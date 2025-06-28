use core::option::Option;
use starknet::ContractAddress;
use crate::base::types::{Campaigns, Donations};

/// Interface for the Campaign Donation contract
///
/// This interface defines the core functionality for managing crowdfunding campaigns,
/// including creating campaigns, accepting donations, and withdrawing funds.
#[starknet::interface]
pub trait ICampaignDonation<TContractState> {
    // *************************************************************************
    //                              EXTERNAL FUNCTIONS
    // *************************************************************************

    /// Creates a new fundraising campaign
    ///
    /// # Arguments
    /// * `campaign_ref` - A unique 5-character identifier for the campaign
    /// * `target_amount` - The fundraising goal amount in the donation token
    ///
    /// # Returns
    /// * `u256` - The newly created campaign's ID
    ///
    /// # Panics
    /// * If `campaign_ref` is empty
    /// * If `campaign_ref` already exists
    /// * If `target_amount` is zero
    fn create_campaign(
        ref self: TContractState, campaign_ref: felt252, target_amount: u256,
    ) -> u256;

    /// Makes a donation to a specific campaign
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign to donate to
    /// * `amount` - The amount to donate in the campaign's donation token
    ///
    /// # Returns
    /// * `u256` - The donation ID for this contribution
    ///
    /// # Requirements
    /// * Donor must have approved the contract to spend the donation amount
    /// * Campaign must not have reached its goal yet
    /// * Amount must be greater than zero
    /// * Amount cannot exceed the campaign's target amount
    ///
    /// # Effects
    /// * Transfers tokens from donor to contract
    /// * Updates campaign balance
    /// * Marks campaign as closed if target is reached
    fn donate_to_campaign(ref self: TContractState, campaign_id: u256, amount: u256) -> u256;

    /// Withdraws all funds from a completed campaign
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign to withdraw from
    ///
    /// # Requirements
    /// * Caller must be the campaign owner
    /// * Campaign must be closed (goal reached)
    /// * Funds must not have been withdrawn already
    ///
    /// # Effects
    /// * Transfers all campaign funds to the campaign owner
    /// * Marks the campaign as withdrawn
    /// * Emits a CampaignWithdrawal event
    fn withdraw_from_campaign(ref self: TContractState, campaign_id: u256);

    // *************************************************************************
    //                              GETTER FUNCTIONS
    // *************************************************************************

    /// Retrieves all campaigns created in the contract
    ///
    /// # Returns
    /// * `Array<Campaigns>` - An array containing all campaign data
    fn get_campaigns(self: @TContractState) -> Array<Campaigns>;

    /// Retrieves a specific donation by campaign and donation ID
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign
    /// * `donation_id` - The ID of the donation
    ///
    /// # Returns
    /// * `Donations` - The donation data, or an empty donation struct if not found
    fn get_donation(self: @TContractState, campaign_id: u256, donation_id: u256) -> Donations;

    /// Retrieves detailed information about a specific campaign
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign to query
    ///
    /// # Returns
    /// * `Campaigns` - The campaign data including owner, target, balance, etc.
    fn get_campaign(self: @TContractState, campaign_id: u256) -> Campaigns;

    /// Retrieves all donations made to a specific campaign
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign
    ///
    /// # Returns
    /// * `Array<Donations>` - An array of all donations made to the campaign
    fn get_campaign_donations(self: @TContractState, campaign_id: u256) -> Array<Donations>;
    /// Sets the address of the donation NFT contract
    ///
    /// # Arguments
    /// * `donation_nft_address` - The address of the donation NFT contract
    ///
    fn set_donation_nft_address(ref self: TContractState, donation_nft_address: ContractAddress);
    /// Mint NFT receipt for a donation
    ///
    /// # Arguments
    /// * `campaign_id` - The ID of the campaign associated with the donation
    /// * `donation_id` - The ID of the donation to mint an NFT for
    ///
    /// # Returns
    /// * `u256` - The token ID of the minted NFT
    fn mint_donation_nft(ref self: TContractState, campaign_id: u256, donation_id: u256) -> u256;
    // *************************************************************************
    //                        USER EXPERIENCE ENHANCEMENTS
    // *************************************************************************

    /// Gets all active (non-closed) campaigns
    ///
    /// # Returns
    /// * `Array<Campaigns>` - Array of campaigns that are still accepting donations
    // fn get_active_campaigns(self: @TContractState) -> Array<Campaigns>;

    /// Gets all campaigns created by a specific address
    ///
    /// # Arguments
    /// * `owner` - The address of the campaign creator
    ///
    /// # Returns
    /// * `Array<Campaigns>` - Array of campaigns created by the owner
    // fn get_campaigns_by_owner(self: @TContractState, owner: ContractAddress) -> Array<Campaigns>;

