use starknet::ContractAddress;
use crate::base::types::{Campaigns, Donations};

/// Interface for the  Campaign Donation contract
#[starknet::interface]
pub trait ICampaignDonation<TContractState> {
    // *************************************************************************
    //                              EXTERNALS FUNCTIONS
    // *************************************************************************
    fn create_campaign(
        ref self: TContractState,
        campaign_ref: felt252, // (5 character unique character)
        target_amount: u256,
        // asset: felt252 // in what asset are you collecting donation in (STRK, ETH, USDC OR USDT)
    ) -> u256;


    fn donate_to_campaign(ref self: TContractState, campaign_id: u256, amount: u256) -> u256;

    fn withdraw_from_campaign(ref self: TContractState, campaign_id: u256);

    // *************************************************************************
    //                              GETTER FUNCTIONS
    // *************************************************************************

    fn get_campaigns(self: @TContractState) -> Array<Campaigns>;

    fn get_donation(self: @TContractState, campaign_id: u256, donation_id: u256) -> Donations;

    fn get_campaign(self: @TContractState, camapign_id: u256) -> Campaigns;

    fn get_campagin_donations(self: @TContractState, camapign_id: u256) -> Array<Donations>;
}
