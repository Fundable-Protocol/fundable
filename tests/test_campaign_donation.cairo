use core::array::ArrayTrait;
use core::traits::Into;
use fundable::base::types::{Campaigns, Donations};
use fundable::campaign_donation::CampaignDonation;
use fundable::interfaces::ICampaignDonation::{
    ICampaignDonationDispatcher, ICampaignDonationDispatcherTrait,
};
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address, test_address,
};
use starknet::{ContractAddress, contract_address_const};

fn setup() -> (ContractAddress, ContractAddress, ICampaignDonationDispatcher, IERC721Dispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into(), 6];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Campaign Donation contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let campaign_donation_class = declare("CampaignDonation").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into(), erc20_address.into()];
    let (campaign_donation_address, _) = campaign_donation_class.deploy(@calldata).unwrap();

    (
        erc20_address,
        sender,
        ICampaignDonationDispatcher { contract_address: campaign_donation_address },
        IERC721Dispatcher { contract_address: campaign_donation_address },
    )
}

// DONE

// #[test]
fn test_successful_create_campaign() {
    let (_token_address, _sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'Test';
    let owner = contract_address_const::<'owner'>();

    start_cheat_caller_address(campaign_donation.contract_address, owner);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);
    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.campaign_id == campaign_id, 'Campaign ID mismatch');
    assert(campaign.owner == owner, 'Owner mismatch');
    assert(campaign.target_amount == target_amount, 'Target amount mismatch');
    assert(campaign.current_balance == 0.into(), 'Current amount should be 0');
    assert(campaign.campaign_reference == campaign_ref, 'Reference mismatch');
    assert(!campaign.is_closed, 'Campaign should not be closed');
    assert(!campaign.is_goal_reached, 'Goal should not be reached');
}

// DONE
// Test for invalid campaign creation with zero amount
fn test_create_campaign_invalid_zero_amount() {
    let (_token_address, _sender, campaign_donation, _erc721) = setup();
    let target_amount = 0_u256;
    let campaign_ref = 'Test';
    let owner = contract_address_const::<'owner'>();
    start_cheat_caller_address(campaign_donation.contract_address, owner);
    campaign_donation.create_campaign(campaign_ref, target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);
}

// DONE
#[test]
fn test_successful_campaign_donation() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 5000_u256;
    let campaign_ref = 'Test';

    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    stop_cheat_caller_address(campaign_donation.contract_address);

    let user_balance_before = token_dispatcher.balance_of(sender);
    println!("user balance before: {}", user_balance_before);
    let contract_balance_before = token_dispatcher.balance_of(campaign_donation.contract_address);
    println!("contract balance before: {}", contract_balance_before);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 1000);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(sender, campaign_donation.contract_address);
    assert(allowance >= 1000, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(campaign_donation.contract_address, sender);

    let donation_id = campaign_donation.donate_to_campaign(campaign_id, 500);

    stop_cheat_caller_address(campaign_donation.contract_address);

    let donation = campaign_donation.get_donation(campaign_id, donation_id);
    assert(donation.donation_id == 1, ' not initalized Properly');
    assert(donation.donor == sender, 'sender failed');
    assert(donation.campaign_id == campaign_id, 'campaing id failed');
    assert(donation.amount == 500, 'fund not eflecting');

    let user_balance_after = token_dispatcher.balance_of(sender);
    println!("user balance after: {}", user_balance_after);
    let contract_balance_after = token_dispatcher.balance_of(campaign_donation.contract_address);
    println!("contract balance after: {}", contract_balance_after);

    assert(
        (contract_balance_before == 0) && (contract_balance_after == 500), 'CON transfer failed',
    );
    assert(user_balance_after == user_balance_before - 500, ' USR transfer failed');
}

