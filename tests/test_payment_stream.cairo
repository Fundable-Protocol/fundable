use core::traits::Into;
use fp::UFixedPoint123x128;
use fundable::base::types::StreamStatus;
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use fundable::payment_stream::PaymentStream;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address, test_address,
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
    let mut calldata = array![sender.into(), sender.into(), 6];
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
    let mut calldata = array![sender.into(), sender.into(), 6];
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
    let mut ps_calldata = array![protocol_owner.into()];
    let (payment_stream_address, _) = payment_stream_class.deploy(@ps_calldata).unwrap();

    (erc20_address, sender, IPaymentStreamDispatcher { contract_address: payment_stream_address })
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
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
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true; // Corrected spelling from tranferable to transferable
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");
    let owner = erc721.owner_of(stream_id);
    assert!(owner == recipient, "NFT not minted to initial owner");
}

#[test]
fn test_create_stream_with_deposit() {
    let (token_address, sender, payment_stream, erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Approve the Payment Stream contract to spend tokens
    let token = IERC20Dispatcher { contract_address: token_address };
    token.approve(payment_stream.contract_address, total_amount);

    // Create the stream with deposit in a single transaction
    let stream_id = payment_stream
        .create_stream_with_deposit(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Verify stream was created successfully
    assert!(stream_id == 0_u256, "Stream creation failed");

    // Verify NFT ownership
    let owner = erc721.owner_of(stream_id);
    assert!(owner == recipient, "NFT not minted to recipient");

    // Verify stream data
    let stream = payment_stream.get_stream(stream_id);
    assert!(stream.sender == sender, "Wrong sender");
    assert!(stream.total_amount == total_amount, "Wrong total amount");
    assert!(stream.balance == total_amount, "Wrong balance - deposit failed");
    assert!(stream.status == StreamStatus::Active, "Stream not active");
}

#[test]
#[should_panic(expected: 'Error: End time < start time.')]
fn test_invalid_end_time() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 50_u64;
    let cancelable = true;
    let transferable = true; // Added transferable boolean

    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
}

#[test]
#[should_panic(expected: 'Error: Invalid recipient.')]
fn test_zero_recipient_address() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x0>(); // Invalid ro address
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true; // Added transferable boolean

    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
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
    let transferable = true; // Added transferable boolean

    payment_stream
        .create_stream(
            recipient,
            total_amount,
            start_time,
            end_time,
            cancelable,
            contract_address_const::<0x0>(),
            transferable,
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
    let transferable = true;

    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
}

#[test]
fn test_successful_create_stream_and_return_correct_rate_per_second() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 100_u256;
    let start_time = 0_u64;
    let end_time = 10_u64;
    let cancelable = false;
    let transferable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
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
    let transferable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
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
    let transferable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
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
    let transferable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
    payment_stream.delegate_stream(stream_id, contract_address_const::<0x1>());
    stop_cheat_caller_address(payment_stream.contract_address);
    let rate_per_second: UFixedPoint123x128 = 1_u256.into();

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");
    payment_stream.delegate_stream(stream_id, test_address());
    payment_stream.cancel(stream_id);
    let get_let = payment_stream.is_stream_active(stream_id);

    assert(!get_let, 'Cancelation failed');
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        ); // Added transferable boolean

    // Try to delegate to zero address
    payment_stream.delegate_stream(stream_id, contract_address_const::<0x0>());
    stop_cheat_caller_address(payment_stream.contract_address);
}


