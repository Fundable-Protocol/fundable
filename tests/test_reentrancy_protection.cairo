use fundable::base::types::{Stream, StreamStatus};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use fundable::payment_stream::PaymentStream;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::storage::*;
use starknet::{ContractAddress, get_caller_address};

#[starknet::interface]
pub trait IMaliciousERC20<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TContractState, to: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256,
    ) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn decimals(self: @TContractState) -> u8;
    fn set_attack_mode(ref self: TContractState, mode: u8);
    fn set_stream_id(ref self: TContractState, stream_id: u256);
    fn set_target(ref self: TContractState, target: ContractAddress);
}

#[starknet::contract]
pub mod MaliciousERC20 {
    use fundable::interfaces::IPaymentStream::{
        IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait,
    };
    use starknet::storage::*;
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,
        name: ByteArray,
        symbol: ByteArray,
        decimals: u8,
        attack_mode: u8, // 0: no attack, 1: withdraw attack, 2: cancel attack, 3: transfer attack
        stream_id: u256,
        target_contract: ContractAddress,
        attack_count: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, name: ByteArray, symbol: ByteArray, decimals: u8) {
        self.name.write(name);
        self.symbol.write(symbol);
        self.decimals.write(decimals);
        self.attack_mode.write(0);
    }

    #[abi(embed_v0)]
    impl MaliciousERC20Impl of super::IMaliciousERC20<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            let current_balance = self.balances.read(to);
            self.balances.write(to, current_balance + amount);
            let current_supply = self.total_supply.read();
            self.total_supply.write(current_supply + amount);
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.allowances.write((caller, spender), amount);
            true
        }

        fn transfer(ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            let from_balance = self.balances.read(caller);
            assert(from_balance >= amount, 'Insufficient balance');

            self.balances.write(caller, from_balance - amount);
            let to_balance = self.balances.read(to);
            self.balances.write(to, to_balance + amount);

            // Attempt reentrancy attack during transfer
            self._attempt_reentrancy_attack();

            true
        }

        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256,
        ) -> bool {
            let caller = get_caller_address();
            let allowance = self.allowances.read((from, caller));
            assert(allowance >= amount, 'Insufficient allowance');

            let from_balance = self.balances.read(from);
            assert(from_balance >= amount, 'Insufficient balance');

            self.allowances.write((from, caller), allowance - amount);
            self.balances.write(from, from_balance - amount);
            let to_balance = self.balances.read(to);
            self.balances.write(to, to_balance + amount);

            // Attempt reentrancy attack during transfer_from
            self._attempt_reentrancy_attack();

            true
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn name(self: @ContractState) -> ByteArray {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.decimals.read()
        }

        fn set_attack_mode(ref self: ContractState, mode: u8) {
            self.attack_mode.write(mode);
        }

        fn set_stream_id(ref self: ContractState, stream_id: u256) {
            self.stream_id.write(stream_id);
        }

        fn set_target(ref self: ContractState, target: ContractAddress) {
            self.target_contract.write(target);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _attempt_reentrancy_attack(ref self: ContractState) {
            let attack_mode = self.attack_mode.read();
            let attack_count = self.attack_count.read();

            if attack_mode == 0 || attack_count >= 3 {
                return;
            }

            let target = self.target_contract.read();
            let stream_id = self.stream_id.read();

            if target.into() == 0 {
                return;
            }

            self.attack_count.write(attack_count + 1);
            let dispatcher = IPaymentStreamDispatcher { contract_address: target };

            if attack_mode == 1 {
                // Withdraw attack
                dispatcher.withdraw(stream_id, 50_u256, starknet::get_contract_address());
            } else if attack_mode == 2 {
                // Cancel attack
                dispatcher.cancel(stream_id);
            } else if attack_mode == 3 {
                // Transfer stream attack
                let new_recipient: ContractAddress = 9999.try_into().unwrap();
                dispatcher.transfer_stream(stream_id, new_recipient);
            }
        }
    }
}

