use core::num::traits::Pow;
use core::traits::{Into, TryInto};
use fundable::base::types::{Stream, StreamStatus};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::token::erc20::interface::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_block_timestamp_global, start_cheat_caller_address,
    stop_cheat_block_timestamp, stop_cheat_block_timestamp_global, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};

// Constantes para roles
const PROTOCOL_OWNER_ROLE: felt252 = selector!("PROTOCOL_OWNER");
// Note: STREAM_ADMIN_ROLE removed - using stream-specific access control
const TOTAL_AMOUNT: u256 = 10000000000000000000000_u256;

fn setup_access_control() -> (
    ContractAddress,
    ContractAddress,
    IPaymentStreamDispatcher,
    IAccessControlDispatcher,
    IERC721Dispatcher,
) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into(), 6];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Payment stream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into(), 300_u64.into(), protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@calldata).unwrap();

    (
        erc20_address,
        sender,
        IPaymentStreamDispatcher { contract_address: payment_stream_address },
        IAccessControlDispatcher { contract_address: payment_stream_address },
        IERC721Dispatcher { contract_address: payment_stream_address },
    )
}

fn convert_to_decimal(value: u256, decimals: u8) -> u256 {
    value * (10_u256.pow(decimals.into()))
}

fn setup() -> (
    ContractAddress, ContractAddress, IPaymentStreamDispatcher, IERC721Dispatcher, IERC20Dispatcher,
) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into(), 6];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Payment stream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into(), 300_u64.into(), protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@calldata).unwrap();
    let payment_stream_contract = IPaymentStreamDispatcher {
        contract_address: payment_stream_address,
    };
    start_cheat_caller_address(payment_stream_address, protocol_owner);
    payment_stream_contract.set_protocol_fee_rate(erc20_address, 300);
    stop_cheat_caller_address(payment_stream_address);

    (
        erc20_address,
        sender,
        payment_stream_contract,
        IERC721Dispatcher { contract_address: payment_stream_address },
        IERC20Dispatcher { contract_address: erc20_address },
    )
}

fn setup_custom_decimals(
    decimals: u8,
) -> (ContractAddress, ContractAddress, IPaymentStreamDispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();

    // Deploy mock ERC20 with custom decimals
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![
        sender.into(), // recipient
        sender.into(), // owner
        decimals.into() // custom decimals
    ];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy PaymentStream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut ps_calldata = array![protocol_owner.into(), 300_u64.into(), protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@ps_calldata).unwrap();

    let payment_stream_contract = IPaymentStreamDispatcher {
        contract_address: payment_stream_address,
    };

    (erc20_address, sender, payment_stream_contract)
}

fn calculate_seconds_in_day(day: u64) -> u64 {
    day * 86400
}

#[test]
fn test_nft_metadata() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    let metadata = IERC721MetadataDispatcher { contract_address: payment_stream.contract_address };

    let name = metadata.name();
    let symbol = metadata.symbol();
    let token_uri = metadata.token_uri(stream_id);

    assert(name == "PaymentStream", 'wrong name');
    assert(symbol == "STREAM", 'wrong symbol');
    assert(token_uri == "https://paymentstream.io/0", 'wrong uri');
}

#[test]
fn test_successful_create_stream() {
    let (token_address, sender, payment_stream, erc721, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    assert(stream_id == 0_u256, 'Stream creation failed');
    let owner = erc721.owner_of(stream_id);
    assert(owner == recipient, 'NFT not minted to initial owner');
}

#[test]
#[should_panic(expected: 'Error: Duration is too short')]
fn test_invalid_end_time() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 0_u64; // Invalid duration
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_zero_recipient_address() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<0x0>(); // Invalid zero address
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);
}

// #[test]
// #[should_panic(expected: 'Error: Invalid token address.')]
// fn test_zero_token_address() {
//     let (_, sender, payment_stream, _, _) = setup();
//     let recipient = contract_address_const::<'recipient'>();
//     let total_amount = TOTAL_AMOUNT;
//     let duration = 100_u64;
//     let cancelable = true;
//     let transferable = true;

//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     payment_stream
//         .create_stream(
//             recipient,
//             total_amount,
//             duration,
//             cancelable,
//             contract_address_const::<0x0>(),
//             transferable,
//         );
//     stop_cheat_caller_address(payment_stream.contract_address);
// }