#[test]
fn test_successful_refund() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Deposit to the stream
    payment_stream.deposit(stream_id, total_amount);

    // Cancel the stream first (required for refund)
    payment_stream.cancel(stream_id);

    // Verify stream is canceled and can be refunded
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Canceled, 'Stream should be canceled');

    // Get available amount for refund
    let refundable_amount = total_amount - stream.withdrawn_amount;
    println!("Refundable amount: {}", refundable_amount);

    // Perform the refund (still as the sender)
    let refund_success = payment_stream.refund(stream_id, refundable_amount);

    // Verify refund was successful
    assert(refund_success, 'Refund should be successful');

    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_successful_refund_with_wrong_address() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create Stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check sender's initial balance
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Refund execution
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let success = payment_stream.refund(stream_id, 10);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Insufficient Balance')]
fn test_successful_refund_with_overdraft() {
    let (token_address, _sender, payment_stream, _) = setup();
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");

    let get_let = payment_stream.refund(stream_id, 10000);

    assert(get_let == false, 'Refund failed');
}

#[test]
fn test_successful_refund_max() {
    let (token_address, sender, payment_stream, _) = setup();
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, sender);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(sender, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let success = payment_stream.refund_max(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
    let sender_final_balance = token_dispatcher.balance_of(sender);
    assert(success, 'Refund failed');
    assert(sender_final_balance == sender_initial_balance, 'Balance Refund failed');
    // println!("Final Bal: {}", sender_final_balance);
}
#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_successful_refund_max_with_wrong_address() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create Stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check sender's initial balance
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Refund execution
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let _success = payment_stream.refund_max(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_successful_refund_and_pause() {
    let (token_address, sender, payment_stream, _) = setup();
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    // Sender assigns a delegate.
    payment_stream.delegate_stream(stream_id, sender);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Simulate delegate's approval:
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(sender, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');
    println!("Allowance for withdrawal: {}", allowance);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let success = payment_stream.refund_and_pause(stream_id, 10);
    stop_cheat_caller_address(payment_stream.contract_address);
    let sender_final_balance = token_dispatcher.balance_of(sender);
    assert(success, 'Refund failed');
    println!("Final Bal: {}", sender_final_balance);
    assert(sender_final_balance == sender_initial_balance, 'Balance Refund failed');
    // Verify that the stream was paused
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');
}

#[test]
#[should_panic(expected: 'WRONG_RECIPIENT_OR_DELEGATE')]
fn test_successful_refund_and_pause_with_wrong_address() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create Stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check sender's initial balance
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    let sender_initial_balance = token_dispatcher.balance_of(sender);
    println!("Initial balance of sender: {}", sender_initial_balance);

    // Refund execution
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let success = payment_stream.refund_and_pause(stream_id, 10);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Insufficient Balance')]
fn test_successful_refund_and_pause_with_overdraft() {
    let (token_address, _sender, payment_stream, _) = setup();
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    // This is the first Stream Created, so it will be 0.
    assert!(stream_id == 0_u256, "Stream creation failed");

    let get_let = payment_stream.refund(stream_id, 10000);

    assert(get_let == false, 'Refund failed');
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

    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Create stream as sender
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            initial_owner, total_amount, start_time, end_time, cancelable, token_address, true,
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

    start_cheat_caller_address(token_address, new_owner);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);
    // New owner withdraws
    start_cheat_caller_address(payment_stream.contract_address, new_owner);
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 1000_u256, new_owner);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Basic withdrawal check
    assert!(withdrawn.into() == 1000_u128, "Withdrawal amount incorrect");
}

#[test]
fn test_six_decimals_store() {
    let test_decimals = 6_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);

    let stream_id = payment_stream
        .create_stream(sender, 1000000_u256, 100_u64, 200_u64, true, token_address, true);

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, 'Decimals not stored correctly');

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.token_decimals == test_decimals, 'Stream decimals mismatch');
}

#[test]
fn test_zero_decimals() {
    let test_decimals = 0_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);

    let stream_id = payment_stream
        .create_stream(
            sender,
            100_u256,
            100_u64,
            200_u64,
            true,
            token_address,
            true // Added transferable boolean
        );

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, 'Zero decimals not stored');

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.token_decimals == test_decimals, 'Stream decimals mismatch');
}

