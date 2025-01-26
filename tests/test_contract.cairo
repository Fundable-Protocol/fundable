use core::traits::Into;
use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_caller_address_global, stop_cheat_caller_address_global
};
use fundable::interfaces::IDistributor::{IDistributorDispatcher, IDistributorDispatcherTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

fn setup() -> (ContractAddress, ContractAddress, IDistributorDispatcher) {
    let sender: ContractAddress = contract_address_const::<'sender'>();
    // Deploy mock ERC20
    let erc20_class = declare("MockUsdc").unwrap().contract_class();
    let mut calldata = array![sender.into(), sender.into(),];
    let (erc20_address, _) = erc20_class.deploy(@calldata).unwrap();

    // Deploy distributor contract
    let distributor_class = declare("Distributor").unwrap().contract_class();
    let (distributor_address, _) = distributor_class.deploy(@array![]).unwrap();

    (erc20_address, sender, IDistributorDispatcher { contract_address: distributor_address })
}

#[test]
fn test_successful_distribution() {
    let (token_address, sender, distributor) = setup();
    let token = IERC20Dispatcher { contract_address: token_address };

    // Create recipients array
    let mut recipients = array![
        contract_address_const::<0x2>(),
        contract_address_const::<0x3>(),
        contract_address_const::<0x4>()
    ];

    let amount_per_recipient = 100_u256;

    let sender_balance_before = token.balance_of(sender);
    println!("Sender balance is {}", sender_balance_before);

    // Approve tokens for distributor
    start_cheat_caller_address(token_address, sender);
    token.approve(distributor.contract_address, amount_per_recipient * 3 + amount_per_recipient);
    println!(
        "Approved tokens for distributor: {}", token.allowance(sender, distributor.contract_address)
    );
    stop_cheat_caller_address(token_address);

    // Distribute tokens
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(amount_per_recipient, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances
    assert(
        token.balance_of(contract_address_const::<0x2>()) == amount_per_recipient,
        'Wrong balance recipient 1'
    );
    assert(
        token.balance_of(contract_address_const::<0x3>()) == amount_per_recipient,
        'Wrong balance recipient 2'
    );
    assert(
        token.balance_of(contract_address_const::<0x4>()) == amount_per_recipient,
        'Wrong balance recipient 3'
    );
}

#[test]
#[should_panic(expected: ('Recipients array is empty',))]
fn test_empty_recipients() {
    let (token_address, sender, distributor) = setup();
    let recipients = array![];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute(100_u256, recipients, token_address);
    stop_cheat_caller_address(sender);
}

#[test]
#[should_panic(expected: ('Amount must be greater than 0',))]
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
        contract_address_const::<0x4>()
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
        "Approved tokens for distributor: {}", token.allowance(sender, distributor.contract_address)
    );
    stop_cheat_caller_address(token_address);

    // Distribute tokens with weighted amounts
    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);

    // Assert balances for each recipient
    assert(
        token.balance_of(contract_address_const::<0x2>()) == 100_u256, 'Wrong balance recipient 1'
    );
    assert(
        token.balance_of(contract_address_const::<0x3>()) == 200_u256, 'Wrong balance recipient 2'
    );
    assert(
        token.balance_of(contract_address_const::<0x4>()) == 300_u256, 'Wrong balance recipient 3'
    );
}

#[test]
#[should_panic(expected: ('Arrays length mismatch',))]
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
#[should_panic(expected: ('Amount must be greater than 0',))]
fn test_weighted_distribution_zero_amount() {
    let (token_address, sender, distributor) = setup();

    let recipients = array![contract_address_const::<0x2>()];
    let amounts = array![0_u256];

    start_cheat_caller_address(distributor.contract_address, sender);
    distributor.distribute_weighted(amounts, recipients, token_address);
    stop_cheat_caller_address(distributor.contract_address);
}
// #[test]
// fn test_weighted_distribution_events() {
//     // Setup
//     let (token_address, sender, distributor) = setup();
//     let token = IERC20Dispatcher { contract_address: token_address };

