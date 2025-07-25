use core::num::traits::Zero;
use fundable::payment_stream::PaymentStream;
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, start_cheat_caller_address, stop_cheat_caller_address,
    start_cheat_block_timestamp, spy_events, EventSpyAssertionsTrait
};
use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
use fundable::base::types::{Stream, StreamStatus};
use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};
use core::serde::Serde;

// ============================================================================
// MALICIOUS CONTRACTS FOR REENTRANCY TESTING
// ============================================================================

/// Malicious ERC20 token that attempts reentrancy during transfers
#[starknet::interface]
pub trait IMaliciousERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer_from(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn total_supply(self: @TContractState) -> u256;
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn set_target_contract(ref self: TContractState, target: ContractAddress);
    fn set_attack_mode(ref self: TContractState, mode: u8);
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
}

#[starknet::contract]
pub mod MaliciousERC20 {
    use starknet::ContractAddress;
    use starknet::storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::get_caller_address;
    use core::num::traits::Zero;
    use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,
        target_contract: ContractAddress,
        attack_mode: u8, // 0: normal, 1: withdraw attack, 2: cancel attack, 3: transfer_stream attack
        attack_count: u8,
    }

    #[abi(embed_v0)]
    impl MaliciousERC20Impl of super::IMaliciousERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            let caller_balance = self.balances.read(caller);
            assert(caller_balance >= amount, 'Insufficient balance');
            
            self.balances.write(caller, caller_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);

            // REENTRANCY ATTACK: Attempt to call target contract during transfer
            self._attempt_reentrancy_attack();
            
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self.allowances.write((caller, spender), amount);
            true
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.allowances.read((owner, spender))
        }

        fn transfer_from(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            let allowed = self.allowances.read((sender, caller));
            assert(allowed >= amount, 'Insufficient allowance');
            
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');
            
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.allowances.write((sender, caller), allowed - amount);

            // REENTRANCY ATTACK: Attempt to call target contract during transfer
            self._attempt_reentrancy_attack();
            
            true
        }

        fn total_supply(self: @ContractState) -> u256 {
            self.total_supply.read()
        }

        fn name(self: @ContractState) -> felt252 {
            'MaliciousToken'
        }

        fn symbol(self: @ContractState) -> felt252 {
            'MAL'
        }

        fn decimals(self: @ContractState) -> u8 {
            18
        }

        fn set_target_contract(ref self: ContractState, target: ContractAddress) {
            self.target_contract.write(target);
        }

        fn set_attack_mode(ref self: ContractState, mode: u8) {
            self.attack_mode.write(mode);
            self.attack_count.write(0);
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _attempt_reentrancy_attack(ref self: ContractState) {
            let target = self.target_contract.read();
            if target.is_zero() {
                return;
            }

            let attack_mode = self.attack_mode.read();
            let attack_count = self.attack_count.read();

            // Prevent infinite recursion by limiting attacks
            if attack_count >= 3 {
                return;
            }
            self.attack_count.write(attack_count + 1);

            let payment_stream = IPaymentStreamDispatcher { contract_address: target };
            
            if attack_mode == 1 {
                // Attack withdraw function
                // Try to call withdraw again with fake parameters
                // This should fail due to reentrancy protection
                // Using dummy values - in a real attack these would be malicious
                let dummy_recipient: ContractAddress = 0x123.try_into().unwrap();
                payment_stream.withdraw(1, 100, dummy_recipient);
            } else if attack_mode == 2 {
                // Attack cancel function
                payment_stream.cancel(1);
            } else if attack_mode == 3 {
                // Attack transfer_stream function
                let dummy_recipient: ContractAddress = 0x456.try_into().unwrap();
                payment_stream.transfer_stream(1, dummy_recipient);
            }
        }
    }
}

/// Malicious recipient contract that attempts reentrancy
#[starknet::interface]
pub trait IMaliciousRecipient<TContractState> {
    fn set_target_contract(ref self: TContractState, target: ContractAddress);
    fn set_attack_mode(ref self: TContractState, mode: u8);
    fn perform_attack(ref self: TContractState, stream_id: u256);
}

