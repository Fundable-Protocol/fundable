use core::traits::Into;
use fp::UFixedPoint123x128;
use fundable::base::types::{Stream, StreamStatus};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};

// Constantes para roles
const STREAM_ADMIN_ROLE: felt252 = selector!("STREAM_ADMIN");
const PROTOCOL_OWNER_ROLE: felt252 = selector!("PROTOCOL_OWNER");

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
    let mut calldata = array![sender.into(), sender.into()];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Payment stream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@calldata).unwrap();

    (
        erc20_address,
        sender,
        IPaymentStreamDispatcher { contract_address: payment_stream_address },
        IAccessControlDispatcher { contract_address: payment_stream_address },
        IERC721Dispatcher { contract_address: payment_stream_address },
    )
}

fn setup() -> (ContractAddress, ContractAddress, IPaymentStreamDispatcher, IERC721Dispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into()];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy Payment stream contract
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let payment_stream_class = declare("PaymentStream").unwrap().contract_class();
    let mut calldata = array![protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@calldata).unwrap();

    (
        erc20_address,
        sender,
        IPaymentStreamDispatcher { contract_address: payment_stream_address },
        IERC721Dispatcher { contract_address: payment_stream_address },
    )
}

#[test]
fn test_nft_metadata() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    let metadata = IERC721MetadataDispatcher { contract_address: payment_stream.contract_address };

    let name = metadata.name();
    let symbol = metadata.symbol();
    let token_uri = metadata.token_uri(stream_id);

    assert!(name == "PaymentStream", "Incorrect NFT name");
    assert!(symbol == "STREAM", "Incorrect NFT symbol");
    assert!(token_uri == "https://paymentstream.io/0", "Incorrect token URI");
}

#[test]
fn test_successful_create_stream() {
    let (token_address, _sender, payment_stream, erc721) = setup();
    let initial_owner = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(
            initial_owner, total_amount, start_time, end_time, cancelable, token_address,
        );
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");
    let owner = erc721.owner_of(stream_id);
    assert!(owner == initial_owner, "NFT not minted to initial owner");
}
#[test]
#[should_panic(expected: 'Error: End time < start time.')]
fn test_invalid_end_time() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let initial_owner = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 50_u64;
    let cancelable = true;

    payment_stream
        .create_stream(
            initial_owner, total_amount, start_time, end_time, cancelable, token_address,
        );
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_zero_recipient_address() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let initial_owner = contract_address_const::<0x0>(); // Invalid ro address
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(
            initial_owner, total_amount, start_time, end_time, cancelable, token_address,
        );
}

#[test]
#[should_panic(expected: 'Error: Invalid token address.')]
fn test_zero_token_address() {
    let (_token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(
            recipient,
            total_amount,
            start_time,
            end_time,
            cancelable,
            contract_address_const::<0x0>(),
        );
}
#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_zero_total_amount() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 0_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
}

#[test]
fn test_successful_create_stream_and_return_correct_rate_per_second() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 100_u256;
    let start_time = 0_u64;
    let end_time = 10_u64;
    let cancelable = false;

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    let stream = payment_stream.get_stream(stream_id);
    let rate_per_second: UFixedPoint123x128 = 10_u256.into();
    assert!(stream.rate_per_second == rate_per_second, "Stream rate per second is invalid");
}

#[test]
fn test_successful_create_stream_and_return_wrong_rate_per_second() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 100_u256;
    let start_time = 0_u64;
    let end_time = 10_u64;
    let cancelable = false;

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    let stream = payment_stream.get_stream(stream_id);
    let rate_per_second: UFixedPoint123x128 = 1_u256.into();
    assert!(stream.rate_per_second == rate_per_second, "Stream rate per second is invalid");
}

#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_update_stream_with_zero_rate_per_second() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 100_u256;
    let start_time = 0_u64;
    let end_time = 10_u64;
    let cancelable = false;

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    let rate_per_second: UFixedPoint123x128 = 0_u256.into();
    payment_stream.update_stream_rate(stream_id, rate_per_second);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Not stream sender.')]
