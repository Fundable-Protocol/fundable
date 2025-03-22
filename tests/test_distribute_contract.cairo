use core::num::traits::Bounded;
use core::traits::Into;
use fundable::base::types::{
    Distribution, DistributionHistory, TokenStats, UserStats, WeightedDistribution,
};
use fundable::interfaces::IDistributor::{IDistributorDispatcher, IDistributorDispatcherTrait};
//use fundable::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, generate_random_felt,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_block_timestamp,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};

const U16_MAX: u16 = Bounded::<u16>::MAX;

fn setup() -> (ContractAddress, ContractAddress, IDistributorDispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into(), 6];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy distributor contract
    let distributor_class = declare("Distributor").unwrap().contract_class();
    let protocol_address = contract_address_const::<'protocol_address'>();
    let (distributor_address, _) = distributor_class
        .deploy(@array![protocol_address.into(), sender.into()])
        .unwrap();

    (erc20_address, sender, IDistributorDispatcher { contract_address: distributor_address })
}

fn top_tokens_mainnet() -> Array<(ContractAddress, ContractAddress, u256)> {
    array![
        (
            contract_address_const::<
                0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7,
            >(),
            contract_address_const::<
                0x0213c67ed78bc280887234fe5ed5e77272465317978ae86c25a71531d9332a2d,
            >(),
            54232_u256,
        ), // 160 * 331, ETH highest_holder -> 0x0213c67ed78bc280887234fe5ed5e77272465317978ae86c25a71531d9332a2d
        (
            contract_address_const::<
                0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8,
            >(),
            contract_address_const::<
                0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b,
            >(),
            19836339_u256,
        ), // 59928 * 331, USDC highest_holder -> 0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b
        (
            contract_address_const::<
                0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
            >(),
            contract_address_const::<
                0x00ca1702e64c81d9a07b86bd2c540188d92a2c73cf5cc0e508d949015e7e84a7,
            >(),
            184313527_u256,
        ), // 556838 * 331, STRK highest_holder -> 0x00ca1702e64c81d9a07b86bd2c540188d92a2c73cf5cc0e508d949015e7e84a7
        (
            contract_address_const::<
                0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8,
            >(),
            contract_address_const::<
                0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b,
            >(),
            9312882_u256,
        ) // 28135 * 331, USDT highest_holder -> 0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b
    ]
}

fn base_address() -> felt252 {
    0x02bbab4d3c77dd83dfe47af99c9a3188a660e9c652a2f7af3d21df213f4882cd
}

// Recipients exceeding 331 results in a failure.
// Failure data:
//     Got an exception while executing a hint: Hint Error: Error at pc=0:8539:
//     Got an exception while executing a hint: Exceeded the maximum number of events, number
//     events: 1001, max number events: 1000.
//     Cairo traceback (most recent call last):
//     Unknown location (pc=0:8553)
fn recipients_array(
    recipients_count: u16, token: IERC20Dispatcher,
) -> (Array<ContractAddress>, Array<u256>) {
    let base_address: felt252 = base_address();

    let recipients_count = if recipients_count == 0 || recipients_count > 331 {
        331
    } else {
        recipients_count
    };

    let mut recipients: Array<ContractAddress> = ArrayTrait::new();
    let mut recipients_initial_balances: Array<u256> = ArrayTrait::new();

    for i in 0..recipients_count {
        let current_address: ContractAddress = (base_address + i.into()).try_into().unwrap();
        recipients.append(current_address);
        recipients_initial_balances.append(token.balance_of(current_address));
    }

    (recipients, recipients_initial_balances)
}

// Assert Eq macro is used here to pass error messages with context(recipient address)
fn assert_balances(
    recipients: Span<ContractAddress>,
    recipients_initial_balances: Span<u256>,
    token: IERC20Dispatcher,
    amount_per_recipient: u256,
) {
    for i in 0..recipients.len() {
        assert_eq!(
            token.balance_of(*recipients.at(i.into())),
            amount_per_recipient + *recipients_initial_balances.at(i.into()),
            "Wrong balance for recipient: {:?}",
            *recipients.at(i.into()),
        );
    };
}