#[starknet::contract]
pub mod MaliciousRecipient {
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::num::traits::Zero;
    use fundable::interfaces::IPaymentStream::{IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait};

    #[storage]
    struct Storage {
        target_contract: ContractAddress,
        attack_mode: u8,
        attack_count: u8,
    }

    #[abi(embed_v0)]
    impl MaliciousRecipientImpl of super::IMaliciousRecipient<ContractState> {
        fn set_target_contract(ref self: ContractState, target: ContractAddress) {
            self.target_contract.write(target);
        }

        fn set_attack_mode(ref self: ContractState, mode: u8) {
            self.attack_mode.write(mode);
            self.attack_count.write(0);
        }

        fn perform_attack(ref self: ContractState, stream_id: u256) {
            let target = self.target_contract.read();
            if target.is_zero() {
                return;
            }

            let attack_count = self.attack_count.read();
            if attack_count >= 2 {
                return;
            }
            self.attack_count.write(attack_count + 1);

            let payment_stream = IPaymentStreamDispatcher { contract_address: target };
            let attack_mode = self.attack_mode.read();

            if attack_mode == 1 {
                // Cross-function reentrancy: withdraw -> cancel
                payment_stream.cancel(stream_id);
            } else if attack_mode == 2 {
                // Cross-function reentrancy: withdraw -> transfer_stream
                let dummy_recipient: ContractAddress = 0x789.try_into().unwrap();
                payment_stream.transfer_stream(stream_id, dummy_recipient);
            }
        }
    }
}

// ============================================================================
// REENTRANCY ATTACK TESTS
// ============================================================================

fn setup_contracts() -> (ContractAddress, ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let protocol_owner: ContractAddress = 0x123.try_into().unwrap();
    let fee_collector: ContractAddress = 0x456.try_into().unwrap();
    let sender: ContractAddress = 0x789.try_into().unwrap();

    // Deploy PaymentStream contract with constructor arguments
    let payment_stream_class = declare("PaymentStream").unwrap();
    let mut payment_stream_constructor_calldata = array![];
    protocol_owner.serialize(ref payment_stream_constructor_calldata);
    500_u64.serialize(ref payment_stream_constructor_calldata); // 5% fee
    fee_collector.serialize(ref payment_stream_constructor_calldata);
    let (payment_stream_address, _) = payment_stream_class
        .contract_class()
        .deploy(@payment_stream_constructor_calldata)
        .unwrap();

    // Deploy MaliciousERC20 token
    let malicious_token_class = declare("MaliciousERC20").unwrap();
    let mut malicious_token_constructor_calldata = array![];
    let (malicious_token_address, _) = malicious_token_class
        .contract_class()
        .deploy(@malicious_token_constructor_calldata)
        .unwrap();

    // Deploy MaliciousRecipient contract
    let malicious_recipient_class = declare("MaliciousRecipient").unwrap();
    let mut malicious_recipient_constructor_calldata = array![];
    let (malicious_recipient_address, _) = malicious_recipient_class
        .contract_class()
        .deploy(@malicious_recipient_constructor_calldata)
        .unwrap();

    (payment_stream_address, malicious_token_address, malicious_recipient_address, sender, protocol_owner)
}