#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_zero_total_amount() {
    let (token_address, sender, payment_stream, _, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 0_u256;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_successful_create_stream_and_return_correct_rate_per_second() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let token_dispatcher = IERC20MetadataDispatcher { contract_address: token_address };
    let token_decimals = token_dispatcher.decimals();
    let total_amount = convert_to_decimal(1000_u256, token_decimals);
    let duration = 10_u64;
    let cancelable = false;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stream_rate_per_second = payment_stream.get_rate_per_second(stream_id);
    // Duration is in hours
    let rate_per_second = total_amount / (duration.into() * 3600);
    assert(stream_rate_per_second == rate_per_second, 'Stream rps is invalid');
}


#[test]
fn test_update_fee_collector() {
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let (token_address, sender, payment_stream, _, _) = setup();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    let fee_collector = payment_stream.get_fee_collector();
    assert(fee_collector == new_fee_collector, 'wrong fee collector');
}

#[test]
fn test_update_percentage_protocol_fee() {
    let (token_address, sender, payment_stream, _, _) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.set_protocol_fee_rate(token_address, 400);
    stop_cheat_caller_address(payment_stream.contract_address);

    let fee = payment_stream.get_protocol_fee_rate(token_address);
    assert(fee == 400, 'wrong fee');
}

#[test]
fn test_protocol_metrics_accuracy() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let amount_to_send = total_amount / 2;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Initial metrics check
    let initial_metrics = payment_stream.get_protocol_metrics();
    assert(initial_metrics.total_active_streams == 0, 'Should be 0');
    assert(initial_metrics.total_tokens_to_stream == 0, 'Initial tokens should be 0');
    assert(initial_metrics.total_streams_created == 0, 'created streams should be 0');
    assert(initial_metrics.total_delegations == 0, 'Initial delegations should be 0');

    // Create first stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, amount_to_send, duration, cancelable, token_address, transferable,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check metrics after first stream
    let metrics_after_first = payment_stream.get_protocol_metrics();
    assert(metrics_after_first.total_active_streams == 1, 'Active streams should be 1');
    assert(
        metrics_after_first.total_tokens_to_stream == amount_to_send, 'Total tokens should match',
    );
    assert(metrics_after_first.total_streams_created == 1, 'Created streams should be 1');

    // Create second stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let _stream_id2 = payment_stream
        .create_stream(
            recipient, amount_to_send, duration, cancelable, token_address, transferable,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check metrics after second stream
    let metrics_after_second = payment_stream.get_protocol_metrics();
    assert(metrics_after_second.total_active_streams == 2, 'Active streams should be 2');
    assert(
        metrics_after_second.total_tokens_to_stream == amount_to_send * 2,
        'Total tokens should be doubled',
    );
    assert(metrics_after_second.total_streams_created == 2, 'Created streams should be 2');

    // Cancel first stream
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.cancel(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check metrics after cancellation
    let metrics_after_cancel = payment_stream.get_protocol_metrics();
    assert(metrics_after_cancel.total_active_streams == 1, '1 Active streams after cancel');
    assert(
        metrics_after_cancel.total_tokens_to_stream == amount_to_send * 2,
        'Total tokens should remain same',
    );
    assert(metrics_after_cancel.total_streams_created == 2, 'Created streams should remain 2');
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_stream_metrics_accuracy() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve the payment stream to spend the sender's balance
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Get initial metrics
    let initial_metrics = payment_stream.get_stream_metrics(stream_id);

    let stream = payment_stream.get_stream(stream_id);
    println!("Stream balance: {}", stream.balance);
    println!("Stream rate per second: {}", stream.rate_per_second);

    // Warp time forward by 50 days (half the duration)
    let time_passed = calculate_seconds_in_day(50);
    println!("Time to warp forward: {} seconds", time_passed);
    start_cheat_block_timestamp_global(time_passed);
    println!("New timestamp after warp: {}", get_block_timestamp());

    // Calculate withdrawable amount
    let withdrawable = payment_stream.get_withdrawable_amount(stream_id);
    println!("Withdrawable amount after time warp: {}", withdrawable);

    // Since we've passed half the duration, we should be able to withdraw half the amount
    let expected_withdrawable = total_amount / 3;
    assert(withdrawable >= expected_withdrawable, 'Half amount not available');

    // Withdraw half of the total amount
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, expected_withdrawable, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Get updated metrics
    let updated_metrics = payment_stream.get_stream_metrics(stream_id);

    // Verify metrics reflect the operations
    assert(
        updated_metrics.total_deposited >= initial_metrics.total_deposited,
        'Deposits not increased',
    );
    assert(
        updated_metrics.total_withdrawn >= initial_metrics.total_withdrawn,
        'Withdrawals not increased',
    );
    assert(updated_metrics.total_withdrawn == expected_withdrawable, 'Wrong withdrawal amount');

    stop_cheat_block_timestamp_global();
}

#[test]
fn test_protocol_fee_rate_management() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    // Test setting fee rate
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    let new_fee_rate = 100_u64; // 1%
    payment_stream.set_protocol_fee_rate(token_address, new_fee_rate);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify fee rate was set correctly
    let stored_fee_rate = payment_stream.get_protocol_fee_rate(token_address);
    assert(stored_fee_rate == new_fee_rate, 'Fee rate not set correctly');
}

