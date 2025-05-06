/// Main contract implementation
#[starknet::contract]
mod DirectDeposit {
    use core::num::traits::Zero;
    use core::traits::Into;
    use fundable::interfaces::IDirectDeposit::IDirectDeposit;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::Map;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::base::types::{DirectDeposit, DirectDepositHistory, DirectDepositPayment, Recipient};
    use crate::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        direct_deposit_count: u256,
        direct_deposits: Map<u256, DirectDeposit>, // deposist_id, DirectDeposit,
        direct_deposit_payment_count: u256,
        direct_deposit_payments: Map<
            (ContractAddress, u256), DirectDepositPayment,
        >, // map<(direct_owner, deiect_deposist_id), DirectDepositPayment> 
        direct_deposit_history: Map<u256, DirectDepositHistory>,
        total_direct_deposit_payment: u256,
        total_direct_deposit_payment_amount: u256,
        protocol_fee_percent: u256,
        protocol_fee_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }
}