fn test_only_creator_can_update_stream() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let total_amount = 100_u256;
    let start_time = 0_u64;
    let end_time = 10_u64;
    let cancelable = false;

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    payment_stream.delegate_stream(stream_id, contract_address_const::<0x1>());
    stop_cheat_caller_address(payment_stream.contract_address);
    let rate_per_second: UFixedPoint123x128 = 1_u256.into();

    // Unauthorized account to update stream.
    start_cheat_caller_address(payment_stream.contract_address, unauthorized);
    payment_stream.update_stream_rate(stream_id, rate_per_second);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_update_fee_collector() {
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    let (token_address, sender, payment_stream, _erc721) = setup();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);

    let fee_collector = payment_stream.get_fee_collector();
    assert(fee_collector == new_fee_collector, 'wrong fee collector');
}

#[test]
fn test_update_percentage_protocol_fee() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_percentage_protocol_fee(300);
}

#[test]
fn test_withdraw() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let delegate = contract_address_const::<'delegate'>();

    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(delegate, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(payment_stream.contract_address, delegate);
    let (_, fee) = payment_stream.withdraw(stream_id, 1000, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // let recipient_balance = token_dispatcher.balance_of(recipient);
    // println!("Recipient's balance after withdrawal: {}", recipient_balance);

    let fee_collector = payment_stream.get_fee_collector();
    let fee_collector_balance = token_dispatcher.balance_of(fee_collector);
    assert(fee_collector_balance == fee.into(), 'incorrect fee received');

    let sender_final_balance = token_dispatcher.balance_of(sender);
    println!("Sender's final balance: {}", sender_final_balance);
}

#[test]
fn test_successful_stream_cancellation() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");

    payment_stream.cancel(stream_id);
    let get_let = payment_stream.is_stream_active(stream_id);

    assert(get_let == false, 'Cancelation failed');
}

#[test]
fn test_withdraw_by_delegate() {
    // Setup: deploy contracts and define test addresses.
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    // Sender creates a stream.
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Simulate delegate's approval:
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, 5000_u256);
    stop_cheat_caller_address(token_address);

    // Delegate performs withdrawal.
    start_cheat_caller_address(payment_stream.contract_address, delegate);
    let (_, fee) = payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    let fee_collector = payment_stream.get_fee_collector();
    let fee_collector_balance = token_dispatcher.balance_of(fee_collector);
    assert(fee_collector_balance == fee.into(), 'incorrect fee received');
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_withdraw_by_unauthorized() {
    // Setup: deploy contracts and define test addresses.
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Sender creates a stream.
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Unauthorized account attempts withdrawal.
    start_cheat_caller_address(payment_stream.contract_address, unauthorized);
    payment_stream.withdraw(stream_id, 5000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_unauthorized_cancel() {
    let (token_address, sender, payment_stream, access_control, _erc721) = setup_access_control();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream as the sender - this will automatically assign STREAM_ADMIN_ROLE
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Verify that the sender has the STREAM_ADMIN_ROLE after creating the stream
    let has_role = access_control.has_role(STREAM_ADMIN_ROLE, sender);
    assert(has_role, 'Sender should have admin role');
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to cancel the stream with an unauthorized user (recipient)
    // The recipient does not have the STREAM_ADMIN_ROLE
    start_cheat_caller_address(payment_stream.contract_address, recipient);

    // Verify that the recipient does NOT have the STREAM_ADMIN_ROLE
    let recipient_has_role = access_control.has_role(STREAM_ADMIN_ROLE, recipient);
    assert(!recipient_has_role, 'Recipient should not have role');

    payment_stream.cancel(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_pause_stream() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Pause the stream
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');
}

#[test]
fn test_restart_stream() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Pause the stream first
    payment_stream.pause(stream_id);

    // Verify that the stream was paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');

    // Restart the stream with a new rate
    let new_rate: UFixedPoint123x128 = 100_u256.into(); // Rate per second
    payment_stream.restart(stream_id, new_rate);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was restarted
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Active, 'Stream should be active');
    assert(stream.rate_per_second == new_rate, 'Rate should be updated');
}
#[test]
fn test_void_stream() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create a stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Void the stream
    payment_stream.void(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the stream was voided
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Voided, 'Stream should be voided');
}