#[test]
fn test_recovery_functionality() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let recovery_address: ContractAddress = contract_address_const::<'recovery'>();

    // Create and fund a stream
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Simulate some surplus tokens in the contract
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    erc20.transfer(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Attempt recovery
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    let recovered_amount = payment_stream.recover(token_address, recovery_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    assert(recovered_amount > 0, 'Should recover surplus tokens');
}

#[test]
fn test_debt_calculations() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10_000_000_000_000_000_000_u256;
    let duration = 1_u64;
    let cancelable = true;
    let transferable = true;

    // Approve the payment stream to spend the sender's amount
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create and fund stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Get initial debt values
    let initial_total_debt = payment_stream.get_total_debt(stream_id);
    let initial_covered_debt = payment_stream.get_covered_debt(stream_id);

    // Verify debt calculations
    assert(initial_total_debt >= 0, 'Total debt non-negative');
    assert(initial_covered_debt <= initial_total_debt, 'Covered debt > total debt');

    // Warp time forward by 30 seconds
    start_cheat_block_timestamp(payment_stream.contract_address, 3605_u64);

    // Check debt after time warp
    let debt_after_1_hour = payment_stream.get_total_debt(stream_id);
    println!("Debt after 1 hour: {}", debt_after_1_hour);
    assert(debt_after_1_hour > initial_total_debt, 'Debt should increase with time');

    // Withdraw some funds
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Warp time forward by another 30 seconds
    start_cheat_block_timestamp(payment_stream.contract_address, 60_u64);

    // Get updated debt values
    let updated_total_debt = payment_stream.get_total_debt(stream_id);
    let updated_covered_debt = payment_stream.get_covered_debt(stream_id);

    // Verify debt calculations after withdrawal and time warp
    assert(updated_total_debt > debt_after_1_hour, 'Debt should continue increasing');
    assert(updated_covered_debt >= initial_covered_debt, 'Must increase after withdrawal');

    // Stop time manipulation
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_depletion_time_calculation() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve the payment stream to spend the sender's amount
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create and fund stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Debug prints
    let stream = payment_stream.get_stream(stream_id);
    println!("Stream rate per second: {}", stream.rate_per_second);
    println!("Stream balance: {}", stream.balance);
    println!("Total debt: {}", payment_stream.get_total_debt(stream_id));
    println!("Current time: {}", get_block_timestamp());

    // Get initial depletion time
    let initial_depletion_time = payment_stream.get_depletion_time(stream_id);
    println!("Initial depletion time: {}", initial_depletion_time);
    assert(initial_depletion_time > 0, 'Depletion time should be +');

    // Warp time forward by 30 seconds
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);

    // Check depletion time after time warp
    let depletion_time_after_30s = payment_stream.get_depletion_time(stream_id);
    println!("Depletion time after 30s: {}", depletion_time_after_30s);
    assert(depletion_time_after_30s < initial_depletion_time, 'Depletion time should decrease');

    // Pause stream and check depletion time
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let paused_depletion_time = payment_stream.get_depletion_time(stream_id);
    assert(paused_depletion_time == 0, 'Must be 0 for paused stream');

    // Warp time forward by another 30 seconds while paused
    start_cheat_block_timestamp(payment_stream.contract_address, 60_u64);

    // Restart stream and check depletion time
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let restarted_depletion_time = payment_stream.get_depletion_time(stream_id);
    assert(restarted_depletion_time > 0, 'Must be positive after restart');
    assert(restarted_depletion_time < depletion_time_after_30s, 'Should be < before pause');

    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_aggregate_balance_tracking() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve the payment stream to spend the sender's amount
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Check initial aggregate balance
    let initial_balance = payment_stream.get_aggregate_balance(token_address);
    assert(initial_balance == 0, 'Balance should be 0');

    // Create and fund stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check balance after deposit
    let balance_after_deposit = payment_stream.get_aggregate_balance(token_address);
    assert(balance_after_deposit == total_amount, 'Balance should match deposit');

    // Withdraw some funds
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check balance after withdrawal
    let balance_removed = withdrawn + fee;
    let balance_after_withdrawal = payment_stream.get_aggregate_balance(token_address);
    assert(
        balance_after_withdrawal == total_amount - balance_removed.into(),
        'Decrease after withdrawal',
    );
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_withdraw() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve and deposit funds
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Warp time forward by 50 days
    let time_passed = calculate_seconds_in_day(50);
    start_cheat_block_timestamp_global(time_passed);

    // Withdraw funds
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Withdraw to another address
    let another_recipient = contract_address_const::<'another_recipient'>();
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn_to_another, fee_to_another) = payment_stream
        .withdraw(stream_id, 5000_u256, another_recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify withdrawal
    let recipient_balance = erc20.balance_of(recipient);
    assert(recipient_balance == withdrawn.into(), 'Incorrect withdrawal amount');

    // Verify fee collection
    let fee_collector = payment_stream.get_fee_collector();
    let fee_collector_balance = erc20.balance_of(fee_collector);
    assert(fee_collector_balance == fee.into() * 2, 'Incorrect fee amount');

    stop_cheat_block_timestamp_global();
}