#[test]
fn test_eighteen_decimals() {
    let test_decimals = 18_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);

    let stream_id = payment_stream
        .create_stream(
            sender,
            1000000000000000000_u256, // 1 token
            100_u64,
            200_u64,
            true,
            token_address,
            true // Added transferable boolean
        );

    let stored_decimals = payment_stream.get_token_decimals(stream_id);
    assert(stored_decimals == test_decimals, '18 decimals not stored');
}

#[test]
#[should_panic(expected: 'Error: Decimals too high.')]
fn test_nineteen_decimals_panic() {
    let test_decimals = 19_u8;
    let (token_address, sender, payment_stream) = setup_custom_decimals(test_decimals);

    // should panic because decimals > 18
    payment_stream
        .create_stream(
            sender, 10000000000000000000_u256, 100_u64, 200_u64, true, token_address, true,
        ); // Added transferable boolean
}

#[test]
fn test_decimal_boundary_conditions() {
    // Test max allowed decimals (18)
    let (token18, sender18, ps18) = setup_custom_decimals(18);
    let stream_id18 = ps18
        .create_stream(
            sender18, // recipient
            1000000000000000000_u256, // 1 token in 18 decimals
            100_u64, // start_time
            200_u64, // end_time
            true, // cancelable
            token18, // token address
            true // Added transferable boolean
        );
    assert(ps18.get_token_decimals(stream_id18) == 18, 'Max decimals failed');

    // Test min allowed decimals (0)
    let (token0, sender0, ps0) = setup_custom_decimals(0);
    let stream_id0 = ps0
        .create_stream(
            sender0, // recipient
            100_u256, // 100 tokens in 0 decimals
            100_u64, // start_time
            200_u64, // end_time
            true, // cancelable
            token0, // token address
            true // Added transferable boolean
        );
    assert(ps0.get_token_decimals(stream_id0) == 0, 'Min decimals failed');
}

// New tests for the added functions
#[test]
fn test_transfer_stream() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    let new_recipient = contract_address_const::<'new_recipient'>();
    payment_stream.transfer_stream(stream_id, new_recipient);

    let stream = payment_stream.get_stream(stream_id);
    assert(stream.recipient == new_recipient, 'Recipient update error');
}

#[test]
fn test_set_transferability() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    payment_stream.set_transferability(stream_id, false);

    let stream = payment_stream.get_stream(stream_id);
    assert(!stream.transferable, 'Transferability setting error');
}

#[test]
fn test_is_transferable() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 10000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    let is_transferable = payment_stream.is_transferable(stream_id);
    assert(is_transferable, 'Stream should be transferable');
}

#[test]
fn test_set_protocol_fee_successful() {
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let fee: u256 = 500; // 5%
    let (token_address, sender, payment_stream, _) = setup();
    // Set fee
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.set_protocol_fee(token_address, fee);
    stop_cheat_caller_address(payment_stream.contract_address);

    assert(payment_stream.get_protocol_fee(token_address) == fee, 'invalid fee')
}

#[test]
#[should_panic]
fn test_set_protocol_fee_fail_if_more_than_max_fee() {
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let fee: u256 = 10000; // 100%. MAX_FEE = 50%
    let (token_address, sender, payment_stream, _) = setup();
    // Set fee
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.set_protocol_fee(token_address, fee); // should panic
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic]
fn test_set_protocol_fee_fail_if_invalid_caller() {
    let random_caller: ContractAddress = contract_address_const::<'random'>();
    let fee: u256 = 500; // 5%
    let (token_address, sender, payment_stream, _) = setup();
    // Set fee
    start_cheat_caller_address(payment_stream.contract_address, random_caller);
    payment_stream.set_protocol_fee(token_address, fee); // should panic
    stop_cheat_caller_address(payment_stream.contract_address);
}