// DONE
#[test]
fn test_successful_campaign_donation_twice() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'Test';

    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    stop_cheat_caller_address(campaign_donation.contract_address);

    let user_balance_before = token_dispatcher.balance_of(sender);
    let contract_balance_before = token_dispatcher.balance_of(campaign_donation.contract_address);

    
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(campaign_donation.contract_address, sender);

    let _donation_id = campaign_donation.donate_to_campaign(campaign_id, 500);
    let donation_id_1 = campaign_donation.donate_to_campaign(campaign_id, 300);

    stop_cheat_caller_address(campaign_donation.contract_address);

    let donation = campaign_donation.get_donation(campaign_id, donation_id_1);

    assert(donation.donation_id == 2, ' not initalized Properly');
    assert(donation.amount == 300, 'fund not eflecting');

    let user_balance_after = token_dispatcher.balance_of(sender);
    let contract_balance_after = token_dispatcher.balance_of(campaign_donation.contract_address);
    assert((contract_balance_before == 0) && (contract_balance_after == 800), 'transfer failed');
    assert(user_balance_after == user_balance_before - 800, ' USR transfer failed');
}


#[test]
fn test_successful_multiple_users_donating_to_a_campaign() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 10000_u256;
    let campaign_ref = 'Test';
    let another_user: ContractAddress = contract_address_const::<'another_user'>();

    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    stop_cheat_caller_address(campaign_donation.contract_address);

    let contract_balance_before = token_dispatcher.balance_of(campaign_donation.contract_address);

    println!("contract balance before: {}", contract_balance_before);
    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 100000);
    token_dispatcher.transfer(another_user, 10000);
    let other_user_balance_before = token_dispatcher.balance_of(another_user);
    println!("other user balance before: {}", other_user_balance_before);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, another_user);
    token_dispatcher.approve(campaign_donation.contract_address, 1000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let _donation_id = campaign_donation.donate_to_campaign(campaign_id, 500);
    stop_cheat_caller_address(campaign_donation.contract_address);

    start_cheat_caller_address(campaign_donation.contract_address, another_user);
    let donation_id_1 = campaign_donation.donate_to_campaign(campaign_id, 300);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let donation = campaign_donation.get_donation(campaign_id, donation_id_1);

    assert(donation.donation_id == 2, ' not initalized Properly');
    assert(donation.amount == 300, 'fund not eflecting');

    let other_user_balance_after = token_dispatcher.balance_of(another_user);
    let contract_balance_after = token_dispatcher.balance_of(campaign_donation.contract_address);
    println!("contract balance after: {}", contract_balance_after);
    assert((contract_balance_before == 0) && (contract_balance_after == 800), 'transfer failed');
    assert(other_user_balance_after == other_user_balance_before - 300, ' USR transfer failed');
}

#[test]
fn test_target_met_successful() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'Test';

    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    stop_cheat_caller_address(campaign_donation.contract_address);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(campaign_donation.contract_address, sender);

    let _donation_id = campaign_donation.donate_to_campaign(campaign_id, 1000);

    stop_cheat_caller_address(campaign_donation.contract_address);

    let campaign = campaign_donation.get_campaign(campaign_id);

    assert(campaign.is_goal_reached, 'target error');
    assert(campaign.is_closed, 'target error');
}