#[test]
fn test_direct_reentrancy_attack_on_withdraw() {
    let (payment_stream_address, malicious_token_address, _, sender, _) = setup_contracts();
    
    let payment_stream = IPaymentStreamDispatcher { contract_address: payment_stream_address };
    let malicious_token = IMaliciousERC20Dispatcher { contract_address: malicious_token_address };
    
    // Set up malicious token for attack
    malicious_token.set_target_contract(payment_stream_address);
    malicious_token.set_attack_mode(1); // withdraw attack mode
    
    // Mint tokens to sender
    malicious_token.mint(sender, 1000);
    
    // Create stream
    start_cheat_caller_address(payment_stream_address, sender);
    start_cheat_caller_address(malicious_token_address, sender);
    
    // Approve payment stream to spend tokens
    malicious_token.approve(payment_stream_address, 1000);
    
    let recipient: ContractAddress = 0xABC.try_into().unwrap();
    
    let stream_id = payment_stream.create_stream(
        recipient, 1000, 3600, true, malicious_token_address, true
    );
    
    stop_cheat_caller_address(payment_stream_address);
    stop_cheat_caller_address(malicious_token_address);
    
    // Fast forward time to allow withdrawal
    start_cheat_block_timestamp(payment_stream_address, get_block_timestamp() + 1800); // 30 minutes
    
    // Attempt withdrawal as recipient (this should be protected against reentrancy)
    start_cheat_caller_address(payment_stream_address, recipient);
    
    // The reentrancy attack should fail, but the legitimate withdrawal should succeed
    let (withdrawn, fee) = payment_stream.withdraw(stream_id, 500, recipient);
    
    // Verify the withdrawal succeeded normally despite the reentrancy attempt
    assert(withdrawn > 0, 'Withdrawal should succeed');
    assert(fee > 0, 'Fee should be collected');
    
    stop_cheat_caller_address(payment_stream_address);
}

#[test]
fn test_cross_function_reentrancy_attack() {
    let (payment_stream_address, malicious_token_address, malicious_recipient_address, sender, _) = setup_contracts();
    
    let payment_stream = IPaymentStreamDispatcher { contract_address: payment_stream_address };
    let malicious_token = IMaliciousERC20Dispatcher { contract_address: malicious_token_address };
    let malicious_recipient = IMaliciousRecipientDispatcher { contract_address: malicious_recipient_address };
    
    // Set up malicious contracts for cross-function attack
    malicious_recipient.set_target_contract(payment_stream_address);
    malicious_recipient.set_attack_mode(1); // withdraw -> cancel attack
    
    // Mint tokens to sender
    malicious_token.mint(sender, 1000);
    
    // Create stream with malicious recipient
    start_cheat_caller_address(payment_stream_address, sender);
    start_cheat_caller_address(malicious_token_address, sender);
    
    malicious_token.approve(payment_stream_address, 1000);
    
    let stream_id = payment_stream.create_stream(
        malicious_recipient_address, 1000, 3600, true, malicious_token_address, true
    );
    
    stop_cheat_caller_address(payment_stream_address);
    stop_cheat_caller_address(malicious_token_address);
    
    // Fast forward time
    start_cheat_block_timestamp(payment_stream_address, get_block_timestamp() + 1800);
    
    // Attempt cross-function reentrancy attack
    start_cheat_caller_address(payment_stream_address, malicious_recipient_address);
    
    // This should be protected against reentrancy
    malicious_recipient.perform_attack(stream_id);
    
    // Verify stream state is still consistent
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Active, 'Stream should still be active');
    
    stop_cheat_caller_address(payment_stream_address);
}

#[test]
fn test_reentrancy_protection_on_cancel() {
    let (payment_stream_address, malicious_token_address, _, sender, _) = setup_contracts();
    
    let payment_stream = IPaymentStreamDispatcher { contract_address: payment_stream_address };
    let malicious_token = IMaliciousERC20Dispatcher { contract_address: malicious_token_address };
    
    // Set up malicious token for cancel attack
    malicious_token.set_target_contract(payment_stream_address);
    malicious_token.set_attack_mode(2); // cancel attack mode
    
    // Mint tokens and create stream
    malicious_token.mint(sender, 1000);
    
    start_cheat_caller_address(payment_stream_address, sender);
    start_cheat_caller_address(malicious_token_address, sender);
    
    malicious_token.approve(payment_stream_address, 1000);
    
    let recipient: ContractAddress = 0xDEF.try_into().unwrap();
    
    let stream_id = payment_stream.create_stream(
        recipient, 1000, 3600, true, malicious_token_address, true
    );
    
    // Attempt to cancel (this should trigger reentrancy attack in the malicious token)
    // The reentrancy protection should prevent the nested call from succeeding
    payment_stream.cancel(stream_id);
    
    // Verify the stream was cancelled despite the reentrancy attempt
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.status == StreamStatus::Canceled, 'Stream should be canceled');
    
    stop_cheat_caller_address(payment_stream_address);
    stop_cheat_caller_address(malicious_token_address);
}