#[test]
fn test_withdraw_max_amount() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve and deposit funds
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Withdraw max amount
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    let (withdrawn, fee) = payment_stream.withdraw_max(stream_id, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify withdrawal
    let recipient_balance = erc20.balance_of(recipient);
    assert(recipient_balance == withdrawn.into(), 'Incorrect withdrawal amount');
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

// #[test]
// fn test_successful_stream_cancellation_with_balance_checks() {
//     let (token_address, sender, payment_stream, _, erc20) = setup();
//     let recipient = contract_address_const::<'recipient'>();
//     let total_amount = TOTAL_AMOUNT;
//     let duration = 100_u64;
//     let cancelable = true;
//     let transferable = true;

//     // Approve and deposit funds
//     start_cheat_caller_address(token_address, sender);
//     erc20.approve(payment_stream.contract_address, total_amount);
//     stop_cheat_caller_address(token_address);

//     // Create stream
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     let stream_id = payment_stream
//         .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Record initial balances
//     let sender_initial_balance = erc20.balance_of(sender);
//     let recipient_initial_balance = erc20.balance_of(recipient);
//     let fee_collector = payment_stream.get_fee_collector();
//     let fee_collector_initial_balance = erc20.balance_of(fee_collector);

//     // Advance time to allow some streaming
//     start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);

//     // Get expected amounts before cancellation
//     let amount_due_to_recipient = payment_stream.get_withdrawable_amount(stream_id);
//     let fee = payment_stream.get_protocol_fee_rate(token_address);
//     let calculated_fee = (amount_due_to_recipient * fee.into()) / 10000_u256;
//     let net_amount_to_recipient = amount_due_to_recipient - calculated_fee;

//     let stream_before_cancel = payment_stream.get_stream(stream_id);
//     let expected_refund = stream_before_cancel.balance - amount_due_to_recipient;

//     // Set up event spy
//     let mut spy = spy_events();

//     // Cancel stream
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     payment_stream.cancel(stream_id);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Verify stream is cancelled
//     let stream = payment_stream.get_stream(stream_id);
//     assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');
//     assert(!payment_stream.is_stream_active(stream_id), 'Stream still active');

//     // Verify ERC20 balance changes
//     if amount_due_to_recipient > 0 {
//         let recipient_final_balance = erc20.balance_of(recipient);
//         assert(
//             recipient_final_balance == recipient_initial_balance + net_amount_to_recipient,
//             'Recipient balance incorrect',
//         );

//         let fee_collector_final_balance = erc20.balance_of(fee_collector);
//         assert(
//             fee_collector_final_balance == fee_collector_initial_balance + calculated_fee,
//             'Fee collector balance incorrect',
//         );
//     }

//     if expected_refund > 0 {
//         let sender_final_balance = erc20.balance_of(sender);
//         assert(
//             sender_final_balance == sender_initial_balance + expected_refund,
//             'Sender refund incorrect',
//         );
//     }

//     // Verify event emissions
//     let events = spy.get_events();
//     let payment_stream_events = events.events.at(0);

//     if amount_due_to_recipient > 0 {
//         spy
//             .assert_emitted(
//                 @array![
//                     (
//                         payment_stream.contract_address,
//                         StreamWithdrawn {
//                             stream_id,
//                             recipient,
//                             amount: net_amount_to_recipient,
//                             protocol_fee: calculated_fee.try_into().unwrap(),
//                         },
//                     ),
//                 ],
//             );
//     }

//     if expected_refund > 0 {
//         spy
//             .assert_emitted(
//                 @array![
//                     (
//                         payment_stream.contract_address,
//                         RefundFromStream { stream_id, sender, amount: expected_refund },
//                     ),
//                 ],
//             );
//     }

//     spy.assert_emitted(@array![(payment_stream.contract_address, StreamCanceled { stream_id })]);

//     stop_cheat_block_timestamp(payment_stream.contract_address);
// }

// #[test]
// fn test_cancellation_zero_amount_due_to_recipient() {
//     // Test edge case: all funds are refundable to sender
//     let (token_address, sender, payment_stream, _, erc20) = setup();
//     let recipient = contract_address_const::<'recipient'>();
//     let total_amount = TOTAL_AMOUNT;
//     let duration = 100_u64;
//     let cancelable = true;
//     let transferable = true;

//     // Approve and deposit funds
//     start_cheat_caller_address(token_address, sender);
//     erc20.approve(payment_stream.contract_address, total_amount);
//     stop_cheat_caller_address(token_address);

//     // Create stream
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     let stream_id = payment_stream
//         .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Record initial balances
//     let sender_initial_balance = erc20.balance_of(sender);
//     let recipient_initial_balance = erc20.balance_of(recipient);
//     let fee_collector = payment_stream.get_fee_collector();
//     let fee_collector_initial_balance = erc20.balance_of(fee_collector);

//     // Cancel immediately (no time progression, so no amount due to recipient)
//     let mut spy = spy_events();

//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     payment_stream.cancel(stream_id);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Verify balances - all should be refunded to sender
//     let sender_final_balance = erc20.balance_of(sender);
//     let recipient_final_balance = erc20.balance_of(recipient);
//     let fee_collector_final_balance = erc20.balance_of(fee_collector);

//     assert(
//         sender_final_balance == sender_initial_balance + total_amount, 'Full refund not received',
//     );
//     assert(
//         recipient_final_balance == recipient_initial_balance, 'Recipient balance should not change',
//     );
//     assert(
//         fee_collector_final_balance == fee_collector_initial_balance,
//         'Fee collector balance should not change',
//     );

//     // Verify events - only RefundFromStream and StreamCanceled should be emitted
//     spy
//         .assert_emitted(
//             @array![
//                 (
//                     payment_stream.contract_address,
//                     RefundFromStream { stream_id, sender, amount: total_amount },
//                 ),
//             ],
//         );

//     spy.assert_emitted(@array![(payment_stream.contract_address, StreamCanceled { stream_id })]);

//     // Verify stream is cancelled
//     let stream = payment_stream.get_stream(stream_id);
//     assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');
// }

// #[test]
// fn test_cancellation_zero_refundable_amount() {
//     // Test edge case: all funds are payable to recipient
//     let (token_address, sender, payment_stream, _, erc20) = setup();
//     let recipient = contract_address_const::<'recipient'>();
//     let total_amount = TOTAL_AMOUNT;
//     let duration = 1_u64; // Very short duration (1 hour)
//     let cancelable = true;
//     let transferable = true;

//     // Approve and deposit funds
//     start_cheat_caller_address(token_address, sender);
//     erc20.approve(payment_stream.contract_address, total_amount);
//     stop_cheat_caller_address(token_address);

//     // Create stream
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     let stream_id = payment_stream
//         .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Record initial balances
//     let sender_initial_balance = erc20.balance_of(sender);
//     let recipient_initial_balance = erc20.balance_of(recipient);
//     let fee_collector = payment_stream.get_fee_collector();
//     let fee_collector_initial_balance = erc20.balance_of(fee_collector);

//     // Advance time past the stream's end to make all funds payable to recipient
//     start_cheat_block_timestamp(payment_stream.contract_address, 3700_u64); // 1 hour + 100 seconds

//     let amount_due_to_recipient = payment_stream.get_withdrawable_amount(stream_id);
//     let fee = payment_stream.get_protocol_fee_rate(token_address);
//     let calculated_fee = (amount_due_to_recipient * fee.into()) / 10000_u256;
//     let net_amount_to_recipient = amount_due_to_recipient - calculated_fee;

//     let mut spy = spy_events();

//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     payment_stream.cancel(stream_id);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Verify balances - all should go to recipient (minus fee)
//     let sender_final_balance = erc20.balance_of(sender);
//     let recipient_final_balance = erc20.balance_of(recipient);
//     let fee_collector_final_balance = erc20.balance_of(fee_collector);

//     assert(sender_final_balance == sender_initial_balance, 'Sender balance should not change');
//     assert(
//         recipient_final_balance == recipient_initial_balance + net_amount_to_recipient,
//         'Recipient did not receive correct amount',
//     );
//     assert(
//         fee_collector_final_balance == fee_collector_initial_balance + calculated_fee,
//         'Fee collector did not receive correct fee',
//     );

//     // Verify events - only StreamWithdrawn and StreamCanceled should be emitted
//     spy
//         .assert_emitted(
//             @array![
//                 (
//                     payment_stream.contract_address,
//                     StreamWithdrawn {
//                         stream_id,
//                         recipient,
//                         amount: net_amount_to_recipient,
//                         protocol_fee: calculated_fee.try_into().unwrap(),
//                     },
//                 ),
//             ],
//         );

//     spy.assert_emitted(@array![(payment_stream.contract_address, StreamCanceled { stream_id })]);

//     // Verify stream is cancelled
//     let stream = payment_stream.get_stream(stream_id);
//     assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');

//     stop_cheat_block_timestamp(payment_stream.contract_address);
// }

// #[test]
// fn test_cancellation_both_amounts_zero() {
//     // Test edge case: stream with zero balance - no transfers should occur
//     let (token_address, sender, payment_stream, _, erc20) = setup();
//     let recipient = contract_address_const::<'recipient'>();
//     let total_amount = 1000_u256; // Smaller amount for easier testing
//     let duration = 1_u64;
//     let cancelable = true;
//     let transferable = true;

//     // Approve and deposit funds
//     start_cheat_caller_address(token_address, sender);
//     erc20.approve(payment_stream.contract_address, total_amount);
//     stop_cheat_caller_address(token_address);

//     // Create stream
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     let stream_id = payment_stream
//         .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Advance time and withdraw all funds first
//     start_cheat_block_timestamp(payment_stream.contract_address, 3700_u64);
//     start_cheat_caller_address(payment_stream.contract_address, recipient);
//     payment_stream.withdraw_max(stream_id, recipient);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Record balances after withdrawal
//     let sender_balance_before_cancel = erc20.balance_of(sender);
//     let recipient_balance_before_cancel = erc20.balance_of(recipient);
//     let fee_collector = payment_stream.get_fee_collector();
//     let fee_collector_balance_before_cancel = erc20.balance_of(fee_collector);

//     // Verify stream has zero balance
//     let stream_before_cancel = payment_stream.get_stream(stream_id);
//     assert(stream_before_cancel.balance == 0, 'Stream should have zero balance');

//     let mut spy = spy_events();

//     // Cancel stream with zero balance
//     start_cheat_caller_address(payment_stream.contract_address, sender);
//     payment_stream.cancel(stream_id);
//     stop_cheat_caller_address(payment_stream.contract_address);

//     // Verify no balance changes occurred
//     let sender_balance_after_cancel = erc20.balance_of(sender);
//     let recipient_balance_after_cancel = erc20.balance_of(recipient);
//     let fee_collector_balance_after_cancel = erc20.balance_of(fee_collector);

//     assert(
//         sender_balance_after_cancel == sender_balance_before_cancel,
//         'Sender balance should not change',
//     );
//     assert(
//         recipient_balance_after_cancel == recipient_balance_before_cancel,
//         'Recipient balance should not change',
//     );
//     assert(
//         fee_collector_balance_after_cancel == fee_collector_balance_before_cancel,
//         'Fee collector balance should not change',
//     );

//     // Verify only StreamCanceled event is emitted (no withdrawal or refund events)
//     spy.assert_emitted(@array![(payment_stream.contract_address, StreamCanceled { stream_id })]);

//     // Verify stream is cancelled
//     let stream = payment_stream.get_stream(stream_id);
//     assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');

//     stop_cheat_block_timestamp(payment_stream.contract_address);
// }

#[test]
fn test_pause_and_restart_stream() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve and deposit funds
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Pause stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream is paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream not paused');

    // Restart stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream is active again
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Active, 'Stream not restarted');
}