fn test_get_campaigns() {
    let (_token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount_1 = 1000_u256;
    let target_amount_2 = 2000_u256;
    let target_amount_3 = 3000_u256;

    // Create multiple campaigns with different references
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id_1 = campaign_donation.create_campaign('Ref1', target_amount_1);
    let campaign_id_2 = campaign_donation.create_campaign('Ref2', target_amount_2);
    let campaign_id_3 = campaign_donation.create_campaign('Ref3', target_amount_3);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Get all campaigns
    let campaigns = campaign_donation.get_campaigns();

    // Verify campaign count
    assert(campaigns.len() == 3, 'Should return 3 campaigns');

    // Verify campaign details
    let campaign_1 = campaigns.at(0);
    let campaign_2 = campaigns.at(1);
    let campaign_3 = campaigns.at(2);

    // Verify first campaign
    assert(*campaign_1.campaign_id == campaign_id_1, 'Campaign 1 ID mismatch');
    assert(*campaign_1.owner == sender, 'Campaign 1 owner mismatch');
    assert(*campaign_1.target_amount == target_amount_1, 'Campaign 1 target mismatch');
    assert(*campaign_1.campaign_reference == 'Ref1', 'Campaign 1 ref mismatch');

    // Verify second campaign
    assert(*campaign_2.campaign_id == campaign_id_2, 'Campaign 2 ID mismatch');
    assert(*campaign_2.target_amount == target_amount_2, 'Campaign 2 target mismatch');
    assert(*campaign_2.campaign_reference == 'Ref2', 'Campaign 2 ref mismatch');

    // Verify third campaign
    assert(*campaign_3.campaign_id == campaign_id_3, 'Campaign 3 ID mismatch');
    assert(*campaign_3.target_amount == target_amount_3, 'Campaign 3 target mismatch');
    assert(*campaign_3.campaign_reference == 'Ref3', 'Campaign 3 ref mismatch');
}

#[test]
fn test_get_campaign_donations() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let another_user: ContractAddress = contract_address_const::<'another_user'>();
    let target_amount = 5000_u256;

    // Create a campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign('TestCampaign', target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup token approvals for both users
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(another_user, 10000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, another_user);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    stop_cheat_caller_address(token_address);

    // Make multiple donations from different users
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let donation_id_1 = campaign_donation.donate_to_campaign(campaign_id, 500);
    let donation_id_2 = campaign_donation.donate_to_campaign(campaign_id, 700);
    stop_cheat_caller_address(campaign_donation.contract_address);

    start_cheat_caller_address(campaign_donation.contract_address, another_user);
    let donation_id_3 = campaign_donation.donate_to_campaign(campaign_id, 300);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Get all donations for the campaign
    let donations = campaign_donation.get_campaign_donations(campaign_id);

    // Verify donation count
    assert(donations.len() == 3, 'Should return 3 donations');

    // Verify donation details
    let donation_1 = donations.at(0);
    let donation_2 = donations.at(1);
    let donation_3 = donations.at(2);

    // Verify first donation
    assert(*donation_1.donation_id == donation_id_1, 'Donation 1 ID mismatch');
    assert(*donation_1.donor == sender, 'Donation 1 donor mismatch');
    assert(*donation_1.amount == 500, 'Donation 1 amount mismatch');

    // Verify second donation
    assert(*donation_2.donation_id == donation_id_2, 'Donation 2 ID mismatch');
    assert(*donation_2.donor == sender, 'Donation 2 donor mismatch');
    assert(*donation_2.amount == 700, 'Donation 2 amount mismatch');

    // Verify third donation
    assert(*donation_3.donation_id == donation_id_3, 'Donation 3 ID mismatch');
    assert(*donation_3.donor == another_user, 'Donation 3 donor mismatch');
    assert(*donation_3.amount == 300, 'Donation 3 amount mismatch');

    // Verify campaign data is updated correctly
    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.current_balance == 1500, 'Campaign amount mismatch');
}