#[test]
fn test_reentrancy_protection_on_transfer_stream() {
    let (payment_stream_address, malicious_token_address, _, sender, _) = setup_contracts();
    
    let payment_stream = IPaymentStreamDispatcher { contract_address: payment_stream_address };
    let malicious_token = IMaliciousERC20Dispatcher { contract_address: malicious_token_address };
    
    // Set up malicious token for transfer_stream attack
    malicious_token.set_target_contract(payment_stream_address);
    malicious_token.set_attack_mode(3); // transfer_stream attack mode
    
    // Mint tokens and create stream
    malicious_token.mint(sender, 1000);
    
    start_cheat_caller_address(payment_stream_address, sender);
    start_cheat_caller_address(malicious_token_address, sender);
    
    malicious_token.approve(payment_stream_address, 1000);
    
    let recipient: ContractAddress = 0x111.try_into().unwrap();
    
    let stream_id = payment_stream.create_stream(
        recipient, 1000, 3600, true, malicious_token_address, true
    );
    
    stop_cheat_caller_address(payment_stream_address);
    stop_cheat_caller_address(malicious_token_address);
    
    // Attempt to transfer stream as recipient
    start_cheat_caller_address(payment_stream_address, recipient);
    
    let new_recipient: ContractAddress = 0x222.try_into().unwrap();
    
    // This should trigger reentrancy attack but be protected
    payment_stream.transfer_stream(stream_id, new_recipient);
    
    // Verify the transfer succeeded despite reentrancy attempt
    let stream = payment_stream.get_stream(stream_id);
    assert(stream.recipient == new_recipient, 'Stream should be transferred');
    
    stop_cheat_caller_address(payment_stream_address);
}

#[test]
fn test_multiple_function_reentrancy_protection() {
    let (payment_stream_address, malicious_token_address, _, sender, _) = setup_contracts();
    
    let payment_stream = IPaymentStreamDispatcher { contract_address: payment_stream_address };
    let malicious_token = IMaliciousERC20Dispatcher { contract_address: malicious_token_address };
    
    // Test that all protected functions are properly guarded
    malicious_token.set_target_contract(payment_stream_address);
    malicious_token.mint(sender, 2000);
    
    start_cheat_caller_address(payment_stream_address, sender);
    start_cheat_caller_address(malicious_token_address, sender);
    
    malicious_token.approve(payment_stream_address, 2000);
    
    let recipient: ContractAddress = 0x333.try_into().unwrap();
    
    // Create multiple streams to test different functions
    let stream_id_1 = payment_stream.create_stream(
        recipient, 500, 3600, true, malicious_token_address, true
    );
    let stream_id_2 = payment_stream.create_stream(
        recipient, 500, 3600, true, malicious_token_address, true
    );
    
    stop_cheat_caller_address(payment_stream_address);
    stop_cheat_caller_address(malicious_token_address);
    
    // Fast forward time
    start_cheat_block_timestamp(payment_stream_address, get_block_timestamp() + 1800);
    
    // Test withdraw protection
    start_cheat_caller_address(payment_stream_address, recipient);
    malicious_token.set_attack_mode(1);
    let (withdrawn, _) = payment_stream.withdraw(stream_id_1, 100, recipient);
    assert(withdrawn > 0, 'Withdraw works despite attack');
    stop_cheat_caller_address(payment_stream_address);
    
    // Test cancel protection
    start_cheat_caller_address(payment_stream_address, sender);
    malicious_token.set_attack_mode(2);
    payment_stream.cancel(stream_id_2);
    let stream = payment_stream.get_stream(stream_id_2);
    assert(stream.status == StreamStatus::Canceled, 'Cancel works despite attack');
    stop_cheat_caller_address(payment_stream_address);
} 