/// CampaignDonation contract implementation
#[starknet::contract]
pub mod CampaignDonation {
    use core::num::traits::Zero;
    use core::traits::Into;
    use fundable::interfaces::ICampaignDonation::ICampaignDonation;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{
        ClassHash, ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
    use crate::base::errors::Errors::{
        CALLER_NOT_CAMPAIGN_OWNER, CAMPAIGN_NOT_CLOSED, CAMPAIGN_REF_EMPTY, CAMPAIGN_REF_EXISTS,
        CANNOT_DENOTE_ZERO_AMOUNT, DOUBLE_WITHDRAWAL, INSUFFICIENT_ALLOWANCE, MORE_THAN_TARGET,
        TARGET_NOT_REACHED, TARGET_REACHED, WITHDRAWAL_FAILED, ZERO_ALLOWANCE, ZERO_AMOUNT,
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
        // campaign_donation: Map<
        //     (ContractAddress, u256), Donation,
        // >,
        // map(<donor_address, campaign_id>, Donation)
        //  donations: Map<u256, (ContractAddress, Donation)>
        // donations: Map<(ContractAddress, u256), Donations>,
        donations: Map<u256, Map<u256, Donations>>, // map<campaign_id, map<dontionid, donation>>
        donation_counts: Map<u256, u256>,
        donation_count: u256,
        // cmapaign_withdrawal: Map<
        //     (ContractAddress, u256), CampaignWithdrawal,
        // >, // map<(campaign_owner, campaign_id), CampaignWithdrawal>
        // Track existing campaign refs
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
            let current_amount: u256 = 0;
            let campaign = Campaigns {
                campaign_id,
                owner: caller,
                target_amount,
                current_amount,
                campaign_reference: campaign_ref,
                is_closed: false,
                is_goal_reached: false,
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
            let timestamp = get_block_timestamp();
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
            campaign.current_amount = campaign.current_amount + amount;

            // If goal reached, mark as closed
            if (campaign.current_amount >= campaign.target_amount) {
                campaign.is_goal_reached = true;
                campaign.is_closed = true;
            }

            self.campaigns.write(campaign_id, campaign);

            // Create donation record
            let donation = Donations { donation_id, donor, campaign_id, amount };

            self.donations.entry(campaign_id).entry(donation_id).write(donation);

            self.donation_count.write(donation_id);

            // Update the per-campaign donation count
            let campaign_donation_count = self.donation_counts.read(campaign_id);
            self.donation_counts.write(campaign_id, campaign_donation_count + 1);

            // Emit donation event
            self.emit(Event::Donation(Donation { donor, campaign_id, amount, timestamp }));

            donation_id
        }


        fn withdraw_from_campaign(ref self: ContractState, campaign_id: u256) {
            let caller = get_caller_address();
            let mut campaign = self.campaigns.read(campaign_id);
            let campaign_owner = campaign.owner;
            assert(caller == campaign_owner, CALLER_NOT_CAMPAIGN_OWNER);
            assert(campaign.current_amount >= campaign.target_amount, TARGET_NOT_REACHED);
            campaign.is_goal_reached = true;

            let this_contract = get_contract_address();

            assert(campaign.is_closed, CAMPAIGN_NOT_CLOSED);

            assert(!self.campaign_withdrawn.read(campaign_id), DOUBLE_WITHDRAWAL);

            let donation_token = self.donation_token.read();

            let token = IERC20Dispatcher { contract_address: donation_token };

            let transfer_from = token.transfer(campaign_owner, campaign.target_amount);

            campaign.is_goal_reached = true;
            self.campaign_closed.write(campaign_id, true);
            self.campaigns.write(campaign_id, campaign);
            assert(transfer_from, WITHDRAWAL_FAILED);
        }

        fn get_donation(self: @ContractState, campaign_id: u256, donation_id: u256) -> Donations {
            let donations: Donations = self.donations.entry(campaign_id).entry(donation_id).read();
            donations
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

        fn get_campagin_donations(self: @ContractState, camapign_id: u256) -> Array<Donations> {
            let mut donations = ArrayTrait::new();

            // Get the total number of donations expected for this campaign
            let campaign_donation_count = self.donation_counts.read(camapign_id);

            // Early return if no donations exist
            if campaign_donation_count == 0 {
                return donations;
            }

            // Get the maximum global donation ID
            let max_donation_id = self.donation_count.read();

            // Track found donations
            let mut found_count: u256 = 0;

            // Check each possible donation ID
            let mut id: u256 = 1;
            while id <= max_donation_id && found_count < campaign_donation_count {
                // Try to read the donation
                let donation = self.donations.entry(camapign_id).entry(id).read();

                // Only add valid donations for this campaign
                if donation.campaign_id == camapign_id && donation.donation_id == id {
                    donations.append(donation);
                    found_count += 1;
                }

                id += 1;
            }

            donations
        }

        fn get_campaign(self: @ContractState, camapign_id: u256) -> Campaigns {
            let campaign: Campaigns = self.campaigns.read(camapign_id);
            campaign
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
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
    }
}