    /// Gets a campaign by its unique reference identifier
    ///
    /// # Arguments
    /// * `campaign_ref` - The unique 5-character campaign reference
    ///
    /// # Returns
    /// * `Option<Campaigns>` - The campaign if found, None otherwise
    // fn get_campaign_by_ref(self: @TContractState, campaign_ref: felt252) -> Option<Campaigns>;

    // *************************************************************************
    //                           DONOR EXPERIENCE
    // *************************************************************************

    /// Gets all donations made by a specific donor across all campaigns
    ///
    /// # Arguments
    /// * `donor` - The address of the donor
    ///
    /// # Returns
    /// * `Array<(u256, Donations)>` - Array of tuples (campaign_id, donation)
    fn get_donations_by_donor(
        self: @TContractState, donor: ContractAddress,
    ) -> Array<(u256, Donations)>;

    /// Gets the total amount donated by a specific address
    ///
    /// # Arguments
    /// * `donor` - The address of the donor
    ///
    /// # Returns
    /// * `u256` - Total amount donated across all campaigns
    fn get_total_donated_by_donor(self: @TContractState, donor: ContractAddress) -> u256;

    /// Checks if a donor has contributed to a specific campaign
    ///
    /// # Arguments
    /// * `campaign_id` - The campaign ID
    /// * `donor` - The donor address
    ///
    /// # Returns
    /// * `bool` - True if the donor has contributed, false otherwise
    fn has_donated_to_campaign(
        self: @TContractState, campaign_id: u256, donor: ContractAddress,
    ) -> bool;
    // *************************************************************************
    //                        CAMPAIGN MANAGEMENT
    // *************************************************************************

    /// Updates the target amount for a campaign (only by owner before any donations)
    ///
    /// # Arguments
    /// * `campaign_id` - The campaign ID
    /// * `new_target` - The new target amount
    ///
    /// # Requirements
    /// * Caller must be campaign owner
    /// * Campaign must have zero balance
    /// * New target must be greater than zero
    fn update_campaign_target(ref self: TContractState, campaign_id: u256, new_target: u256);

    //     / Cancels a campaign and enables refunds (only if no withdrawals have occurred)
    // /
    // / # Arguments
    // / * `campaign_id` - The campaign ID
    // /
    // / # Requirements
    // / * Caller must be campaign owner
    // / * Campaign must not be withdrawn
    // / * Campaign must not have reached its goal
    fn cancel_campaign(ref self: TContractState, campaign_id: u256);

    //     / Allows donors to claim refunds from cancelled campaigns
    // /
    // / # Arguments
    // / * `campaign_id` - The campaign ID
    // /
    // / # Requirements
    // / * Campaign must be cancelled
    // / * Caller must have donated to the campaign
    // / * Refund must not have been claimed already
    fn claim_refund(ref self: TContractState, campaign_id: u256);

    // *************************************************************************
    //                        PROTOCOL FEES
    // *************************************************************************

    /// @notice Gets the current protocol fee percentage
    /// @return The protocol fee percentage (100 = 1%)
    fn get_protocol_fee_percent(self: @TContractState) -> u256;

    /// @notice Sets a new protocol fee percentage
    /// @param new_fee_percent The new fee percentage to set (100 = 1%)
    fn set_protocol_fee_percent(ref self: TContractState, new_fee_percent: u256);

    /// @notice Gets the current protocol fee collection address
    /// @return The address where protocol fees are sent
    fn get_protocol_fee_address(self: @TContractState) -> ContractAddress;

    /// @notice Sets a new protocol fee collection address
    /// @param new_fee_address The new address to collect protocol fees
    fn set_protocol_fee_address(ref self: TContractState, new_fee_address: ContractAddress);
    // *************************************************************************
//                        ANALYTICS & INSIGHTS
// *************************************************************************

    /// Gets the progress percentage of a campaign
///
/// # Arguments
/// * `campaign_id` - The campaign ID
///
/// # Returns
/// * `u8` - Progress percentage (0-100)
// fn get_campaign_progress(self: @TContractState, campaign_id: u256) -> u8;

    /// Gets the number of unique donors for a campaign
///
/// # Arguments
/// * `campaign_id` - The campaign ID
///
/// # Returns
/// * `u32` - Number of unique donors
// fn get_campaign_donor_count(self: @TContractState, campaign_id: u256) -> u32;

    /// Gets campaigns close to reaching their goal
///
/// # Arguments
/// * `threshold_percentage` - Minimum progress percentage (e.g., 80 for 80%+)
///
/// # Returns
/// * `Array<Campaigns>` - Array of campaigns near completion
// fn get_campaigns_near_goal(self: @TContractState, threshold_percentage: u8) ->
// Array<Campaigns>;
}