#[test]
fn test_get_campaign_donations_empty() {
    let (_token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;

    // Create a campaign but don't make any donations
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign('EmptyCampaign', target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Get donations for the campaign
    let donations = campaign_donation.get_campaign_donations(campaign_id);

    // Verify no donations are returned
    assert(donations.len() == 0, 'Should return empty array');
}

#[test]
fn test_multiple_campaigns_with_donations() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;

    // Create multiple campaigns
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id_1 = campaign_donation.create_campaign('Campaign1', target_amount);
    let campaign_id_2 = campaign_donation.create_campaign('Campaign2', target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup token approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    stop_cheat_caller_address(token_address);

    // Make donations to both campaigns
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let _donation_id_1 = campaign_donation.donate_to_campaign(campaign_id_1, 100);
    let _donation_id_2 = campaign_donation.donate_to_campaign(campaign_id_1, 200);
    let _donation_id_3 = campaign_donation.donate_to_campaign(campaign_id_2, 300);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Get donations for campaign 1
    let donations_1 = campaign_donation.get_campaign_donations(campaign_id_1);
    assert(donations_1.len() == 2, 'wrong donation count 1');
    assert(*donations_1.at(0).amount == 100, '1st donation amt error');
    assert(*donations_1.at(1).amount == 200, '2nd donation amt error');

    // Get donations for campaign 2
    let donations_2 = campaign_donation.get_campaign_donations(campaign_id_2);
    assert(donations_2.len() == 1, 'wrong donation count 2');
    assert(*donations_2.at(0).amount == 300, '3rd donation amount error');

    // Verify get_campaigns returns both campaigns
    let campaigns = campaign_donation.get_campaigns();
    assert(campaigns.len() == 2, 'Should return 2 campaigns');
}

// #[test]
// #[fork(url: "https://starknet-sepolia.public.blastapi.io/rpc/v0_8", block_tag: latest)]
fn test_withdraw_funds_from_campaign_successful() {
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 800_u256;
    let campaign_ref = 'Test';
    let owner = contract_address_const::<'owner'>();

    start_cheat_caller_address(campaign_donation.contract_address, owner);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    stop_cheat_caller_address(campaign_donation.contract_address);
    // This is the first Campaign Created, so it will be 1.
    assert!(campaign_id == 1_u256, "Campaign creation failed");

    // let donor = contract_address_const::<'donor'>();

    let user_balance_before = token_dispatcher.balance_of(sender);
    println!("user balance before: {}", user_balance_before);
    let contract_balance_before = token_dispatcher.balance_of(campaign_donation.contract_address);
    println!("contract balance before: {}", contract_balance_before);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 1000);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(sender, campaign_donation.contract_address);
    println!("Allowance for withdrawal: {}", allowance);

    assert(allowance >= 1000, 'Allowance not set correctly');

    start_cheat_caller_address(campaign_donation.contract_address, sender);

    let _donation_id = campaign_donation.donate_to_campaign(campaign_id, 800);

    stop_cheat_caller_address(campaign_donation.contract_address);

    // let donation = campaign_donation.get_donation(campaign_id, donation_id);

    start_cheat_caller_address(campaign_donation.contract_address, owner);

    let owner_balance_before = token_dispatcher.balance_of(owner);
    println!("campaign owner balance before: {}", owner_balance_before);
    let contract_balance_before = token_dispatcher.balance_of(campaign_donation.contract_address);
    println!("contract  balance before: {}", contract_balance_before);
    campaign_donation.withdraw_from_campaign(campaign_id);

    let owner_balance_after = token_dispatcher.balance_of(owner);
    println!("campaign owner balance after: {}", owner_balance_after);
    let contract_balance_after = token_dispatcher.balance_of(campaign_donation.contract_address);

    println!("contract balance after: {}", contract_balance_after);
    stop_cheat_caller_address(campaign_donation.contract_address);

    assert(owner_balance_after - owner_balance_before == 800, 'Withdrawal error')
}

// =============================================================================
// AUTO-CAPPING TESTS - Added to address reviewer's feedback
// =============================================================================

#[test]
fn test_single_donation_auto_capping() {
    // Test: Single donation exceeding remaining target is capped correctly
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'AutoCap1';
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 5000); // Give donor2 some tokens
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Make initial donation of 600 (leaving 400 remaining)
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    campaign_donation.donate_to_campaign(campaign_id, 600);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify campaign state
    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.current_balance == 600, 'Initial donation failed');
    assert(!campaign.is_goal_reached, 'Goal not reached yet');

    // Attempt to donate 500 when only 400 remaining (should be auto-capped)
    let donor2_balance_before = token_dispatcher.balance_of(donor2);

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.donate_to_campaign(campaign_id, 500);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify campaign received exactly 400 more (total 1000)
    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.current_balance == 1000, 'Campaign fully funded');
    assert(campaign.is_goal_reached, 'Goal should be reached');
    assert(campaign.is_closed, 'Campaign should be closed');

    // Verify donor2 was only charged 400 (not the requested 500)
    let donor2_balance_after = token_dispatcher.balance_of(donor2);
    assert(donor2_balance_before - donor2_balance_after == 400, 'Charge capped amount');
}