#[test]
fn test_delegate_assignment_and_verification() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Assign delegate
    let delegation_success = payment_stream.delegate_stream(stream_id, delegate);
    assert(delegation_success == true, 'Delegation should succeed');

    // Verify delegate assignment
    let assigned_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(assigned_delegate == delegate, 'Wrong delegate assigned');
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_multiple_delegations() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate1 = contract_address_const::<'delegate1'>();
    let delegate2 = contract_address_const::<'delegate2'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Assign first delegate
    payment_stream.delegate_stream(stream_id, delegate1);
    let first_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(first_delegate == delegate1, 'First delegation failed');

    // Assign second delegate (should override first)
    payment_stream.delegate_stream(stream_id, delegate2);
    let second_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(second_delegate == delegate2, 'Second delegation failed');
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_delegation_revocation() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream and assign delegate
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    payment_stream.delegate_stream(stream_id, delegate);

    // Verify delegate is assigned
    let assigned_delegate = payment_stream.get_stream_delegate(stream_id);
    assert(assigned_delegate == delegate, 'Delegate not assigned');

    // Revoke delegation
    let revocation_success = payment_stream.revoke_delegation(stream_id);
    assert(revocation_success == true, 'Revocation should succeed');

    // Verify delegate is removed
    let delegate_after_revocation = payment_stream.get_stream_delegate(stream_id);
    assert(delegate_after_revocation == contract_address_const::<0x0>(), 'Delegate not revoked');
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Not stream sender.')]
fn test_unauthorized_delegation() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let unauthorized = contract_address_const::<'unauthorized'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream as sender
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to delegate from unauthorized address
    start_cheat_caller_address(payment_stream.contract_address, unauthorized);
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Stream does not exist.')]
fn test_revoke_nonexistent_delegation() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Try to revoke non-existent delegation
    payment_stream.revoke_delegation(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_delegate_withdrawal_after_revocation() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let delegate = contract_address_const::<'delegate'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    // Create stream and setup
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);

    // Assign and then revoke delegate
    payment_stream.delegate_stream(stream_id, delegate);
    payment_stream.revoke_delegation(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Setup delegate's approval
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, 5000_u256);
    stop_cheat_caller_address(token_address);

    // Attempt withdrawal as revoked delegate (should fail with WRONG_RECIPIENT_OR_DELEGATE)
    start_cheat_caller_address(payment_stream.contract_address, delegate);
    // This should panic with the expected error since the delegate was revoked
    payment_stream.withdraw(stream_id, 1000_u256, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_delegate_to_zero_address() {
    // Setup
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(recipient, total_amount, start_time, end_time, cancelable, token_address);
    // Try to delegate to zero address
    payment_stream.delegate_stream(stream_id, contract_address_const::<0x0>());
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_nft_transfer_and_withdrawal() {
    let (token_address, sender, payment_stream, erc721) = setup();
    let initial_owner = contract_address_const::<'initial_owner'>();
    let new_owner = contract_address_const::<'new_owner'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream as sender
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            initial_owner, total_amount, start_time, end_time, cancelable, token_address,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Approve tokens for PaymentStream (sender funds the stream)
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    // Verify initial ownership
    let owner = erc721.owner_of(stream_id);
    assert!(owner == initial_owner, "Initial owner mismatch");

    // Transfer NFT from initial_owner to new_owner
    start_cheat_caller_address(payment_stream.contract_address, initial_owner);
    erc721.transfer_from(initial_owner, new_owner, stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify new ownership
    let new_owner_check = erc721.owner_of(stream_id);
    assert!(new_owner_check == new_owner, "NFT ownership not transferred");

    // New owner withdraws
    start_cheat_caller_address(payment_stream.contract_address, new_owner);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 1000_u256, new_owner);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Basic withdrawal check
    assert!(withdrawn.into() == 1000_u128, "Withdrawal amount incorrect");
}

