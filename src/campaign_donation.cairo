/// CampaignDonation contract implementation
#[starknet::contract]
pub mod CampaignDonation {
    use core::num::traits::{OverflowingAdd, Zero};
    use core::traits::Into;
    use fundable::interfaces::ICampaignDonation::ICampaignDonation;
    use fundable::interfaces::IDonationNFT::{IDonationNFTDispatcher, IDonationNFTDispatcherTrait};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{
        ClassHash, ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
    use crate::base::errors::Errors::{
        CALLER_NOT_CAMPAIGN_OWNER, CALLER_NOT_DONOR, CAMPAIGN_CLOSED, CAMPAIGN_HAS_DONATIONS,
        CAMPAIGN_NOT_CANCELLED, CAMPAIGN_NOT_CLOSED, CAMPAIGN_NOT_FOUND, CAMPAIGN_REF_EMPTY,
        CAMPAIGN_REF_EXISTS, CAMPAIGN_WITHDRAWN, CANNOT_DENOTE_ZERO_AMOUNT, DONATION_NOT_FOUND,
        DOUBLE_WITHDRAWAL, INSUFFICIENT_ALLOWANCE, INSUFFICIENT_BALANCE, INVALID_DONATION_TOKEN,
        MORE_THAN_TARGET, NFT_NOT_CONFIGURED, OPERATION_OVERFLOW, PROTOCOL_FEE_ADDRESS_NOT_SET,
        PROTOCOL_FEE_PERCENTAGE_EXCEED, REFUND_ALREADY_CLAIMED, TARGET_NOT_REACHED, TARGET_REACHED,
        TOTAL_DONATION_AMOUNT, WITHDRAWAL_FAILED, ZERO_ALLOWANCE, ZERO_AMOUNT,
    };
    use crate::base::types::{
        Campaigns, DonationMetadata, DonationResult, Donations,
    };

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
        donation_nft_address: ContractAddress, // Address of the Donation NFT contract
        donor_donations: Map<
            ContractAddress, Vec<(u256, u256)>,
        >, // Map donor_address to Vec of (campaign_id, donation_id)
        refunds_claimed: Map<(u256, ContractAddress), bool>, // Map((campaign_id, donor), claimed)
        donations_by_donor: Map<
            (u256, ContractAddress), u256,
        >, // Map((campaign_id, donor), total_donation)
        /// Protocol fee percentage using 10000 basis points (e.g. 250 = 2.5%). Default is 0.
        protocol_fee_percent: u256,
        protocol_fee_address: ContractAddress,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Campaign: Campaign,
        Donation: Donation,
        CampaignWithdrawal: CampaignWithdrawal,
        CampaignUpdated: CampaignUpdated,
        CampaignCancelled: CampaignCancelled,
        CampaignRefunded: CampaignRefunded,
        BatchDonationProcessed: BatchDonationProcessed,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BatchDonationProcessed {
        #[key]
        pub donor: ContractAddress,
        pub total_campaigns: u32,
        pub successful_donations: u32,
        pub total_amount: u256,
        pub results: Array<DonationResult>,
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

    #[derive(Drop, starknet::Event)]
    pub struct CampaignUpdated {
        #[key]
        pub campaign_id: u256,
        #[key]
        pub new_target: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignCancelled {
        #[key]
        pub campaign_id: u256,
        #[key]
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CampaignRefunded {
        #[key]
        pub campaign_id: u256,
        #[key]
        pub donor: ContractAddress,
        #[key]
        pub amount: u256,
        #[key]
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        token: ContractAddress,
        protocol_fee_address: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.donation_token.write(token);
        self.protocol_fee_address.write(protocol_fee_address);
    }

    #[abi(embed_v0)]
    impl CampaignDonationImpl of ICampaignDonation<ContractState> {
        fn create_campaign(
            ref self: ContractState,
            campaign_ref: felt252,
            target_amount: u256,
            donation_token: ContractAddress,
        ) -> u256 {
            let caller = get_caller_address();
            let timestamp = get_block_timestamp();
            let ref_campaign = campaign_ref.clone();
            let campaign_target_amount = target_amount.clone();
            let campaign_id = self
                ._create_campaign(ref_campaign, campaign_target_amount, donation_token);
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
            let _campaign_id = campaign_id.clone();
            let _amount = amount.clone();
            let donor = get_caller_address();
            let timestamp = get_block_timestamp();
            let donation_id = self._donate_to_campaign(_campaign_id, _amount);
            // Emit donation event
            self
                .emit(
                    Event::Donation(
                        Donation { donor, campaign_id: _campaign_id, amount: _amount, timestamp },
                    ),
                );

            donation_id
        }


        fn withdraw_from_campaign(ref self: ContractState, campaign_id: u256) {
            let caller = get_caller_address();
            let _campaign_id = campaign_id.clone();

            let withdrawn_amount = self._withdraw_from_campaign(_campaign_id);
            let timestamp = get_block_timestamp();

            // emit CampaignWithdrawal event
            self
                .emit(
                    Event::CampaignWithdrawal(
                        CampaignWithdrawal {
                            owner: caller,
                            campaign_id: _campaign_id,
                            amount: withdrawn_amount,
                            timestamp,
                        },
                    ),
                );
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
                donation_id: 0, donor: contract_address_const::<0>(), campaign_id: 0, amount: 0,
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
        fn set_donation_nft_address(
            ref self: ContractState, donation_nft_address: ContractAddress,
        ) {
            // Ensure the caller is the owner
            self.ownable.assert_only_owner();
            // Set the donation NFT address
            self.donation_nft_address.write(donation_nft_address);
        }
        fn mint_donation_nft(
            ref self: ContractState, campaign_id: u256, donation_id: u256,
        ) -> u256 {
            let nft_address = self.donation_nft_address.read();
            assert(nft_address.is_non_zero(), NFT_NOT_CONFIGURED);
            let donation_nft_dispatcher = IDonationNFTDispatcher { contract_address: nft_address };
            // Ensure caller is the donor
            let caller = get_caller_address();
            let donation = self.get_donation(campaign_id, donation_id);
            assert(caller == donation.donor, CALLER_NOT_DONOR);
            let campaign = self.get_campaign(campaign_id);
            let donation_data = DonationMetadata {
                campaign_id,
                campaign_name: campaign.campaign_reference,
                campaign_owner: campaign.owner,
                donation_id,
                donor: donation.donor,
                amount: donation.amount,
                timestamp: get_block_timestamp(),
            };
            // Mint the NFT receipt
            let token_id = donation_nft_dispatcher.mint_receipt(caller, donation_data);
            token_id
        }

        fn get_donations_by_donor(
            self: @ContractState, donor: ContractAddress,
        ) -> Array<(u256, Donations)> {
            let mut donations = ArrayTrait::new();

            // List of (campaign_id, donation_id) for this donor
            let donor_entries = self.donor_donations.entry(donor);

            // Rebuild full donation records from stored entries
            for i in 0..donor_entries.len() {
                let (campaign_id, donation_id) = donor_entries.at(i).read();
                let donation = self.get_donation(campaign_id, donation_id);
                donations.append((campaign_id, donation));
            }

            donations
        }

        fn get_total_donated_by_donor(self: @ContractState, donor: ContractAddress) -> u256 {
            let mut total: u256 = 0;
            let donor_donations = self.get_donations_by_donor(donor);

            // Sum all donation amounts across campaigns
            for (_, donation) in donor_donations {
                let (new_total, overflowed) = total.overflowing_add(donation.amount);
                assert(!overflowed, OPERATION_OVERFLOW);
                total = new_total;
            }

            total
        }

        fn has_donated_to_campaign(
            self: @ContractState, campaign_id: u256, donor: ContractAddress,
        ) -> bool {
            // List of (campaign_id, donation_id) for this donor
            let donor_entries = self.donor_donations.entry(donor);

            // Check if any entry matches the specified campaign_id
            for i in 0..donor_entries.len() {
                let (donor_campaign_id, _) = donor_entries.at(i).read();
                if donor_campaign_id == campaign_id {
                    return true;
                }
            }

            false
        }

        fn update_campaign_target(ref self: ContractState, campaign_id: u256, new_target: u256) {
            let caller = get_caller_address();
            assert(campaign_id > 0, CAMPAIGN_NOT_FOUND);
            assert(campaign_id <= self.campaign_counts.read(), CAMPAIGN_NOT_FOUND);
            let mut campaign = self.get_campaign(campaign_id);
            assert(caller == campaign.owner, CALLER_NOT_CAMPAIGN_OWNER);
            assert(new_target > 0, ZERO_AMOUNT);
            assert(!campaign.is_closed, CAMPAIGN_CLOSED);
            assert(
                !campaign.is_goal_reached, TARGET_REACHED,
            ); // Campaign must not have reached its goal
            assert(
                campaign.current_balance == 0, CAMPAIGN_HAS_DONATIONS,
            ); // Campaign must have no donations
            campaign.target_amount = new_target;
            self.campaigns.write(campaign_id, campaign);
            self.emit(Event::CampaignUpdated(CampaignUpdated { campaign_id, new_target }));
        }

        fn cancel_campaign(ref self: ContractState, campaign_id: u256) {
            let caller = get_caller_address();
            assert(campaign_id > 0, CAMPAIGN_NOT_FOUND);
            assert(campaign_id <= self.campaign_counts.read(), CAMPAIGN_NOT_FOUND);
            let mut campaign = self.get_campaign(campaign_id);
            assert(caller == campaign.owner, CALLER_NOT_CAMPAIGN_OWNER);
            assert(!campaign.is_closed, CAMPAIGN_CLOSED);
            assert(!campaign.is_goal_reached, TARGET_REACHED);
            assert(campaign.withdrawn_amount == 0, CAMPAIGN_WITHDRAWN);
            let timestamp = get_block_timestamp();
            campaign.is_closed = true;
            campaign.is_cancelled = true;
            self.campaigns.write(campaign_id, campaign);
            self.campaign_closed.write(campaign_id, true);
            self.emit(Event::CampaignCancelled(CampaignCancelled { campaign_id, timestamp }));
        }

        fn claim_refund(ref self: ContractState, campaign_id: u256) {
            let caller = get_caller_address();
            assert(campaign_id > 0, CAMPAIGN_NOT_FOUND);
            assert(campaign_id <= self.campaign_counts.read(), CAMPAIGN_NOT_FOUND);
            let mut campaign = self.get_campaign(campaign_id);

            // Check if campaign is cancelled
            assert(campaign.is_cancelled, CAMPAIGN_NOT_CANCELLED);
            assert(campaign.withdrawn_amount == 0, CAMPAIGN_WITHDRAWN);

            // Check if caller has already claimed refund
            assert(!self.refunds_claimed.read((campaign_id, caller)), REFUND_ALREADY_CLAIMED);

            // Get total donation amount directly from mapping
            let total_donation = self.donations_by_donor.read((campaign_id, caller));

            // Ensure caller has donated
            assert(total_donation > 0, DONATION_NOT_FOUND);

            // Transfer tokens back to donor
            let donation_token = self.donation_token.read();
            let token = IERC20Dispatcher { contract_address: donation_token };
            let transfer_success = token.transfer(caller, total_donation);
            assert(transfer_success, WITHDRAWAL_FAILED);

            // Mark refund as claimed
            self.refunds_claimed.write((campaign_id, caller), true);

            // Emit event
            let timestamp = get_block_timestamp();
            self
                .emit(
                    Event::CampaignRefunded(
                        CampaignRefunded {
                            campaign_id, donor: caller, amount: total_donation, timestamp,
                        },
                    ),
                );
        }

        fn batch_donate(ref self: ContractState, campaign_amounts: Array<(u256, u256)>) {
            const MAX_BATCH_SIZE: u32 = 20;

            // Input validation
            assert(campaign_amounts.len() > 0, 'Empty campaign array');
            assert(campaign_amounts.len() <= MAX_BATCH_SIZE, 'Batch size too large');

            let donor = get_caller_address();
            let contract_address = get_contract_address();

            // STEP 1: Gas-optimized validation and total calculation - O(n) complexity
            let total_amount = self._validate_and_calculate_total_optimized(@campaign_amounts);
            assert(total_amount > 0, TOTAL_DONATION_AMOUNT);

            // STEP 2: Token approval and balance checks
            let donation_token = self.donation_token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: donation_token };

            let donor_balance = token_dispatcher.balance_of(donor);
            assert(donor_balance >= total_amount, 'Insufficient balance');

            let allowance = token_dispatcher.allowance(donor, contract_address);
            assert(allowance >= total_amount, 'Insufficient allowance');

            // STEP 3: Single transfer for all donations (optimization)
            let transfer_success = token_dispatcher
                .transfer_from(donor, contract_address, total_amount);
            assert(transfer_success, 'Transfer failed');

            // STEP 4: Process all donations with result tracking
            let mut results: Array<DonationResult> = ArrayTrait::new();
            let mut successful_donations: u32 = 0;
            let mut actual_total_amount: u256 = 0;
            let mut i = 0;

            while i < campaign_amounts.len() {
                let (campaign_id, requested_amount) = *campaign_amounts.at(i);

                // Process donation and get actual amount and donation ID
                let (donation_id, actual_amount) = self
                    ._process_internal_donation_with_return(donor, campaign_id, requested_amount);

                // Track results (only add if donation actually happened)
                if actual_amount > 0 {
                    results
                        .append(
                            DonationResult {
                                campaign_id, amount: actual_amount, success: true, donation_id,
                            },
                        );
                    successful_donations += 1;
                    actual_total_amount += actual_amount;
                }

                i += 1;
            }

            // CRITICAL FIX: Refund any excess if actual total is less than transferred amount
            if actual_total_amount < total_amount {
                let refund_amount = total_amount - actual_total_amount;
                let refund_success = token_dispatcher.transfer(donor, refund_amount);
                assert(refund_success, 'Refund failed');
            }

            // Emit batch event (use actual amount, not pre-calculated amount)
            self
                .emit(
                    Event::BatchDonationProcessed(
                        BatchDonationProcessed {
                            donor,
                            total_campaigns: campaign_amounts.len(),
                            successful_donations,
                            total_amount: actual_total_amount, // Use actual amount, not pre-calculated
                            results,
                        },
                    ),
                );
        }


        fn get_protocol_fee_percent(self: @ContractState) -> u256 {
            self.protocol_fee_percent.read()
        }

        fn set_protocol_fee_percent(ref self: ContractState, new_fee_percent: u256) {
            self.ownable.assert_only_owner();
            assert(new_fee_percent <= 10000, PROTOCOL_FEE_PERCENTAGE_EXCEED);
            self.protocol_fee_percent.write(new_fee_percent);
        }

        fn get_protocol_fee_address(self: @ContractState) -> ContractAddress {
            self.protocol_fee_address.read()
        }

        fn set_protocol_fee_address(ref self: ContractState, new_fee_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self.protocol_fee_address.write(new_fee_address);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _validate_and_calculate_total_optimized(
            self: @ContractState, campaign_amounts: @Array<(u256, u256)>,
        ) -> u256 {
            // STEP 1: Pre-calculate campaign batch totals in single pass O(n)
            let mut campaign_totals: Array<CampaignBatchTotal> = ArrayTrait::new();
            let mut i = 0;

            while i < campaign_amounts.len() {
                let (campaign_id, amount) = *campaign_amounts.at(i);

                // Validate donation amount > 0
                assert(amount > 0, 'Amount must be > 0');

                // Find existing total for this campaign or create new entry
                let mut found = false;
                let mut found_index = 0;
                let mut j = 0;
                while j < campaign_totals.len() {
                    let existing_total = *campaign_totals.at(j); // FIXED: Now works with Copy trait
                    if existing_total.campaign_id == campaign_id {
                        found = true;
                        found_index = j;
                        break;
                    }
                    j += 1;
                }

                if found {
                    // Update existing total (simplified approach - rebuild array)
                    let mut new_totals: Array<CampaignBatchTotal> = ArrayTrait::new();
                    let mut k = 0;
                    while k < campaign_totals.len() {
                        let existing = *campaign_totals.at(k);
                        if k == found_index {
                            new_totals
                                .append(
                                    CampaignBatchTotal {
                                        campaign_id: existing.campaign_id,
                                        total_amount: existing.total_amount + amount,
                                    },
                                );
                        } else {
                            new_totals.append(existing);
                        }
                        k += 1;
                    }
                    campaign_totals = new_totals;
                } else {
                    campaign_totals
                        .append(CampaignBatchTotal { campaign_id, total_amount: amount });
                }

                i += 1;
            }

            // STEP 2: Validate campaigns and calculate effective total O(unique_campaigns)
            let mut total: u256 = 0;
            let mut k = 0;

            while k < campaign_totals.len() {
                let campaign_total = *campaign_totals.at(k); // FIXED: Now works with Copy trait

                // Validate campaign exists and is active
                let campaign = self.campaigns.read(campaign_total.campaign_id);
                assert(!campaign.owner.is_zero(), 'Campaign does not exist');
                assert(!campaign.is_closed, 'Campaign is closed');
                assert(!campaign.is_goal_reached, 'Campaign goal reached');

                // Calculate effective amount with auto-capping
                let remaining = campaign.target_amount - campaign.current_balance;
                let effective_amount = if campaign_total.total_amount > remaining {
                    remaining // Cap to remaining amount
                } else {
                    campaign_total.total_amount // Use full amount
                };

                total += effective_amount;

                // Check for overflow
                assert(total >= effective_amount, 'Total overflow');

                k += 1;
            }

            total
        }

        fn _create_campaign(
            ref self: ContractState,
            campaign_ref: felt252,
            target_amount: u256,
            donation_token: ContractAddress,
        ) -> u256 {
            assert(campaign_ref != '', CAMPAIGN_REF_EMPTY);
            assert(!self.campaign_refs.read(campaign_ref), CAMPAIGN_REF_EXISTS);
            assert(target_amount > 0, ZERO_AMOUNT);
            assert(!donation_token.is_zero(), INVALID_DONATION_TOKEN);
            let campaign_id: u256 = self.campaign_counts.read() + 1;
            let caller = get_caller_address();
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
                donation_token: donation_token,
                is_cancelled: false,
            };

            self.campaigns.write(campaign_id, campaign);
            self.campaign_counts.write(campaign_id);
            self.campaign_refs.write(campaign_ref, true);
            campaign_id
        }

        fn _donate_to_campaign(ref self: ContractState, campaign_id: u256, amount: u256) -> u256 {
            assert(amount > 0, CANNOT_DENOTE_ZERO_AMOUNT);
            let donor = get_caller_address();
            let mut campaign = self.get_campaign(campaign_id);
            let contract_address = get_contract_address();

            let donation_token = campaign.donation_token;
            // cannot send more than target amount
            assert!(amount <= campaign.target_amount, "More than Target");

            let donation_id = self.donation_count.read() + 1;

            // Ensure the campaign is still accepting donations
            assert(!campaign.is_goal_reached, TARGET_REACHED);

            // Prepare the ERC20 interface
            let token_dispatcher = IERC20Dispatcher { contract_address: donation_token };

            let donor_balance = token_dispatcher.balance_of(donor);
            assert(donor_balance >= amount, INSUFFICIENT_BALANCE);

            let allowance = token_dispatcher.allowance(donor, contract_address);
            assert(allowance >= amount, INSUFFICIENT_ALLOWANCE);

            // Transfer funds to contract — requires prior approval
            token_dispatcher.transfer_from(donor, contract_address, amount);

            // Update campaign amount
            campaign.current_balance = campaign.current_balance + amount;

            // Update donor's total donation for this campaign
            let current_total = self.donations_by_donor.read((campaign_id, donor));
            self.donations_by_donor.write((campaign_id, donor), current_total + amount);

            // If goal reached, mark as closed
            if (campaign.current_balance >= campaign.target_amount) {
                campaign.is_goal_reached = true;
                campaign.is_closed = true;
            }

            self.campaigns.write(campaign_id, campaign);

            // Create donation record
            let donation = Donations { donation_id, donor, campaign_id, amount };

            // Properly append to the Vec using push
            self.donations.entry(campaign_id).push(donation);

            self.donation_count.write(donation_id);

            // Save donation reference for the donor
            self.donor_donations.entry(donor).push((campaign_id, donation_id));

            // Update the per-campaign donation count
            let campaign_donation_count = self.donation_counts.read(campaign_id);
            self.donation_counts.write(campaign_id, campaign_donation_count + 1);
            donation_id
        }

        fn _withdraw_from_campaign(ref self: ContractState, campaign_id: u256) -> u256 {
            let caller = get_caller_address();
            let mut campaign = self.campaigns.read(campaign_id);
            let campaign_owner = campaign.owner;
            assert(caller == campaign_owner, CALLER_NOT_CAMPAIGN_OWNER);

            assert(campaign.is_closed, CAMPAIGN_NOT_CLOSED);

            assert(!self.campaign_withdrawn.read(campaign_id), DOUBLE_WITHDRAWAL);

            let donation_token = campaign.donation_token;

            let token_dispatcher = IERC20Dispatcher { contract_address: donation_token };

            let withdrawn_amount = campaign.current_balance;
            let protocol_fee = self.calculate_protocol_fee(@withdrawn_amount);

            // transfer protocol fee
            if protocol_fee > 0 {
                let protocol_address = self.protocol_fee_address.read();
                assert(!protocol_address.is_zero(), PROTOCOL_FEE_ADDRESS_NOT_SET);
                let protocol_transfer = token_dispatcher.transfer(protocol_address, protocol_fee);
                assert(protocol_transfer, WITHDRAWAL_FAILED);
            }

            let amount_after_fee = withdrawn_amount - protocol_fee;
            let transfer_from = token_dispatcher.transfer(campaign_owner, amount_after_fee);
            assert(transfer_from, WITHDRAWAL_FAILED);

            campaign.withdrawn_amount = campaign.withdrawn_amount + withdrawn_amount;
            campaign.is_goal_reached = true;
            self.campaign_closed.write(campaign_id, true);
            self.campaigns.write(campaign_id, campaign);
            self.campaign_withdrawn.write(campaign_id, true);
            withdrawn_amount
        }

        fn _process_internal_donation_with_return(
            ref self: ContractState, donor: ContractAddress, campaign_id: u256, amount: u256,
        ) -> (u256, u256) {
            let mut campaign = self.campaigns.read(campaign_id);
            let timestamp = get_block_timestamp();

            // Calculate actual donation amount (don't exceed target) - AUTO-CAPPING
            let remaining_amount = campaign.target_amount - campaign.current_balance;
            let actual_amount = if amount > remaining_amount {
                remaining_amount
            } else {
                amount
            };

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
            self
                .emit(
                    Event::Donation(
                        Donation { donor, campaign_id, amount: actual_amount, timestamp },
                    ),
                );

            // Return both donation_id and actual_amount for tracking
            (donation_id, actual_amount)
        }
    }


    fn calculate_protocol_fee(self: @ContractState, total_amount: @u256) -> u256 {
        let fee_percent = self.protocol_fee_percent.read();
        let protocol_fee = (*total_amount * fee_percent) / 10000;
        protocol_fee
    }


    fn get_asset_address(self: @ContractState, token_name: felt252) -> ContractAddress {
        let mut token_address: ContractAddress = contract_address_const::<0>();
        if token_name == 'USDC' || token_name == 'usdc' {
            token_address =
                contract_address_const::<
                    0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8,
                >();
        }
        if token_name == 'STRK' || token_name == 'strk' {
            token_address =
                contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                >();
        }
        if token_name == 'ETH' || token_name == 'eth' {
            token_address =
                contract_address_const::<
                    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
                >();
        }
        if token_name == 'USDT' || token_name == 'usdt' {
            token_address =
                contract_address_const::<
                    0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8,
                >();
        }

        token_address
    }

    fn _validate_and_calculate_total(
        self: @ContractState, campaign_amounts: @Array<(u256, u256)>,
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
        }

        total
    }

    /// GAS-OPTIMIZED: O(n) validation that handles mid-batch campaign completion
    /// Pre-calculates campaign totals to avoid nested loops (was O(n²), now O(n))
    /// FIXED: Removed dictionary approach to avoid Copy trait issues
    fn _validate_and_calculate_total_optimized(
        self: @ContractState, campaign_amounts: @Array<(u256, u256)>,
    ) -> u256 {
        // STEP 1: Pre-calculate campaign batch totals in single pass O(n)
        let mut campaign_totals: Array<CampaignBatchTotal> = ArrayTrait::new();
        let mut i = 0;

        while i < campaign_amounts.len() {
            let (campaign_id, amount) = *campaign_amounts.at(i);

            // Validate donation amount > 0
            assert(amount > 0, 'Amount must be > 0');

            // Find existing total for this campaign or create new entry
            let mut found = false;
            let mut found_index = 0;
            let mut j = 0;
            while j < campaign_totals.len() {
                let existing_total = *campaign_totals.at(j); // FIXED: Now works with Copy trait
                if existing_total.campaign_id == campaign_id {
                    found = true;
                    found_index = j;
                    break;
                }
                j += 1;
            }

            if found {
                // Update existing total (simplified approach - rebuild array)
                let mut new_totals: Array<CampaignBatchTotal> = ArrayTrait::new();
                let mut k = 0;
                while k < campaign_totals.len() {
                    let existing = *campaign_totals.at(k);
                    if k == found_index {
                        new_totals
                            .append(
                                CampaignBatchTotal {
                                    campaign_id: existing.campaign_id,
                                    total_amount: existing.total_amount + amount,
                                },
                            );
                    } else {
                        new_totals.append(existing);
                    }
                    k += 1;
                }
                campaign_totals = new_totals;
            } else {
                campaign_totals.append(CampaignBatchTotal { campaign_id, total_amount: amount });
            }

            i += 1;
        }

        // STEP 2: Validate campaigns and calculate effective total O(unique_campaigns)
        let mut total: u256 = 0;
        let mut k = 0;

        while k < campaign_totals.len() {
            let campaign_total = *campaign_totals.at(k); // FIXED: Now works with Copy trait

            // Validate campaign exists and is active
            let campaign = self.campaigns.read(campaign_total.campaign_id);
            assert(!campaign.owner.is_zero(), 'Campaign does not exist');
            assert(!campaign.is_closed, 'Campaign is closed');
            assert(!campaign.is_goal_reached, 'Campaign goal reached');

            // Calculate effective amount with auto-capping
            let remaining = campaign.target_amount - campaign.current_balance;
            let effective_amount = if campaign_total.total_amount > remaining {
                remaining // Cap to remaining amount
            } else {
                campaign_total.total_amount // Use full amount
            };

            total += effective_amount;

            // Check for overflow
            assert(total >= effective_amount, 'Total overflow');

            k += 1;
        }

        total
    }
}

#[abi(embed_v0)]
impl UpgradeableImpl of IUpgradeable<ContractState> {
    fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
        self.ownable.assert_only_owner();
        self.upgradeable.upgrade(new_class_hash);
    }
}