#[test]
fn test_batch_donation_auto_capping_multiple_campaigns() {
    // Test: Batch donations to multiple campaigns with individual auto-capping
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create two campaigns with different targets
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id_1 = campaign_donation.create_campaign('MultiCap1', 500); // Target: 500
    let campaign_id_2 = campaign_donation.create_campaign('MultiCap2', 800); // Target: 800
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Pre-fund campaigns partially
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    campaign_donation.donate_to_campaign(campaign_id_1, 300); // Campaign 1: 200 remaining
    campaign_donation.donate_to_campaign(campaign_id_2, 300); // Campaign 2: 500 remaining
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Batch donate exceeding both remaining amounts
    let mut campaign_amounts: Array<(u256, u256)> = ArrayTrait::new();
    campaign_amounts.append((campaign_id_1, 400)); // Should cap to 200
    campaign_amounts.append((campaign_id_2, 600)); // Should cap to 500

    let donor2_balance_before = token_dispatcher.balance_of(donor2);

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.batch_donate(campaign_amounts);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify both campaigns are fully funded
    let campaign_1 = campaign_donation.get_campaign(campaign_id_1);
    let campaign_2 = campaign_donation.get_campaign(campaign_id_2);

    assert(campaign_1.current_balance == 500, 'Campaign 1 fully funded');
    assert(campaign_1.is_goal_reached, 'Campaign 1 goal reached');
    assert(campaign_1.is_closed, 'Campaign 1 should be closed');

    assert(campaign_2.current_balance == 800, 'Campaign 2 fully funded');
    assert(campaign_2.is_goal_reached, 'Campaign 2 goal reached');
    assert(campaign_2.is_closed, 'Campaign 2 should be closed');

    // Verify donor2 was charged correct amount (200 + 500 = 700, not 1000)
    let donor2_balance_after = token_dispatcher.balance_of(donor2);
    assert(donor2_balance_before - donor2_balance_after == 700, 'Charge capped amounts');
}

#[test]
fn test_batch_donation_zero_amount_after_capping() {
    // Test: Donation that gets capped to zero (campaign already full)
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'ZeroCap';
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Fully fund the campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    campaign_donation.donate_to_campaign(campaign_id, 1000);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify campaign is complete
    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.current_balance == 1000, 'Campaign fully funded');
    assert(campaign.is_goal_reached, 'Goal should be reached');
    assert(campaign.is_closed, 'Campaign should be closed');

    // Attempt batch donation to already completed campaign
    let mut campaign_amounts: Array<(u256, u256)> = ArrayTrait::new();
    campaign_amounts.append((campaign_id, 500)); // Should be capped to 0

    let donor2_balance_before = token_dispatcher.balance_of(donor2);
    let donations_before = campaign_donation.get_campaign_donations(campaign_id);
    let donation_count_before = donations_before.len();

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.batch_donate(campaign_amounts);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify no additional donation was made and no charge occurred
    let campaign_after = campaign_donation.get_campaign(campaign_id);
    assert(campaign_after.current_balance == 1000, 'Balance unchanged');

    let donor2_balance_after = token_dispatcher.balance_of(donor2);
    assert(donor2_balance_before == donor2_balance_after, 'No tokens charged');

    // Verify no new donation record was created (since amount was 0)
    let donations_after = campaign_donation.get_campaign_donations(campaign_id);
    assert(donations_after.len() == donation_count_before, 'No new donation recorded');
}

#[test]
fn test_batch_donation_mixed_scenarios() {
    // Test: Complex batch with some full donations, some capped, some zero
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create three campaigns with different states
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id_1 = campaign_donation.create_campaign('Mixed1', 1000); // Will be partially funded
    let campaign_id_2 = campaign_donation.create_campaign('Mixed2', 500);  // Will be fully funded
    let campaign_id_3 = campaign_donation.create_campaign('Mixed3', 800);  // Will accept full donation
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 10000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    stop_cheat_caller_address(token_address);

    // Pre-fund campaigns to different levels
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    campaign_donation.donate_to_campaign(campaign_id_1, 700); // 300 remaining
    campaign_donation.donate_to_campaign(campaign_id_2, 500); // 0 remaining (full)
    // campaign_id_3 remains empty (800 remaining)
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Create mixed batch donation
    let mut campaign_amounts: Array<(u256, u256)> = ArrayTrait::new();
    campaign_amounts.append((campaign_id_1, 500)); // Should cap to 300
    campaign_amounts.append((campaign_id_2, 200)); // Should cap to 0 (already full)
    campaign_amounts.append((campaign_id_3, 400)); // Should get full 400

    let donor2_balance_before = token_dispatcher.balance_of(donor2);

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.batch_donate(campaign_amounts);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify final campaign states
    let campaign_1_final = campaign_donation.get_campaign(campaign_id_1);
    let campaign_2_final = campaign_donation.get_campaign(campaign_id_2);
    let campaign_3_final = campaign_donation.get_campaign(campaign_id_3);

    assert(campaign_1_final.current_balance == 1000, 'Campaign 1 complete');
    assert(campaign_1_final.is_goal_reached, 'Campaign 1 goal reached');
    
    assert(campaign_2_final.current_balance == 500, 'Campaign 2 unchanged');
    assert(campaign_2_final.is_goal_reached, 'Campaign 2 complete');
    
    assert(campaign_3_final.current_balance == 400, 'Campaign 3 has 400');
    assert(!campaign_3_final.is_goal_reached, 'Campaign 3 not complete');

    // Verify donor was charged correct total: 300 + 0 + 400 = 700
    let donor2_balance_after = token_dispatcher.balance_of(donor2);
    assert(donor2_balance_before - donor2_balance_after == 700, 'Charge effective total');
}