fn test_successful_stream_check() {
    let (token_address, _sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    let is_stream = payment_stream.is_stream(stream_id);
    assert!(is_stream, "Stream is non existent");
}

#[test]
fn test_successful_pause_check() {
    let (token_address, _sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    let is_paused = payment_stream.is_paused(stream_id);
    assert!(!is_paused, "Stream is paused");

    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let is_paused = payment_stream.is_paused(stream_id);
    assert!(is_paused, "Stream is not paused");
}

#[test]
fn test_successful_voided_check() {
    let (token_address, _sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    let is_voided = payment_stream.is_voided(stream_id);
    assert!(!is_voided, "Stream is voided");

    payment_stream.void(stream_id);

    let is_voided = payment_stream.is_voided(stream_id);
    assert!(is_voided, "Stream is not voided");
}


#[test]
fn test_successful_transferrable_check() {
    let (token_address, _sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);

    let is_transferable = payment_stream.is_transferable(stream_id);
    assert!(is_transferable, "Stream is not transferable");
}

#[test]
fn test_successful_get_sender() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let get_sender = payment_stream.get_sender(stream_id);
    assert!(get_sender == sender, "Stream is not transferable");
}


#[test]
fn test_successful_get_recipient() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let get_recipient = payment_stream.get_recipient(stream_id);
    assert!(get_recipient == recipient, "Stream is not transferable");
}


#[test]
fn test_successful_get_token() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let get_token = payment_stream.get_token(stream_id);
    assert!(get_token == token_address, "Stream is not transferable");
}

#[test]
fn test_successful_get_rate_per_second() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let rate_per_second: UFixedPoint123x128 = 10_u256.into();

    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    println!("Stream ID: {}", stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    let get_rate_per_second = payment_stream.get_rate_per_second(stream_id);
    assert!(get_rate_per_second == rate_per_second, "Stream is not transferable");
}

#[test]
fn test_deposit_successful() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 500_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Setup token approval for deposit
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, deposit_amount);
    stop_cheat_caller_address(token_address);

    // Deposit additional funds
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.deposit(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream amount was updated
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.total_amount == total_amount + deposit_amount, 'Deposit amount not added');
}

#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_deposit_zero_amount() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 0_u256; // Zero amount should fail
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Try to deposit zero amount - should panic
    payment_stream.deposit(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Stream is voided')]
fn test_deposit_to_voided_stream() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 500_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Void the stream
    payment_stream.void(stream_id);

    // Setup token approval
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, deposit_amount);
    stop_cheat_caller_address(token_address);

    // Try to deposit to voided stream - should panic
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.deposit(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Stream is canceled')]
fn test_deposit_to_canceled_stream() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 500_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Get protocol owner for setting up fee collector
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let new_fee_collector: ContractAddress = contract_address_const::<'new_fee_collector'>();

    // Setup fee collector
    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.update_fee_collector(new_fee_collector);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Create and cancel stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    payment_stream.cancel(stream_id);

    // Setup token approval
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, deposit_amount);
    stop_cheat_caller_address(token_address);

    // Try to deposit to canceled stream - should panic
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.deposit(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_deposit_and_pause_successful() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 500_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Setup token approval for deposit
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, deposit_amount);
    stop_cheat_caller_address(token_address);

    // Deposit additional funds and pause
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.deposit_and_pause(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream amount was updated
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.total_amount == total_amount + deposit_amount, 'Deposit amount not added');

    // Verify that the stream is paused
    assert(stream.status == StreamStatus::Paused, 'Stream should be paused');
}

#[test]
#[should_panic(expected: 'Error: Amount must be > 0.')]
fn test_deposit_and_pause_zero_amount() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let total_amount = 1000_u256;
    let deposit_amount = 0_u256; // Zero amount should fail
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );

    // Try to deposit_and_pause with zero amount - should panic
    payment_stream.deposit_and_pause(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_deposit_by_non_sender() {
    // Setup
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<'recipient'>();
    let non_sender = contract_address_const::<'non_sender'>(); // Another account
    let total_amount = 1000_u256;
    let deposit_amount = 500_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    // Create stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Setup token approval for deposit by non-sender
    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, non_sender);
    token_dispatcher.approve(payment_stream.contract_address, deposit_amount);
    stop_cheat_caller_address(token_address);

    // Deposit additional funds from non-sender
    start_cheat_caller_address(payment_stream.contract_address, non_sender);
    payment_stream.deposit(stream_id, deposit_amount);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream amount was updated (anyone can deposit)
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.total_amount == total_amount + deposit_amount, 'Deposit amount not added');
}