#[test]
fn test_delegate_assignment_and_verification() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);

    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, recipient);
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify delegate assignment
    let assigned_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(assigned_delegate == delegate, 'Wrong delegate assigned');
}

#[test]
fn test_multiple_delegations() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate1 = contract_address_const::<'delegate1'>();
    let delegate2 = contract_address_const::<'delegate2'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Assign first delegate
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    payment_stream.delegate_stream(stream_id, delegate1);

    let first_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(first_delegate == delegate1, 'First delegation failed');

    let _bool = payment_stream.revoke_delegation(stream_id);

    // Assign second delegate (should override first)
    payment_stream.delegate_stream(stream_id, delegate2);

    let second_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(second_delegate == delegate2, 'Second delegation failed');
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_delegation_revocation() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream and assign delegate
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, recipient);
    payment_stream.delegate_stream(stream_id, delegate);

    // Verify delegate is assigned
    let assigned_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(assigned_delegate == delegate, 'Delegate not assigned');

    // Revoke delegation
    payment_stream.revoke_delegation(stream_id);

    // Verify delegate is removed
    let delegate_after_revocation = payment_stream.get_stream_delegate(stream_id);
    assert(delegate_after_revocation == contract_address_const::<0x0>(), 'Delegate not revoked');
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Only the NFT owner can delegate')]
fn test_unauthorized_delegation() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream as sender
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to delegate from unauthorized address
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);
    start_cheat_caller_address(payment_stream.contract_address, unauthorized);
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Stream does not exist.')]
fn test_revoke_nonexistent_delegation() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    // Try to revoke non-existent delegation
    payment_stream.revoke_delegation(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_delegate_withdrawal_after_revocation() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream and setup
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Assign and then revoke delegate
    start_cheat_caller_address(payment_stream.contract_address, recipient);
    payment_stream.delegate_stream(stream_id, delegate);
    payment_stream.revoke_delegation(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Attempt withdrawal as revoked delegate
    start_cheat_caller_address(payment_stream.contract_address, delegate);
    payment_stream.withdraw(stream_id, 1000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_delegate_to_zero_address() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    // Try to delegate to zero address
    payment_stream.delegate_stream(stream_id, contract_address_const::<0x0>());
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_successful_refund() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve and deposit funds
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Get initial balance
    let sender_initial_balance = erc20.balance_of(sender);

    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);
    // Refund amount
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.cancel(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
    // Verify refund
    let sender_final_balance = erc20.balance_of(sender);
    assert(sender_final_balance > sender_initial_balance, 'balance unchanged');
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_nft_transfer_and_withdrawal() {
    let (token_address, sender, payment_stream, erc721, erc20) = setup();
    let initial_owner = contract_address_const::<'initial_owner'>();
    let new_owner = contract_address_const::<'new_owner'>();
    let total_amount = TOTAL_AMOUNT;
    let duration = 100_u64;
    let cancelable = true;
    let transferable = true;

    // Approve and deposit funds
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            initial_owner, total_amount, duration, cancelable, token_address, transferable,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify initial ownership
    let owner = erc721.owner_of(stream_id);
    assert(owner == initial_owner, 'wrong owner');

    // Transfer NFT
    start_cheat_caller_address(payment_stream.contract_address, initial_owner);
    erc721.approve(initial_owner, stream_id);
    erc721.transfer_from(initial_owner, new_owner, stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify new ownership
    let new_owner_check = erc721.owner_of(stream_id);
    assert(new_owner_check == new_owner, 'transfer failed');

    // New owner withdraws
    start_cheat_block_timestamp(payment_stream.contract_address, 30_u64);

    start_cheat_caller_address(payment_stream.contract_address, new_owner);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 1000_u256, new_owner);

    // Verify withdrawal
    let new_owner_balance = erc20.balance_of(new_owner);
    assert(new_owner_balance == withdrawn.into(), 'wrong amount');
    stop_cheat_caller_address(payment_stream.contract_address);
    stop_cheat_block_timestamp(payment_stream.contract_address);
}

#[test]
fn test_six_decimals_store() {
    let test_decimals = 6_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);
    let total_amount = 1000000_u256; // 1 token in 6 decimals
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(sender, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, 'wrong decimals');

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.token_decimals == test_decimals, 'wrong stream decimals');
}

#[test]
fn test_zero_decimals() {
    let test_decimals = 0_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);
    let total_amount = 100_u256; // 100 tokens (0 decimals)
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(sender, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, 'wrong decimals');

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.token_decimals == test_decimals, 'wrong stream decimals');
}