//     // Create test data
//     let recipients = array![
//         contract_address_const::<0x2>(),
//         contract_address_const::<0x3>()
//     ];
//     let amounts = array![100_u256, 200_u256];
//     let total_amount = 300_u256;

//     // Start spying on events
//     let mut spy = spy_events(SpyOn::One(distributor.contract_address));

//     // Setup and execute distribution
//     start_cheat_caller_address(token_address, sender);
//     token.approve(distributor.contract_address, total_amount);
//     stop_cheat_caller_address(token_address);

//     start_cheat_caller_address(distributor.contract_address, sender);
//     distributor.distribute_weighted(amounts, recipients, token_address);
//     stop_cheat_caller_address(distributor.contract_address);

//     // Assert events using assert_emitted
//     spy.assert_emitted(@array![
//         (
//             distributor.contract_address,
//             WeightedDistribution {
//                 recipient: contract_address_const::<0x2>(),
//                 amount: 100_u256
//             }
//         ),
//         (
//             distributor.contract_address,
//             WeightedDistribution {
//                 recipient: contract_address_const::<0x3>(),
//                 amount: 200_u256
//             }
//         )
//     ]);
// }

// #[test]
// fn test_weighted_distribution_manual_event_check() {
//     // Setup
//     let (token_address, sender, distributor) = setup();
//     let token = IERC20Dispatcher { contract_address: token_address };

//     // Create test data
//     let recipients = array![contract_address_const::<0x2>()];
//     let amounts = array![100_u256];

//     // Start spying on events
//     let mut spy = spy_events(SpyOn::One(distributor.contract_address));

//     // Setup and execute distribution
//     start_cheat_caller_address(token_address, sender);
//     token.approve(distributor.contract_address, 100_u256);
//     stop_cheat_caller_address(token_address);

//     start_cheat_caller_address(distributor.contract_address, sender);
//     distributor.distribute_weighted(amounts, recipients, token_address);
//     stop_cheat_caller_address(distributor.contract_address);

//     // Get and manually check events
//     let events = spy.get_events().unwrap();
//     assert(events.len() == 1, 'Wrong number of events');

//     let (emitter, event) = events.at(0);
//     assert(emitter == distributor.contract_address, 'Wrong event emitter');
//     assert(event.keys.at(0) == selector!("WeightedDistribution"), 'Wrong event name');
//     assert(event.data.at(0) == contract_address_const::<0x2>(), 'Wrong recipient');
//     assert(event.data.at(1) == 100_u256, 'Wrong amount');
// }

// #[test]
// fn test_no_events_on_invalid_input() {
//     // Setup
//     let (token_address, sender, distributor) = setup();

//     // Create invalid test data (empty arrays)
//     let recipients = array![];
//     let amounts = array![];

//     // Start spying on events
//     let mut spy = spy_events(SpyOn::One(distributor.contract_address));

//     // Attempt distribution (should fail)
//     start_cheat_caller_address(distributor.contract_address, sender);
//     match distributor.distribute_weighted(amounts, recipients, token_address) {
//         Result::Ok(_) => panic_with_felt252('Should fail with empty arrays'),
//         Result::Err(_) => (),
//     };
//     stop_cheat_caller_address(distributor.contract_address);

//     // Verify no events were emitted
//     let events = spy.get_events().unwrap();
//     assert(events.is_empty(), 'Should not emit events');
// }

// #[test]
// fn test_weighted_distribution_zero_total_supply() {
//     let (token_address, sender, distributor) = setup();
//     let token = IERC20Dispatcher { contract_address: token_address };

//     // Create test data with zero total supply
//     let recipients = array![contract_address_const::<0x2>()];
//     let amounts = array![0_u256];

//     // Spy on events
//     let mut spy = spy_events(distributor.contract_address);

//     // Should not emit any events since it will fail validation
//     start_cheat_caller_address(distributor.contract_address, sender);
//     let result = try_distribute_weighted(distributor, amounts, recipients, token_address);
//     stop_cheat_caller_address(distributor.contract_address);

//     assert(result.is_err(), 'Should fail with zero amount');

//     // Verify no events were emitted
//     let events = spy.get_events().unwrap();
//     assert(events.is_empty(), 'Should not emit events');
// }