#[test]
fn test_aggregate_balance_on_stream_creation() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the aggregated balance match the total amount of the first stream
    let token_balance = payment_stream.aggregate_balance(token_address);
    assert!(
        token_balance == total_amount,
        "Aggregated balance does not match the expected value after the first stream creation",
    );

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the aggregated balance match the sum of the two streams
    let token_balance = payment_stream.aggregate_balance(token_address);
    assert!(
        token_balance == (total_amount * 2),
        "Aggregated balance does not match the expected value after the second stream creation",
    );
}

#[test]
fn test_aggregate_balance_on_withdraw() {
    let (token_address, sender, payment_stream, _) = setup();
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
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    payment_stream.delegate_stream(stream_id, delegate);
    stop_cheat_caller_address(payment_stream.contract_address);

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    start_cheat_caller_address(token_address, delegate);
    token_dispatcher.approve(payment_stream.contract_address, total_amount);
    stop_cheat_caller_address(token_address);

    let allowance = token_dispatcher.allowance(delegate, payment_stream.contract_address);
    assert(allowance >= total_amount, 'Allowance not set correctly');

    let withdraw_amount: u256 = 100;
    start_cheat_caller_address(payment_stream.contract_address, delegate);
    payment_stream.withdraw(stream_id, withdraw_amount, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify that the withdraw amount has been deducted from the aggregated balance
    let token_balance = payment_stream.aggregate_balance(token_address);
    let expected_token_balance = total_amount - withdraw_amount;
    assert!(
        token_balance == expected_token_balance,
        "Aggregated balance does not match the expected value after withdrawal",
    );
}

#[test]
fn test_recover() {
    let (token_address, sender, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 10000_u256;
    let surplus = 10_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();

    let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(payment_stream.contract_address, total_amount + surplus);
    token_dispatcher.transfer(payment_stream.contract_address, total_amount + surplus);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, true,
        );
    stop_cheat_caller_address(payment_stream.contract_address);

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    let mut spy = spy_events();

    payment_stream.recover(token_address, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);

    assert!(token_dispatcher.balance_of(recipient) == surplus, "Invalid surplus amount received");

    let expected_event = PaymentStream::Event::Recover(
        PaymentStream::Recover { sender: payment_stream.contract_address, to: recipient, surplus },
    );
    spy.assert_emitted(@array![(payment_stream.contract_address, expected_event)]);
}

#[test]
#[should_panic]
fn test_recover_when_caller_not_admin() {
    let (token_address, _, payment_stream, _) = setup();
    let recipient = contract_address_const::<0x2>();

    start_cheat_caller_address(payment_stream.contract_address, recipient);
    payment_stream.recover(token_address, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic]
fn test_recover_when_nothing_to_recover() {
    let (token_address, _, payment_stream, _) = setup();
    let protocol_owner: ContractAddress = contract_address_const::<'protocol_owner'>();
    let recipient = contract_address_const::<0x2>();

    start_cheat_caller_address(payment_stream.contract_address, protocol_owner);
    payment_stream.recover(token_address, recipient);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
fn test_pause_and_restart_stream() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Create the stream
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Pause the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check stream is paused
    let is_paused = payment_stream.is_paused(stream_id);
    assert!(is_paused, "Stream not paused");

    // Set new rate
    let new_rate: UFixedPoint123x128 = 2_u64.into();

    // Restart the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart(stream_id, new_rate);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Check stream is active
    let is_active = payment_stream.is_stream_active(stream_id);
    assert!(is_active, "Stream not active after restart");

    // Check new rate
    let updated_rate = payment_stream.get_rate_per_second(stream_id);
    assert!(updated_rate == new_rate, "Rate not updated");
}

#[test]
fn test_restart_and_deposit() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Create the stream
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Pause the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify stream is paused
    let is_paused = payment_stream.is_paused(stream_id);
    assert!(is_paused, "Stream not paused");

    // Setup for restart and deposit
    let additional_amount = 500_u256;
    let new_rate: UFixedPoint123x128 = 2_u64.into();

    // Approve the Payment Stream contract to spend tokens
    let token = IERC20Dispatcher { contract_address: token_address };
    token.approve(payment_stream.contract_address, additional_amount);

    // Use restart_and_deposit to restart the stream and add funds
    start_cheat_caller_address(payment_stream.contract_address, sender);
    let success = payment_stream.restart_and_deposit(stream_id, new_rate, additional_amount);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Verify operation was successful
    assert!(success, "Restart and deposit failed");

    // Verify stream is active
    let is_active = payment_stream.is_stream_active(stream_id);
    assert!(is_active, "Stream not active after restart");

    // Verify rate was updated
    let updated_rate = payment_stream.get_rate_per_second(stream_id);
    assert!(updated_rate == new_rate, "Rate not updated");

    // Verify total amount was updated
    let stream = payment_stream.get_stream(stream_id);
    assert!(
        stream.total_amount == total_amount + additional_amount,
        "Total amount not updated correctly",
    );
}

#[test]
#[should_panic(expected: 'Stream is not paused')]
fn test_restart_and_deposit_active_stream() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Create the stream (active by default)
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Attempt to restart an already active stream
    let additional_amount = 500_u256;
    let new_rate: UFixedPoint123x128 = 2_u64.into();

    // Approve token spending
    let token = IERC20Dispatcher { contract_address: token_address };
    token.approve(payment_stream.contract_address, additional_amount);

    // This should fail because the stream is not paused
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart_and_deposit(stream_id, new_rate, additional_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Amount must be > 0')]
fn test_restart_and_deposit_zero_amount() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Create the stream
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Pause the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to restart with zero deposit amount
    let zero_amount = 0_u256;
    let new_rate: UFixedPoint123x128 = 2_u64.into();

    // This should fail because amount is zero
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart_and_deposit(stream_id, new_rate, zero_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}

#[test]
#[should_panic(expected: 'Error: Insufficient allowance')]
fn test_create_stream_with_deposit_insufficient_allowance() {
    let (token_address, _sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Try to create stream with deposit without approving tokens first
    // This should fail due to insufficient allowance
    payment_stream
        .create_stream_with_deposit(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );
}

#[test]
#[should_panic(expected: 'Error: Insufficient allowance')]
fn test_restart_and_deposit_insufficient_allowance() {
    let (token_address, sender, payment_stream, _erc721) = setup();
    let recipient = contract_address_const::<0x2>();
    let total_amount = 1000_u256;
    let start_time = 100_u64;
    let end_time = 200_u64;
    let cancelable = true;
    let transferable = true;

    // Create the stream
    let stream_id = payment_stream
        .create_stream(
            recipient, total_amount, start_time, end_time, cancelable, token_address, transferable,
        );

    // Pause the stream
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.pause(stream_id);
    stop_cheat_caller_address(payment_stream.contract_address);

    // Try to restart with deposit without approving tokens
    let additional_amount = 500_u256;
    let new_rate: UFixedPoint123x128 = 2_u64.into();

    // This should fail because of insufficient allowance
    start_cheat_caller_address(payment_stream.contract_address, sender);
    payment_stream.restart_and_deposit(stream_id, new_rate, additional_amount);
    stop_cheat_caller_address(payment_stream.contract_address);
}