fn assert_weighted_balances(
    recipients: Span<ContractAddress>,
    recipients_initial_balances: Span<u256>,
    token: IERC20Dispatcher,
    amount_per_recipient: Span<u256>,
) {
    for i in 0..recipients.len() {
        assert_eq!(
            token.balance_of(*recipients.at(i.into())),
            *amount_per_recipient.at(i.into()) + *recipients_initial_balances.at(i.into()),
            "Wrong balance for recipient: {:?}",
            *recipients.at(i.into()),
        );
    };
}

// Fuzzer could fuzz 0 value which would error.
// If amount is zero, set to max to avoid transfer errors.
fn gen_amount_per_recipient(amount_per_recipient: u256) -> u256 {
    if amount_per_recipient == 0 {
        (U16_MAX).into()
    } else {
        amount_per_recipient
    }
}

// U16 is used to avoid 'Add Overflow' errors.
fn gen_weighted_amounts(weight: u32) -> Array<u256> {
    let mut weighted_amounts = ArrayTrait::new();
    for _ in 0..weight {
        // 65,535 * 331 < U256_MAX
        let max_16: u256 = U16_MAX.into();
        let amount: u256 = generate_random_felt().into();
        let amount = if amount == 0 || amount > max_16 {
            max_16
        } else {
            amount
        };
        weighted_amounts.append(amount);
    }
    weighted_amounts
}

// This would not be needed when this issue is resolved
// `https://github.com/foundry-rs/starknet-foundry/issues/1979`
// `mint cheatcode for testing purposes`
fn gen_based_weighted_amounts(weight: u32, max_check: u256) -> Array<u256> {
    let mut weighted_amounts = ArrayTrait::new();
    for _ in 0..weight {
        // allowance * 331 <= max_check
        let maxi: u256 = max_check / weight.into();
        let amount: u256 = generate_random_felt().into();
        let amount = if amount == 0 || amount > maxi {
            maxi
        } else {
            amount
        };
        weighted_amounts.append(amount);
    }
    weighted_amounts
}

// Test Cases (Distribute, DistributeWeighted)
// Fuzz recipients array
#[test]
#[fuzzer]
fn test_fuzz_recipients(recipients_count: u16) {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Calculate and approve the amount each recipient will receive, ensuring the sender has
    // sufficient balance for all 'transfer_from' calls.
    let balance = token.balance_of(sender);
    let amount_per_recipient = balance / recipients.len().into();

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, balance);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz amount per recipient
#[test]
#[fuzzer]
fn test_fuzz_amount_per_recipient(amount_per_recipient: u16) {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(331, token);

    // Avoid zero transfer errors.
    let amount_per_recipient: u256 = gen_amount_per_recipient(amount_per_recipient.into());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, token.balance_of(sender));
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz Both amount and recipients
#[test]
#[fuzzer]
fn test_fuzz_both_amount_and_recipients(recipients_count: u16, amount_per_recipient: u16) {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Avoid zero transfer errors.
    let amount_per_recipient: u256 = gen_amount_per_recipient(amount_per_recipient.into());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, token.balance_of(sender));
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz Weighted amount and recipients
#[test]
#[fuzzer]
#[ignore]
fn test_fuzz_weighted_amount_and_recipients(recipients_count: u16) {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Weighted amounts are generated based on the recipients' weights.
    let mut weighted_amounts: Array<u256> = gen_weighted_amounts(recipients.len());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, token.balance_of(sender));
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(weighted_amounts.clone(), recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_weighted_balances(
        recipients.span(), recipients_initial_balances.span(), token, weighted_amounts.span(),
    );
}

