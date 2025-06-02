/// CampaignDonation contract implementation
#[starknet::contract]
pub mod CampaignDonation {
    use core::num::traits::Zero;
    use core::traits::Into;
    use fundable::interfaces::ICampaignDonation::{ICampaignDonation, DonationResult, BatchDonationProcessed};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::base::errors::Errors::{
        CALLER_NOT_CAMPAIGN_OWNER, CAMPAIGN_NOT_CLOSED, CAMPAIGN_REF_EMPTY, CAMPAIGN_REF_EXISTS,
        CANNOT_DENOTE_ZERO_AMOUNT, DOUBLE_WITHDRAWAL, TARGET_REACHED, WITHDRAWAL_FAILED, ZERO_AMOUNT,
    };
    use crate::base::types::{Campaigns, Donations};

    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        campaign_counts: u256,
        campaigns: Map<u256, Campaigns>, // (campaign_id, Campaigns)
        donations: Map<u256, Vec<Donations>>, // MAP((campaign_id, donation_id), donation)
        donation_counts: Map<u256, u256>,
        donation_count: u256,
        campaign_refs: Map<felt252, bool>, // All campaign ref to use for is_campaign_ref_exists
        campaign_closed: Map<u256, bool>, // Map campaign ids to closing boolean
        campaign_withdrawn: Map<u256, bool>, //Map campaign ids to whether they have been withdrawn
        donation_token: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Campaign: Campaign,
        Donation: Donation,
        CampaignWithdrawal: CampaignWithdrawal,
        BatchDonationProcessed: BatchDonationProcessed, // ADDED: Missing batch event
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Campaign {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub campaign_reference: felt252,
        #[key]
        pub campaign_id: u256,
        #[key]
        pub target_amount: u256,
        #[key]
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Donation {
        #[key]
        pub donor: ContractAddress,
        #[key]
        pub campaign_id: u256,
        #[key]
        pub amount: u256,
        #[key]
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignWithdrawal {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub campaign_id: u256,
        #[key]
        pub amount: u256,
        #[key]
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, token: ContractAddress) {
        self.ownable.initializer(owner);
        self.donation_token.write(token);
    }

    #[abi(embed_v0)]
    impl CampaignDonationImpl of ICampaignDonation<ContractState> {
        fn create_campaign(
            ref self: ContractState, campaign_ref: felt252, target_amount: u256,
        ) -> u256 {
            assert(campaign_ref != '', CAMPAIGN_REF_EMPTY);
            assert(!self.campaign_refs.read(campaign_ref), CAMPAIGN_REF_EXISTS);
            assert(target_amount > 0, ZERO_AMOUNT);
            let campaign_id: u256 = self.campaign_counts.read() + 1;
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let current_balance: u256 = 0;
            let withdrawn_amount: u256 = 0;
            let campaign = Campaigns {
                campaign_id,
                owner: caller,
                target_amount,
                current_balance,
                withdrawn_amount,
                campaign_reference: campaign_ref,
                is_closed: false,
                is_goal_reached: false,
                donation_token: self.donation_token.read(),
            };

            self.campaigns.write(campaign_id, campaign);
            self.campaign_counts.write(campaign_id);
            self.campaign_refs.write(campaign_ref, true);
            self
                .emit(
                    Event::Campaign(
                        Campaign {
                            owner: caller,
                            campaign_reference: campaign_ref,
                            campaign_id,
                            target_amount,
                            timestamp,
                        },
                    ),
                );

            campaign_id
        }

        fn donate_to_campaign(ref self: ContractState, campaign_id: u256, amount: u256) -> u256 {
            assert(amount > 0, CANNOT_DENOTE_ZERO_AMOUNT);
            let donor = get_caller_address();
            let mut campaign = self.get_campaign(campaign_id);
            let contract_address = get_contract_address();
            let donation_token = self.donation_token.read();
            // cannot send more than target amount
            assert!(amount <= campaign.target_amount, "Error: More than Target");

            let donation_id = self.donation_count.read() + 1;

            // Ensure the campaign is still accepting donations
            assert(!campaign.is_goal_reached, TARGET_REACHED);

            // Prepare the ERC20 interface
            let token_dispatcher = IERC20Dispatcher { contract_address: donation_token };

            // Transfer funds to contract — requires prior approval
            token_dispatcher.transfer_from(donor, contract_address, amount);

            // Update campaign amount
            campaign.current_balance = campaign.current_balance + amount;

            // If goal reached, mark as closed
            if (campaign.current_balance >= campaign.target_amount) {
                campaign.is_goal_reached = true;
                campaign.is_closed = true;
            }

            self.campaigns.write(campaign_id, campaign);

            // Create donation record
            let donation = Donations { donation_id, donor, campaign_id, amount };

            self.donations.entry(campaign_id).push(donation);

            self.donation_count.write(donation_id);

            // Update the per-campaign donation count
            let campaign_donation_count = self.donation_counts.read(campaign_id);
            self.donation_counts.write(campaign_id, campaign_donation_count + 1);
            let timestamp = get_block_timestamp();
            // Emit donation event
            self.emit(Event::Donation(Donation { donor, campaign_id, amount, timestamp }));

            donation_id
        }

        fn withdraw_from_campaign(ref self: ContractState, campaign_id: u256) {
            let caller = get_caller_address();
            let mut campaign = self.campaigns.read(campaign_id);
            let campaign_owner = campaign.owner;
            assert(caller == campaign_owner, CALLER_NOT_CAMPAIGN_OWNER);
            campaign.is_goal_reached = true;

            assert(campaign.is_closed, CAMPAIGN_NOT_CLOSED);
            assert(!self.campaign_withdrawn.read(campaign_id), DOUBLE_WITHDRAWAL);

            let donation_token = self.donation_token.read();
            let token = IERC20Dispatcher { contract_address: donation_token };

            let withdrawn_amount = campaign.current_balance;
            let transfer_from = token.transfer(campaign_owner, withdrawn_amount);

            campaign.withdrawn_amount = campaign.withdrawn_amount + withdrawn_amount;
            campaign.is_goal_reached = true;
            self.campaign_closed.write(campaign_id, true);
            self.campaigns.write(campaign_id, campaign);
            assert(transfer_from, WITHDRAWAL_FAILED);
            let timestamp = get_block_timestamp();
            // emit CampaignWithdrawal event
            self
                .emit(
                    Event::CampaignWithdrawal(
                        CampaignWithdrawal {
                            owner: caller, campaign_id, amount: withdrawn_amount, timestamp,
                        },
                    ),
                );
        }

        /// Batch donations to multiple campaigns
        /// All-or-Nothing approach: if any donation fails, entire transaction reverts
        /// 
        /// Requirements:
        /// - campaign_amounts must not be empty and must not exceed MAX_BATCH_SIZE (20)
        /// - All campaign IDs must exist and be active
        /// - Total donation amount must not exceed donor's balance and allowance
        /// - Individual donations that exceed remaining campaign target will be auto-capped
        ///
        /// Effects:
        /// - Transfers total amount from donor to contract in single transaction
        /// - Updates campaign raised amounts and donation records
        /// - Emits individual Donation events and one BatchDonationProcessed event
        ///
        /// Note: Unlike single donations, batch donations automatically cap amounts
        /// that exceed the remaining needed to reach campaign targets
        fn batch_donate(
            ref self: ContractState,
            campaign_amounts: Array<(u256, u256)>
        ) {
            const MAX_BATCH_SIZE: u32 = 20;
            
            // Input validation
            assert(campaign_amounts.len() > 0, 'Empty campaign array');
            assert(campaign_amounts.len() <= MAX_BATCH_SIZE, 'Batch size too large');
            
            let donor = get_caller_address();
            let contract_address = get_contract_address();
            
            // STEP 1: Validate all campaigns and calculate total amount
            // FIXED: Now handles mid-batch campaign completion properly
            let total_amount = self._validate_and_calculate_total_dynamic(@campaign_amounts);
            assert(total_amount > 0, 'Total amount must be > 0');
            
            // STEP 2: Token approval and balance checks
            let donation_token = self.donation_token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: donation_token };
            
            let donor_balance = token_dispatcher.balance_of(donor);
            assert(donor_balance >= total_amount, 'Insufficient balance');
            
            let allowance = token_dispatcher.allowance(donor, contract_address);
            assert(allowance >= total_amount, 'Insufficient allowance');
            
            // STEP 3: Single transfer for all donations (optimization)
            let transfer_success = token_dispatcher.transfer_from(
                donor, 
                contract_address, 
                total_amount
            );
            assert(transfer_success, 'Transfer failed');
            
            // STEP 4: Process all donations with result tracking
            // FIXED: Added proper result tracking and event emission
            let mut results: Array<DonationResult> = ArrayTrait::new();
            let mut successful_donations: u32 = 0;
            let mut actual_total_amount: u256 = 0;
            let mut i = 0;
            
            while i < campaign_amounts.len() {
                let (campaign_id, requested_amount) = *campaign_amounts.at(i);
                
                // Process donation and get actual amount and donation ID
                let (donation_id, actual_amount) = self._process_internal_donation_with_return(
                    donor, 
                    campaign_id, 
                    requested_amount
                );
                
                // Track results (only add if donation actually happened)
                if actual_amount > 0 {
                    results.append(DonationResult {
                        campaign_id,
                        amount: actual_amount,
                        success: true,
                        donation_id
                    });
                    successful_donations += 1;
                    actual_total_amount += actual_amount;
                }
                
                i += 1;
            };
            
            // FIXED: Emit batch event - THIS WAS MISSING!
            self.emit(Event::BatchDonationProcessed(BatchDonationProcessed {
                donor,
                total_campaigns: campaign_amounts.len(),
                successful_donations,
                total_amount: actual_total_amount,
                results
            }));
        }

        fn get_donation(self: @ContractState, campaign_id: u256, donation_id: u256) -> Donations {
            // Since donations are stored sequentially in the Vec, we need to find the index
            // The donation_id is global, so we need to iterate through the Vec to find it
            let vec_len = self.donations.entry(campaign_id).len();
            let mut i: u64 = 0;

            while i < vec_len {
                let donation = self.donations.entry(campaign_id).at(i).read();
                if donation.donation_id == donation_id {
                    return donation;
                }
                i += 1;
            }

            // Return empty donation if not found
            Donations {
                donation_id: 0, donor: starknet::contract_address_const::<0>(), campaign_id: 0, amount: 0,
            }
        }

        fn get_campaigns(self: @ContractState) -> Array<Campaigns> {
            let mut campaigns = ArrayTrait::new();
            let campaigns_count = self.campaign_counts.read();

            // Iterate through all campaign IDs (1 to campaigns_count)
            let mut i: u256 = 1;
            while i <= campaigns_count {
                let campaign = self.campaigns.read(i);
                campaigns.append(campaign);
                i += 1;
            }

            campaigns
        }

        fn get_campaign_donations(self: @ContractState, campaign_id: u256) -> Array<Donations> {
            let mut donations = ArrayTrait::new();

            // Get the length of the Vec for this campaign
            let vec_len = self.donations.entry(campaign_id).len();

            // Iterate through all donations in the Vec
            let mut i: u64 = 0;
            while i < vec_len {
                let donation = self.donations.entry(campaign_id).at(i).read();
                donations.append(donation);
                i += 1;
            }

            donations
        }

        fn get_campaign(self: @ContractState, campaign_id: u256) -> Campaigns {
            let campaign: Campaigns = self.campaigns.read(campaign_id);
            campaign
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn get_asset_address(self: @ContractState, token_name: felt252) -> ContractAddress {
            let mut token_address: ContractAddress = starknet::contract_address_const::<0>();
            if token_name == 'USDC' || token_name == 'usdc' {
                token_address =
                    starknet::contract_address_const::<
                        0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8,
                    >();
            }
            if token_name == 'STRK' || token_name == 'strk' {
                token_address =
                    starknet::contract_address_const::<
                        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                    >();
            }
            if token_name == 'ETH' || token_name == 'eth' {
                token_address =
                    starknet::contract_address_const::<
                        0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
                    >();
            }
            if token_name == 'USDT' || token_name == 'usdt' {
                token_address =
                    starknet::contract_address_const::<
                        0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8,
                    >();
            }

            token_address
        }

        fn _validate_and_calculate_total(
            self: @ContractState, 
            campaign_amounts: @Array<(u256, u256)>
        ) -> u256 {
            let mut total: u256 = 0;
            let mut i = 0;
            
            while i < campaign_amounts.len() {
                let (campaign_id, amount) = *campaign_amounts.at(i);
                
                // Validate donation amount > 0
                assert(amount > 0, 'Amount must be > 0');
                
                // Validate campaign exists
                let campaign = self.campaigns.read(campaign_id);
                assert(!campaign.owner.is_zero(), 'Campaign does not exist');
                
                // Check campaign is active (not closed/goal reached)
                assert(!campaign.is_closed, 'Campaign is closed');
                assert(!campaign.is_goal_reached, 'Campaign goal reached');
                
                // Check for integer overflow in total calculation
                let new_total = total + amount;
                assert(new_total >= total, 'Amount overflow');
                total = new_total;
                
                i += 1;
            };
            
            total
        }

        /// FIXED: Enhanced validation that handles mid-batch campaign completion
        /// This improved validation considers cumulative donations within the batch
        /// Using Array-based tracking instead of Felt252Dict for better compatibility
        fn _validate_and_calculate_total_dynamic(
            self: @ContractState, 
            campaign_amounts: @Array<(u256, u256)>
        ) -> u256 {
            let mut total: u256 = 0;
            let mut i = 0;
            
            while i < campaign_amounts.len() {
                let (campaign_id, amount) = *campaign_amounts.at(i);
                
                // Validate donation amount > 0
                assert(amount > 0, 'Amount must be > 0');
                
                // Validate campaign exists
                let campaign = self.campaigns.read(campaign_id);
                assert(!campaign.owner.is_zero(), 'Campaign does not exist');
                
                // Check campaign is active (not closed/goal reached)
                assert(!campaign.is_closed, 'Campaign is closed');
                assert(!campaign.is_goal_reached, 'Campaign goal reached');
                
                // Calculate cumulative amount for this campaign in the batch (simplified)
                let mut current_batch_total: u256 = 0;
                let mut j = 0;
                while j <= i {
                    let (check_campaign_id, check_amount) = *campaign_amounts.at(j);
                    if check_campaign_id == campaign_id {
                        current_batch_total += check_amount;
                    }
                    j += 1;
                };
                
                // Check if the cumulative amount exceeds remaining target
                let remaining = campaign.target_amount - campaign.current_balance;
                let effective_amount = if current_batch_total > remaining {
                    // Calculate how much of this specific donation can be used
                    let previous_batch_total = current_batch_total - amount;
                    if previous_batch_total >= remaining {
                        0 // This donation would be completely capped
                    } else {
                        remaining - previous_batch_total // Partial amount
                    }
                } else {
                    amount // Full amount can be used
                };
                
                // Add to total (will be the actual amount after capping)
                total = total + effective_amount;
                
                // Check for overflow
                assert(total >= effective_amount, 'Total overflow');
                
                i += 1;
            };
            
            total
        }

        fn _process_internal_donation(
            ref self: ContractState,
            donor: ContractAddress,
            campaign_id: u256,
            amount: u256
        ) {
            // FIXED: Use the new function for backward compatibility
            let (_donation_id, _actual_amount) = self._process_internal_donation_with_return(donor, campaign_id, amount);
        }

        /// FIXED: Process internal donation with return values for batch tracking
        /// If amount exceeds the remaining needed to hit campaign.target_amount, 
        /// it is automatically reduced to that remaining amount.
        fn _process_internal_donation_with_return(
            ref self: ContractState,
            donor: ContractAddress,
            campaign_id: u256,
            amount: u256
        ) -> (u256, u256) {
            let mut campaign = self.campaigns.read(campaign_id);
            let timestamp = get_block_timestamp();
            
            // Calculate actual donation amount (don't exceed target) - AUTO-CAPPING
            let remaining_amount = campaign.target_amount - campaign.current_balance;
            let actual_amount = if amount > remaining_amount { remaining_amount } else { amount };
            
            // Skip if no amount to donate (campaign already fully funded)
            if actual_amount == 0 {
                return (0, 0);
            }
            
            // Get next donation ID
            let donation_id = self.donation_count.read() + 1;
            
            // Update campaign amount
            campaign.current_balance = campaign.current_balance + actual_amount;
            
            // If goal reached, mark as closed
            if campaign.current_balance >= campaign.target_amount {
                campaign.is_goal_reached = true;
                campaign.is_closed = true;
            }
            
            self.campaigns.write(campaign_id, campaign);
            
            // Create donation record
            let donation = Donations { donation_id, donor, campaign_id, amount: actual_amount };
            
            // Properly append to the Vec using push
            self.donations.entry(campaign_id).push(donation);
            
            self.donation_count.write(donation_id);
            
            // Update the per-campaign donation count
            let campaign_donation_count = self.donation_counts.read(campaign_id);
            self.donation_counts.write(campaign_id, campaign_donation_count + 1);
            
            // Emit donation event for each successful donation
            self.emit(Event::Donation(Donation { donor, campaign_id, amount: actual_amount, timestamp }));
            
            // Return both donation_id and actual_amount for tracking
            (donation_id, actual_amount)
        }
    }
}