/// @notice Malicious contract that attempts reentrancy on withdraw function
#[starknet::interface]
pub trait IMaliciousWithdrawAttacker<TContractState> {
    fn set_target(ref self: TContractState, target: ContractAddress, stream_id: u256);
    fn start_attack(ref self: TContractState);
    fn get_attack_count(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod MaliciousWithdrawAttacker {
    use fundable::interfaces::IPaymentStream::{
        IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait,
    };
    use starknet::ContractAddress;
    use starknet::storage::*;

    #[storage]
    pub struct Storage {
        target_contract: ContractAddress,
        stream_id: u256,
        attack_count: u32,
        max_attacks: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.max_attacks.write(3); // Limit attacks to prevent infinite loops
    }

    #[abi(embed_v0)]
    impl MaliciousWithdrawAttackerImpl of super::IMaliciousWithdrawAttacker<ContractState> {
        fn set_target(ref self: ContractState, target: ContractAddress, stream_id: u256) {
            self.target_contract.write(target);
            self.stream_id.write(stream_id);
        }

        fn start_attack(ref self: ContractState) {
            let target = self.target_contract.read();
            let stream_id = self.stream_id.read();
            let dispatcher = IPaymentStreamDispatcher { contract_address: target };

            // Attempt initial withdrawal
            dispatcher.withdraw(stream_id, 100_u256, starknet::get_contract_address());
        }

        fn get_attack_count(self: @ContractState) -> u32 {
            self.attack_count.read()
        }
    }
}

/// @notice Malicious contract that attempts reentrancy on cancel function
#[starknet::interface]
pub trait IMaliciousCancelAttacker<TContractState> {
    fn set_target(ref self: TContractState, target: ContractAddress, stream_id: u256);
    fn start_attack(ref self: TContractState);
    fn get_attack_count(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod MaliciousCancelAttacker {
    use fundable::interfaces::IPaymentStream::{
        IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait,
    };
    use starknet::ContractAddress;
    use starknet::storage::*;

    #[storage]
    pub struct Storage {
        target_contract: ContractAddress,
        stream_id: u256,
        attack_count: u32,
        max_attacks: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.max_attacks.write(2);
    }

    #[abi(embed_v0)]
    impl MaliciousCancelAttackerImpl of super::IMaliciousCancelAttacker<ContractState> {
        fn set_target(ref self: ContractState, target: ContractAddress, stream_id: u256) {
            self.target_contract.write(target);
            self.stream_id.write(stream_id);
        }

        fn start_attack(ref self: ContractState) {
            let target = self.target_contract.read();
            let stream_id = self.stream_id.read();
            let dispatcher = IPaymentStreamDispatcher { contract_address: target };

            // Attempt to cancel stream
            dispatcher.cancel(stream_id);
        }

        fn get_attack_count(self: @ContractState) -> u32 {
            self.attack_count.read()
        }
    }
}

/// @notice Malicious contract that attempts reentrancy on transfer_stream function
#[starknet::interface]
pub trait IMaliciousTransferAttacker<TContractState> {
    fn set_target(ref self: TContractState, target: ContractAddress, stream_id: u256);
    fn start_attack(ref self: TContractState, new_recipient: ContractAddress);
    fn get_attack_count(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod MaliciousTransferAttacker {
    use fundable::interfaces::IPaymentStream::{
        IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait,
    };
    use starknet::ContractAddress;
    use starknet::storage::*;

    #[storage]
    pub struct Storage {
        target_contract: ContractAddress,
        stream_id: u256,
        attack_count: u32,
        max_attacks: u32,
        new_recipient: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.max_attacks.write(2);
    }

    #[abi(embed_v0)]
    impl MaliciousTransferAttackerImpl of super::IMaliciousTransferAttacker<ContractState> {
        fn set_target(ref self: ContractState, target: ContractAddress, stream_id: u256) {
            self.target_contract.write(target);
            self.stream_id.write(stream_id);
        }

        fn start_attack(ref self: ContractState, new_recipient: ContractAddress) {
            self.new_recipient.write(new_recipient);
            let target = self.target_contract.read();
            let stream_id = self.stream_id.read();
            let dispatcher = IPaymentStreamDispatcher { contract_address: target };

            // Attempt to transfer stream
            dispatcher.transfer_stream(stream_id, new_recipient);
        }

        fn get_attack_count(self: @ContractState) -> u32 {
            self.attack_count.read()
        }
    }
}


// Helper function to deploy malicious ERC20 token
fn deploy_malicious_token() -> ContractAddress {
    let contract = declare("MaliciousERC20").unwrap().contract_class();
    let mut constructor_args = array![];
    let name: ByteArray = "Malicious Token";
    let symbol: ByteArray = "MAL";
    let decimals: u8 = 18;

    name.serialize(ref constructor_args);
    symbol.serialize(ref constructor_args);
    decimals.serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// Helper function to deploy payment stream contract
fn deploy_payment_stream() -> ContractAddress {
    let contract = declare("PaymentStream").unwrap().contract_class();
    let mut constructor_args = array![];

    let protocol_owner: ContractAddress = 123.try_into().unwrap();
    let fee_collector: ContractAddress = 456.try_into().unwrap();
    let general_fee_rate: u64 = 250; // 2.5%

    protocol_owner.serialize(ref constructor_args);
    fee_collector.serialize(ref constructor_args);
    general_fee_rate.serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// Helper function to deploy malicious withdraw attacker
fn deploy_malicious_withdraw_attacker() -> ContractAddress {
    let contract = declare("MaliciousWithdrawAttacker").unwrap().contract_class();
    let constructor_args = array![];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// Helper function to deploy malicious cancel attacker
fn deploy_malicious_cancel_attacker() -> ContractAddress {
    let contract = declare("MaliciousCancelAttacker").unwrap().contract_class();
    let constructor_args = array![];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// Helper function to deploy malicious transfer attacker
fn deploy_malicious_transfer_attacker() -> ContractAddress {
    let contract = declare("MaliciousTransferAttacker").unwrap().contract_class();
    let constructor_args = array![];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// Helper functions to generate contract addresses
fn get_sender_address() -> ContractAddress {
    'WHEVAL'.try_into().unwrap()
}

fn get_recipient_address() -> ContractAddress {
    'BOB'.try_into().unwrap()
}

fn get_new_recipient_address() -> ContractAddress {
    'KANYE'.try_into().unwrap()
}

fn get_alt_sender_address() -> ContractAddress {
    'MARY'.try_into().unwrap()
}

fn get_alt_recipient_address() -> ContractAddress {
    'BEN'.try_into().unwrap()
}

fn get_alt_new_recipient_address() -> ContractAddress {
    'WEST'.try_into().unwrap()
}


#[test]
#[should_panic(expected: ('ReentrancyGuard: reentrant call',))]
fn test_reentrancy_protection_on_withdraw() {
    let token_address = deploy_malicious_token();
    let stream_address = deploy_payment_stream();

    let token_dispatcher = IMaliciousERC20Dispatcher { contract_address: token_address };
    let stream_dispatcher = IPaymentStreamDispatcher { contract_address: stream_address };

    let sender = get_sender_address();
    let recipient = get_recipient_address();

    token_dispatcher.mint(sender, 100000_u256); // Increase amount

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(stream_address, 100000_u256);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(stream_address, sender);
    start_cheat_block_timestamp(stream_address, 1000);

    let stream_id = stream_dispatcher
        .create_stream(
            recipient,
            10000_u256, // total_amount - increased
            10, // duration (10 hours) - increased
            true, // cancelable
            token_address,
            true // transferable
        );

    stop_cheat_caller_address(stream_address);

    token_dispatcher.set_attack_mode(1); // withdraw attack
    token_dispatcher.set_stream_id(stream_id);
    token_dispatcher.set_target(stream_address);

    // Move time forward significantly to ensure withdrawable amount (5 hours = 18000 seconds)
    start_cheat_block_timestamp(stream_address, 19000); // 1000 + 18000

    // Attempt withdrawal - should trigger reentrancy and fail
    start_cheat_caller_address(stream_address, recipient);
    stream_dispatcher.withdraw(stream_id, 100, recipient);
    stop_cheat_caller_address(stream_address);
}

#[test]
#[should_panic(expected: ('ReentrancyGuard: reentrant call',))]
fn test_reentrancy_protection_on_cancel() {
    let token_address = deploy_malicious_token();
    let stream_address = deploy_payment_stream();

    let token_dispatcher = IMaliciousERC20Dispatcher { contract_address: token_address };
    let stream_dispatcher = IPaymentStreamDispatcher { contract_address: stream_address };

    let sender = get_sender_address();
    let recipient = get_recipient_address();

    token_dispatcher.mint(sender, 100000_u256);

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(stream_address, 100000_u256);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(stream_address, sender);
    start_cheat_block_timestamp(stream_address, 1000);

    let stream_id = stream_dispatcher
        .create_stream(
            recipient,
            10000_u256, // total_amount
            10, // duration (10 hours)
            true, // cancelable
            token_address,
            true // transferable
        );

    stop_cheat_caller_address(stream_address);

    token_dispatcher.set_attack_mode(2); // cancel attack
    token_dispatcher.set_stream_id(stream_id);
    token_dispatcher.set_target(stream_address);

    // Attempt cancellation - should trigger reentrancy and fail
    start_cheat_caller_address(stream_address, sender);
    stream_dispatcher.cancel(stream_id);
    stop_cheat_caller_address(stream_address);
}

#[test]
#[should_panic(expected: ('ReentrancyGuard: reentrant call',))]
fn test_reentrancy_protection_on_transfer_stream() {
    let token_address = deploy_malicious_token();
    let stream_address = deploy_payment_stream();

    let token_dispatcher = IMaliciousERC20Dispatcher { contract_address: token_address };
    let stream_dispatcher = IPaymentStreamDispatcher { contract_address: stream_address };

    let sender = get_sender_address();
    let recipient = get_recipient_address();
    let new_recipient = get_new_recipient_address();

    token_dispatcher.mint(sender, 100000_u256);

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(stream_address, 100000_u256);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(stream_address, sender);
    start_cheat_block_timestamp(stream_address, 1000);

    let stream_id = stream_dispatcher
        .create_stream(
            recipient,
            10000_u256, // total_amount
            10, // duration (10 hours)
            true, // cancelable
            token_address,
            true // transferable
        );

    stop_cheat_caller_address(stream_address);

    token_dispatcher.set_attack_mode(3); // transfer_stream attack
    token_dispatcher.set_stream_id(stream_id);
    token_dispatcher.set_target(stream_address);

    start_cheat_block_timestamp(stream_address, 19000);

    start_cheat_caller_address(stream_address, recipient);
    stream_dispatcher
        .withdraw(
            stream_id, 100, recipient,
        ); // This will trigger malicious token's transfer_stream attack
    stop_cheat_caller_address(stream_address);
}

#[test]
fn test_reentrancy_protection_on_withdraw_max() {
    let token_address = deploy_malicious_token();
    let stream_address = deploy_payment_stream();

    let token_dispatcher = IMaliciousERC20Dispatcher { contract_address: token_address };
    let stream_dispatcher = IPaymentStreamDispatcher { contract_address: stream_address };

    let sender = get_sender_address();
    let recipient = get_recipient_address();

    token_dispatcher.mint(sender, 100000_u256);

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(stream_address, 100000_u256);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(stream_address, sender);
    start_cheat_block_timestamp(stream_address, 1000);

    let stream_id = stream_dispatcher
        .create_stream(
            recipient,
            10000_u256, // total_amount
            10, // duration (10 hours)
            true, // cancelable
            token_address,
            true // transferable
        );

    stop_cheat_caller_address(stream_address);

    start_cheat_block_timestamp(stream_address, 19000); // 1000 + 18000 (5 hours)

    // Test withdraw_max with reentrancy protection
    start_cheat_caller_address(stream_address, recipient);
    let (_withdrawn_amount, _fee) = stream_dispatcher.withdraw_max(stream_id, recipient);
    stop_cheat_caller_address(stream_address);

    // Should succeed without issues since no attack
    let stream = stream_dispatcher.get_stream(stream_id);
    assert(stream.status == StreamStatus::Active, 'Stream should still be active');
}

#[test]
fn test_successful_operations_after_reentrancy_protection() {
    let token_address = deploy_malicious_token();
    let stream_address = deploy_payment_stream();

    let token_dispatcher = IMaliciousERC20Dispatcher { contract_address: token_address };
    let stream_dispatcher = IPaymentStreamDispatcher { contract_address: stream_address };

    // Setup normal accounts (not malicious contracts)
    let sender = get_alt_sender_address();
    let recipient = get_alt_recipient_address();

    token_dispatcher.mint(sender, 100000_u256);

    start_cheat_caller_address(token_address, sender);
    token_dispatcher.approve(stream_address, 100000_u256);
    stop_cheat_caller_address(token_address);

    start_cheat_caller_address(stream_address, sender);
    start_cheat_block_timestamp(stream_address, 1000);

    let stream_id = stream_dispatcher
        .create_stream(
            recipient,
            10000_u256, // total_amount
            10, // duration (10 hours)
            true, // cancelable
            token_address,
            true // transferable
        );

    stop_cheat_caller_address(stream_address);

    start_cheat_block_timestamp(stream_address, 19000); // 1000 + 18000 (5 hours)

    start_cheat_caller_address(stream_address, recipient);
    let (withdrawn_amount, _fee) = stream_dispatcher.withdraw(stream_id, 100_u256, recipient);
    assert(withdrawn_amount > 0, 'Normal withdrawal should work');
    stop_cheat_caller_address(stream_address);

    // Test normal stream transfer (should work)
    let new_recipient = get_alt_new_recipient_address();
    start_cheat_caller_address(stream_address, recipient);
    stream_dispatcher.transfer_stream(stream_id, new_recipient);
    stop_cheat_caller_address(stream_address);

    let updated_stream = stream_dispatcher.get_stream(stream_id);
    assert(updated_stream.recipient == new_recipient, 'Transfer should work');

    // Test normal cancellation (should work)
    start_cheat_caller_address(stream_address, sender);
    stream_dispatcher.cancel(stream_id);
    stop_cheat_caller_address(stream_address);

    let cancelled_stream = stream_dispatcher.get_stream(stream_id);
    assert(cancelled_stream.status == StreamStatus::Canceled, 'Cancel should work');
}