// Fuzz and Fork Mainnet recipients array
#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_and_fork_STRK_mainnet_recipients(recipients_count: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(2);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let amount_per_recipient: u256 = U16_MAX.into();

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz and Fork Mainnet amount per recipient
#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_and_fork_STRK_mainnet_amount_per_recipient(amount_per_recipient: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(2);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(331, token);

    let amount_per_recipient: u256 = gen_amount_per_recipient(amount_per_recipient.into());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz and Fork Mainnet amount per recipient and recipients array
#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_STRK_distribution(recipients_count: u16, amount_per_recipient: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(2);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let amount_per_recipient: u256 = gen_amount_per_recipient(amount_per_recipient.into());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

// Fuzz and Fork Mainnet weighted amount per recipient and recipients array
#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_STRK_weighted_distribution(recipients_count: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(2);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let mut weighted_amounts: Array<u256> = gen_weighted_amounts(recipients.len());

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(weighted_amounts.clone(), recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_weighted_balances(
        recipients.span(), recipients_initial_balances.span(), token, weighted_amounts.span(),
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_ETH_distribution(recipients_count: u16, amount_per_recipient: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let token_data = *mainnet_token.at(0);
    let (token_address, sender, allow) = token_data;

    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Avoid zero transfer errors.
    let amount_per_recipient: u256 = 160;

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_ETH_weighted_distribution(recipients_count: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(0);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let mut weighted_amounts: Array<u256> = gen_based_weighted_amounts(recipients.len(), allow);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(weighted_amounts.clone(), recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_weighted_balances(
        recipients.span(), recipients_initial_balances.span(), token, weighted_amounts.span(),
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_USDC_distribution(recipients_count: u16, amount_per_recipient: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let token_data = *mainnet_token.at(1);
    let (token_address, sender, allow) = token_data;

    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Avoid zero transfer errors.
    let amount_per_recipient: u256 = 59928;

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_USDC_weighted_distribution(recipients_count: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(1);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let mut weighted_amounts: Array<u256> = gen_based_weighted_amounts(recipients.len(), allow);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(weighted_amounts.clone(), recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_weighted_balances(
        recipients.span(), recipients_initial_balances.span(), token, weighted_amounts.span(),
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_USDT_distribution(recipients_count: u16, amount_per_recipient: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let token_data = *mainnet_token.at(3);
    let (token_address, sender, allow) = token_data;

    let token = IERC20Dispatcher { contract_address: token_address };

    // Fuzz recipients array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    // Avoid zero transfer errors.
    let amount_per_recipient: u256 = 28135;

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_balances(
        recipients.span(), recipients_initial_balances.span(), token, amount_per_recipient,
    );
}

#[test]
#[fuzzer]
#[ignore]
#[fork("MAINNET")]
fn test_fuzz_fork_USDT_weighted_distribution(recipients_count: u16) {
    let (_, _, distributor) = setup();

    let mainnet_token = top_tokens_mainnet();
    let (token_address, sender, allow) = *mainnet_token.at(3);
    let token = IERC20Dispatcher { contract_address: token_address };

    // Recipients, Recipients initial balances array
    let (recipients, recipients_initial_balances) = recipients_array(recipients_count, token);

    let mut weighted_amounts: Array<u256> = gen_based_weighted_amounts(recipients.len(), allow);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, allow);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(weighted_amounts.clone(), recipients.clone(), token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert_weighted_balances(
        recipients.span(), recipients_initial_balances.span(), token, weighted_amounts.span(),
    );
}

#[test]
fn test_successful_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let sender_balance_before = token.balance_of(sender);
    println!("Sender balance is {}", sender_balance_before);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);
    println!(
        "Approved tokens for distributor: {}",
        token.allowance(sender, distributor.contract_address),
    );
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert(
        token.balance_of(contract_address_const::<0x2>()) == amount_per_recipient,
        'Wrong balance recipient 1',
    );
    assert(
        token.balance_of(contract_address_const::<0x3>()) == amount_per_recipient,
        'Wrong balance recipient 2',
    );
    assert(
        token.balance_of(contract_address_const::<0x4>()) == amount_per_recipient,
        'Wrong balance recipient 3',
    );
}

#[test]
fn test_protocol_fee_calculation() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };
    let protocol_address = contract_address_const::<'protocol_address'>();

    // Set protocol fee to 250 basis points (2.5%)
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.set_protocol_fee_address(protocol_address);
    distributor.set_protocol_fee_percent(250);
    stop_cheat_caller_address(distributor.contract_address);

    // Create recipients array
    let recipients = array![contract_address_const::<0x2>(), contract_address_const::<0x3>()];

    let amount_per_recipient = 1000_u256;
    let total_base_amount = amount_per_recipient * 2; // 2000 total tokens
    let protocol_fee = (total_base_amount * 250) / 10000; // 2.5% of 2000 = 50
    let total_amount = total_base_amount + protocol_fee; // 2050 total tokens needed

    // Approve tokens for distributor (including fee)
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Check protocol fee address received correct amount (2.5% of 2000 = 50)
    assert(token.balance_of(protocol_address) == protocol_fee, 'Wrong protocol fee amount');

    // Check recipients received full amount (no fee deduction from their share)
    assert(
        token.balance_of(contract_address_const::<0x2>()) == amount_per_recipient,
        'Wrong recipient 1 amount',
    );
    assert(
        token.balance_of(contract_address_const::<0x3>()) == amount_per_recipient,
        'Wrong recipient 2 amount',
    );
}

#[test]
fn test_protocol_fee_edge_cases() {
    let (_token_address, sender, distributor) = setup();

    // Test with 0% fee
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.set_protocol_fee_percent(0);
    assert(distributor.get_protocol_fee_percent() == 0, 'Fee should be 0');

    // Test with max fee (100%)
    distributor.set_protocol_fee_percent(10000);
    assert(distributor.get_protocol_fee_percent() == 10000, 'Fee should be 10000');
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
#[should_panic(expected: ('Error: Recipients array empty.',))]
fn test_empty_recipients() {
    let (token_address, sender, distributor) = setup();
    let recipients = array![];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(100_u256, recipients, token_address);
    stop_cheat_caller_address(sender);
}

#[test]
#[should_panic(expected: ('Error: Amount must be > 0.',))]
fn test_zero_amount() {
    let (token_address, sender, distributor) = setup();
    let recipients = array![contract_address_const::<0x2>()];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(0_u256, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
fn test_weighted_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    // Create amounts array with different values for each recipient
    let amounts = array![
        100_u256, // First recipient gets 100 tokens
        200_u256, // Second recipient gets 200 tokens
        300_u256 // Third recipient gets 300 tokens
    ];

    let total_amount = 600_u256; // Sum of all amounts

    let sender_balance_before = token.balance_of(sender);
    println!("Sender balance before: {}", sender_balance_before);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, total_amount);
    println!(
        "Approved tokens for distributor: {}",
        token.allowance(sender, distributor.contract_address),
    );
    stop_cheat_caller_address(token_address);

    // Distribute tokens with weighted amounts
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances for each recipient
    assert(
        token.balance_of(contract_address_const::<0x2>()) == 100_u256, 'Wrong balance recipient 1',
    );
    assert(
        token.balance_of(contract_address_const::<0x3>()) == 200_u256, 'Wrong balance recipient 2',
    );
    assert(
        token.balance_of(contract_address_const::<0x4>()) == 300_u256, 'Wrong balance recipient 3',
    );
}

#[test]
fn test_weighted_distribution_with_protocol_fee() {
    // Setup
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };
    let protocol_address = contract_address_const::<'protocol_address'>();

    let recipient1 = contract_address_const::<4>();
    let recipient2 = contract_address_const::<5>();

    // Set protocol fee to 2.5%
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.set_protocol_fee_percent(250);
    distributor.set_protocol_fee_address(protocol_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Prepare distribution data
    let mut amounts: Array<u256> = ArrayTrait::new();
    amounts.append(1000); // 1000 tokens for recipient1
    amounts.append(2000); // 2000 tokens for recipient2
    let total_distribution = 3000_u256; // 1000 + 2000
    let protocol_fee = (total_distribution * 250) / 10000; // 2.5% of 3000 = 75

    let mut recipients: Array<ContractAddress> = ArrayTrait::new();
    recipients.append(recipient1);
    recipients.append(recipient2);

    // Setup approvals and balances
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, total_distribution + protocol_fee);
    stop_cheat_caller_address(token_address);

    // Execute distribution
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token.contract_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert correct amounts were transferred
    assert(token.balance_of(recipient1) == 1000, 'Recipient1 balance incorrect');
    assert(token.balance_of(recipient2) == 2000, 'Recipient2 balance incorrect');
    assert(token.balance_of(protocol_address) == protocol_fee, 'Protocol fee transfer incorrect');
}

#[test]
#[should_panic(expected: 'Error: Arrays length mismatch.')]
fn test_weighted_distribution_mismatched_arrays() {
    let (token_address, sender, distributor) = setup();

    // Create unequal length arrays
    let recipients = array![contract_address_const::<0x2>(), contract_address_const::<0x3>()];
    let amounts = array![100_u256];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
#[should_panic(expected: ('Error: Amount must be > 0.',))]
fn test_weighted_distribution_zero_amount() {
    let (token_address, sender, distributor) = setup();

    let recipients = array![contract_address_const::<0x2>()];
    let amounts = array![0_u256];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
fn test_set_and_get_protocol_fee_percent() {
    let (_, sender, distributor) = setup();
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.set_protocol_fee_percent(5);
    assert(distributor.get_protocol_fee_percent() == 5, 'Wrong protocol fee');
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_protocol_fee_percent_unauthorized() {
    let (_, _, distributor) = setup();
    distributor.set_protocol_fee_percent(5);
}

#[test]
fn test_set_and_get_protocol_fee_address() {
    let (_, sender, distributor) = setup();
    let test_address = contract_address_const::<'test'>();
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.set_protocol_fee_address(test_address);
    assert(distributor.get_protocol_fee_address() == test_address, 'Wrong protocol address');
    stop_cheat_caller_address(distributor.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_set_protocol_fee_address_unauthorized() {
    let (_, _, distributor) = setup();
    let test_address = contract_address_const::<'test'>();
    distributor.set_protocol_fee_address(test_address);
}


#[test]
fn test_total_distribution_initial_state() {
    let (_, _, distributor) = setup();
    assert(distributor.get_total_distributions() == 0, 'wrong initial state');
}

#[test]
fn test_total_distribution_after_single_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert distributions
    assert(distributor.get_total_distributions() == 1, 'wrong total distribution');
}

#[test]
fn test_total_distribution_after_multiple_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![contract_address_const::<0x2>(), contract_address_const::<0x3>()];

    let amount_per_recipient = 50_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 2 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Create recipients array
    let mut new_recipients = array![
        contract_address_const::<0x2>(), contract_address_const::<0x3>(),
    ];

    let amount_per_recipient = 50_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 2 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, new_recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert distributions
    assert(distributor.get_total_distributions() == 2, 'wrong total distribution');
}

#[test]
fn test_total_distributed_amount_initial_state() {
    let (_, _, distributor) = setup();
    assert(distributor.get_total_distributed_amount() == 0, 'wrong initial state');
}

#[test]
fn test_total_distributed_amount_after_single_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert distributions
    assert(
        distributor.get_total_distributed_amount() == 300_u256, 'wrong total distributed amount',
    );
}

#[test]
fn test_total_distributed_amount_after_multiple_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![contract_address_const::<0x2>(), contract_address_const::<0x3>()];

    let amount_per_recipient = 50_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 2 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Create recipients array
    let mut new_recipients = array![
        contract_address_const::<0x2>(), contract_address_const::<0x3>(),
    ];

    let amount_per_recipient = 50_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 2 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, new_recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert distributions
    assert(
        distributor.get_total_distributed_amount() == 200_u256, 'wrong total distributed amount',
    );
}

#[test]
fn test_token_stats_initial_state() {
    let (token_address, _, distributor) = setup();

    //Assert token stats
    assert(distributor.get_token_stats(token_address).total_amount == 0, 'wrong initial state');
    assert(
        distributor.get_token_stats(token_address).distribution_count == 0, 'wrong initial state',
    );
    assert(
        distributor.get_token_stats(token_address).unique_recipients == 0, 'wrong initial state',
    );
    assert(
        distributor.get_token_stats(token_address).last_distribution_time == 0,
        'wrong initial state',
    );
}

#[test]
fn test_token_stats_after_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    start_cheat_block_timestamp(distributor.contract_address, 0x2137_u64);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    //Assert token stats
    assert(distributor.get_token_stats(token_address).total_amount == 300, 'wrong total amount');
    assert(
        distributor.get_token_stats(token_address).distribution_count == 1,
        'wrong distribution amount',
    );
    assert(
        distributor.get_token_stats(token_address).unique_recipients == 0,
        'wrong unique recipients',
    );
    assert(
        distributor.get_token_stats(token_address).last_distribution_time == 0x2137_u64,
        'wrong last distribution time',
    );

    stop_cheat_block_timestamp(distributor.contract_address);
}

#[test]
fn test_user_stats_initial_state() {
    let (_, sender, distributor) = setup();

    //Assert token stats
    assert(distributor.get_user_stats(sender).distributions_initiated == 0, 'wrong initial state');
    assert(distributor.get_user_stats(sender).total_amount_distributed == 0, 'wrong initial state');
    assert(distributor.get_user_stats(sender).last_distribution_time == 0, 'wrong initial state');
    assert(distributor.get_user_stats(sender).unique_tokens_used == 0, 'wrong initial state');
}

#[test]
fn test_user_stats_after_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    start_cheat_block_timestamp(distributor.contract_address, 0x2137_u64);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    //Assert token stats
    assert(
        distributor.get_user_stats(sender).distributions_initiated == 1,
        'wrong distributions
    amount',
    );
    assert(
        distributor.get_user_stats(sender).total_amount_distributed == 300,
        'wrong distributed
    amount',
    );
    assert(
        distributor.get_user_stats(sender).last_distribution_time == 0x2137_u64,
        'wrong last_distribution time',
    );
    assert(
        distributor.get_user_stats(sender).unique_tokens_used == 1, 'wrong unique token
    count',
    );

    stop_cheat_block_timestamp(distributor.contract_address);
}

#[test]
fn test_distribution_history_initial_state() {
    let (_, _, distributor) = setup();

    let mut history = distributor
        .get_distribution_history(0, distributor.get_total_distributions());
    assert(history.len() == 0, 'Wrong initial state');
}

#[test]
fn test_distribution_history_after_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>(),
    ];

    let amount_per_recipient = 100_u256;

    let _sender_balance_before = token.balance_of(sender);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);

    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    start_cheat_block_timestamp(distributor.contract_address, 0x2137_u64);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    let history = distributor.get_distribution_history(0, 1);

    //Assert token stats
    assert(*history[0].caller == sender, 'wrong caller');
    assert(*history[0].token == token_address, 'wrong token');
    assert(*history[0].amount == 300, 'wrong last_distribution time');
    assert(*history[0].recipients_count == 3, 'wrong recipient
    count');
    assert(*history[0].timestamp == 0x2137_u64, 'wrong timestamp');

    stop_cheat_block_timestamp(distributor.contract_address);
}