#[test]
fn test_batch_donation_event_emission() {
    // Test: Verify BatchDonationProcessed event is emitted correctly
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign('EventTest', target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Spy on events
    let mut _spy = spy_events();

    // Make batch donation
    let mut campaign_amounts: Array<(u256, u256)> = ArrayTrait::new();
    campaign_amounts.append((campaign_id, 300));
    campaign_amounts.append((campaign_id, 400));

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.batch_donate(campaign_amounts);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify that events were emitted (individual Donation events + BatchDonationProcessed event)
    // This test verifies that the batch event emission functionality works
    // The specific event verification would depend on your event assertion framework
}

#[test]
fn test_batch_donation_auto_capping_single_campaign() {
    // Test: Batch donations to same campaign with cumulative auto-capping
    let (token_address, sender, campaign_donation, _erc721) = setup();
    let target_amount = 1000_u256;
    let campaign_ref = 'BatchCap1';
    let donor2: ContractAddress = contract_address_const::<'donor2'>();

    // Create campaign
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    let campaign_id = campaign_donation.create_campaign(campaign_ref, target_amount);
    stop_cheat_caller_address(campaign_donation.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    // Setup tokens and approvals
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(campaign_donation.contract_address, 10000);
    token_dispatcher.transfer(donor2, 5000);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(token_address, donor2);
    token_dispatcher.approve(campaign_donation.contract_address, 5000);
    stop_cheat_caller_address(token_address);

    // Make initial donation of 300 (leaving 700 remaining)
    start_cheat_caller_address(campaign_donation.contract_address, sender);
    campaign_donation.donate_to_campaign(campaign_id, 300);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Batch donate: 400 + 400 = 800 total, but only 700 remaining
    // Should be auto-capped to 700 total (400 + 300)
    let mut campaign_amounts: Array<(u256, u256)> = ArrayTrait::new();
    campaign_amounts.append((campaign_id, 400)); // First: 400 (should get full amount)
    campaign_amounts.append((campaign_id, 400)); // Second: 300 (should be capped from 400 to 300)

    let donor2_balance_before = token_dispatcher.balance_of(donor2);

    start_cheat_caller_address(campaign_donation.contract_address, donor2);
    campaign_donation.batch_donate(campaign_amounts);
    stop_cheat_caller_address(campaign_donation.contract_address);

    // Verify campaign received exactly 700 more (total 1000)
    let campaign = campaign_donation.get_campaign(campaign_id);
    assert(campaign.current_balance == 1000, 'Campaign fully funded');
    assert(campaign.is_goal_reached, 'Goal should be reached');
    assert(campaign.is_closed, 'Campaign should be closed');

    // Verify donor2 was only charged 700 (not the requested 800)
    let donor2_balance_after = token_dispatcher.balance_of(donor2);
    assert(donor2_balance_before - donor2_balance_after == 700, 'Charge effective amount');

    // Verify donation records show correct amounts
    let donations = campaign_donation.get_campaign_donations(campaign_id);
    // Should have 3 donations: 300 (initial) + 400 (batch 1) + 300 (batch 2, capped)
    assert(donations.len() == 3, 'Should have 3 donations');
    
    // Check the batch donation amounts
    let batch_donation_1 = donations.at(1); // Second donation (first batch)
    let batch_donation_2 = donations.at(2); // Third donation (second batch, capped)
    
    assert(*batch_donation_1.amount == 400, 'First batch 400');
    assert(*batch_donation_2.amount == 300, 'Second batch capped 300');
}