#[test]
fn test_eighteen_decimals() {
    let test_decimals = 18_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);
    let total_amount = TOTAL_AMOUNT; // 1 token in 18 decimals
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(sender, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, 'wrong decimals');

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.token_decimals == test_decimals, 'wrong stream decimals');
}

#[test]
#[should_panic(expected: 'Error: Decimals too high.')]
fn test_nineteen_decimals_panic() {
    let test_decimals = 19_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);
    let total_amount = TOTAL_AMOUNT;
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20 = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(sender, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_decimal_boundary_conditions() {
    // Test max allowed decimals (18)
    let (token18, sender18, ps18) = setup_custom_decimals(18);
    let total_amount = TOTAL_AMOUNT; // 1 token in 18 decimals
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20_18 = IERC20Dispatcher { contract_address: token18 };
    start_cheat_caller_address(token18, sender18);
    erc20_18.approve(ps18.contract_address, total_amount);
    stop_cheat_caller_address(token18);

    start_cheat_caller_address(ps18.contract_address, sender18);
    let stream_id18 = ps18
        .create_stream(sender18, total_amount, duration, cancelable, token18, transferable);
    stop_cheat_caller_address(ps18.contract_address);
    assert(ps18.get_token_decimals(stream_id18) == 18, 'max failed');

    // Test min allowed decimals (0)
    let (token0, sender0, ps0) = setup_custom_decimals(0);
    let total_amount = 100_u256; // 100 tokens in 0 decimals
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Approve tokens before creating stream
    let erc20_0 = IERC20Dispatcher { contract_address: token0 };
    start_cheat_caller_address(token0, sender0);
    erc20_0.approve(ps0.contract_address, total_amount);
    stop_cheat_caller_address(token0);

    start_cheat_caller_address(ps0.contract_address, sender0);
    let stream_id0 = ps0
        .create_stream(sender0, total_amount, duration, cancelable, token0, transferable);
    stop_cheat_caller_address(ps0.contract_address);
    assert(ps0.get_token_decimals(stream_id0) == 0, 'min failed');
}

#[test]
fn test_withdrawable_amount_after_pause() {
    let (token_address, sender, payment_stream, _, erc20) = setup();
    let total_amount = TOTAL_AMOUNT;
    let duration = 30_u64;
    let cancelable = true;
    let transferable = true;

    // Create stream
    start_cheat_caller_address(token_address, sender);
    erc20.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(sender, total_amount, duration, cancelable, token_address, transferable);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Advance time by 10 seconds
    start_cheat_block_timestamp(payment_stream.contract_address, 10);

    // Get withdrawable amount before pause
    let pre_pause_amount = payment_stream.get_withdrawable_amount(stream_id);
    println!("pre_pause_amount: {}", pre_pause_amount);
    assert(pre_pause_amount > 0, 'should have withdrawable amount');

    // Pause the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
    stop_cheat_block_timestamp(payment_stream.contract_address);

    // Advance time more
    start_cheat_block_timestamp(payment_stream.contract_address, 20);

    // Get withdrawable amount after pause - should be same as before
    let post_pause_amount = payment_stream.get_withdrawable_amount(stream_id);
    println!("post_pause_amount: {}", post_pause_amount);
    assert(post_pause_amount == pre_pause_amount, 'amount should not increase');
    stop_cheat_block_timestamp(payment_stream.contract_address);
}
