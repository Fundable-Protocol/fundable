/// Main contract implementation
#[starknet::contract]
mod Distributor {
    use core::num::traits::Zero;
    use core::traits::Into;
    use fundable::interfaces::IDistributor::IDistributor;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::Map;
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    //  use super::Errors;
    use crate::base::errors::Errors::{
        ARRAY_LEN_MISMATCH, EMPTY_RECIPIENTS, INSUFFICIENT_ALLOWANCE, INVALID_TOKEN,
        PROTOCOL_FEE_ADDRESS_NOT_SET, ZERO_AMOUNT,
    };
    use crate::base::types::{
        Distribution, DistributionHistory, TokenStats, UserStats, WeightedDistribution,
    };
    use crate::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        balance: u256, // 2 slots
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        total_distributions: u256,
        total_distributed_amount: u256,
        token_stats: Map<ContractAddress, TokenStats>,
        user_stats: Map<ContractAddress, UserStats>,
        distribution_history: Map<u256, DistributionHistory>,
        distribution_count: u256,
        /// Protocol fee percentage using 10000 basis points (e.g. 250 = 2.5%). Default is 0.
        protocol_fee_percent: u256,
        protocol_fee_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Distribution: Distribution,
        WeightedDistribution: WeightedDistribution,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, protocol_fee_address: ContractAddress, owner: ContractAddress,
    ) {
        self.protocol_fee_address.write(protocol_fee_address);
        self.ownable.initializer(owner);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn update_global_stats(ref self: ContractState, total_amount: u256) {
            let current_total_distributions = self.total_distributions.read();
            self.total_distributions.write(current_total_distributions + 1);

            let current_total_distributed_amount = self.total_distributed_amount.read();
            self.total_distributed_amount.write(current_total_distributed_amount + total_amount);
        }

        fn update_token_stats(ref self: ContractState, token: ContractAddress, amount: u256) {
            let mut stats = self.token_stats.read(token);
            stats.total_amount += amount;
            stats.distribution_count += 1;
            stats.last_distribution_time = get_block_timestamp();

            self.token_stats.write(token, stats);
        }

        fn update_user_stats(
            ref self: ContractState,
            user: ContractAddress,
            total_amount: u256,
            token: ContractAddress,
        ) {
            let mut stats = self.user_stats.read(user);
            stats.distributions_initiated += 1;
            stats.total_amount_distributed += total_amount;
            stats.unique_tokens_used += 1;
            stats.last_distribution_time = get_block_timestamp();
            self.user_stats.write(user, stats);
        }

        fn record_distribution(ref self: ContractState, distribution: DistributionHistory) {
            let current_count = self.distribution_count.read();
            let current_count = if current_count == 0.into() {
                0.into()
            } else {
                current_count
            };

            self.distribution_history.write(current_count, distribution);
            self.distribution_count.write(current_count + 1);
        }

        fn calculate_protocol_fee(self: @ContractState, total_amount: @u256) -> u256 {
            let fee_percent = self.protocol_fee_percent.read();
            let protocol_fee = (*total_amount * fee_percent) / 10000;
            protocol_fee
        }

        fn validate_token(self: @ContractState, token: ContractAddress) {
            assert(!token.is_zero(), INVALID_TOKEN);
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let token_decimals = token_dispatcher.decimals();
            assert(token_decimals > 0, 'INVALID_TOKEN_DECIMALS');
        }
    }

    #[abi(embed_v0)]
    impl DistributorImpl of IDistributor<ContractState> {
        fn distribute(
            ref self: ContractState,
            amount: u256,
            recipients: Array<ContractAddress>,
            token: ContractAddress,
            unique_ref: felt252,
        ) {
            // Validate inputs
            assert(!recipients.is_empty(), EMPTY_RECIPIENTS);
            assert(amount > 0, ZERO_AMOUNT);
            self.validate_token(token);

            // Initialize the dispatcher
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let caller = get_caller_address();
            let timestamp: u64 = get_block_timestamp();

            // Calculate total amount and check allowance
            let amount_to_distribute = amount * recipients.len().into();
            let protocol_fee = self.calculate_protocol_fee(@amount_to_distribute);
            let total_amount = amount_to_distribute + protocol_fee;
            let allowance = token_dispatcher.allowance(caller, get_contract_address());
            assert(allowance >= total_amount, INSUFFICIENT_ALLOWANCE);

            // transfer protocol fee
            if protocol_fee > 0 {
                let protocol_address = self.protocol_fee_address.read();
                assert(!protocol_address.is_zero(), PROTOCOL_FEE_ADDRESS_NOT_SET);
                token_dispatcher.transfer_from(caller, protocol_address, protocol_fee);
            }

            // Perform distribution
            let recipients_list = recipients.span();
            for recipient in recipients.clone() {
                token_dispatcher.transfer_from(caller, recipient, amount);
                self.emit(WeightedDistribution { caller, token, recipient, amount, unique_ref });
            }

            // Update global statistics
            self.update_global_stats(amount_to_distribute);
            self.update_token_stats(token, amount_to_distribute);
            self.update_user_stats(caller, amount_to_distribute, token);

            // Record distribution history
            self
                .record_distribution(
                    DistributionHistory {
                        caller,
                        token,
                        amount: amount_to_distribute,
                        recipients_count: recipients_list.len(),
                        unique_ref,
                        timestamp,
                    },
                );

            // Emit summary event
            self
                .emit(
                    Event::Distribution(
                        Distribution {
                            caller,
                            token,
                            amount: amount_to_distribute,
                            recipients_count: recipients_list.len(),
                            unique_ref,
                            recipients,
                        },
                    ),
                );
        }

        fn distribute_weighted(
            ref self: ContractState,
            amounts: Array<u256>,
            recipients: Array<ContractAddress>,
            token: ContractAddress,
            unique_ref: felt252,
        ) {
            // Validate inputs
            assert(!recipients.is_empty(), EMPTY_RECIPIENTS);
            assert(amounts.len() == recipients.len(), ARRAY_LEN_MISMATCH);
            self.validate_token(token);

            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let mut amount_to_distribute: u256 = 0;
            let timestamp: u64 = get_block_timestamp();

            // Calculate total amount needed
            let mut i = 0;
            while i < amounts.len() {
                let amount = *amounts.at(i);
                assert(amount > 0, ZERO_AMOUNT);
                amount_to_distribute += amount;
                i += 1;
            }

            let protocol_fee = self.calculate_protocol_fee(@amount_to_distribute);
            let total_amount = amount_to_distribute + protocol_fee;
            let allowance = token_dispatcher.allowance(caller, contract_address);
            assert(allowance >= total_amount, INSUFFICIENT_ALLOWANCE);

            // transfer protocol fee
            if protocol_fee > 0 {
                let protocol_address = self.protocol_fee_address.read();
                assert(!protocol_address.is_zero(), PROTOCOL_FEE_ADDRESS_NOT_SET);
                token_dispatcher.transfer_from(caller, protocol_address, protocol_fee);
            }

            // Transfer tokens from sender to recipients
            i = 0;
            while i < recipients.len() {
                let recipient = *recipients.at(i);
                let amount = *amounts.at(i);

                token_dispatcher.transfer_from(caller, recipient, amount);

                // Emit event for each distribution
                self.emit(WeightedDistribution { caller, token, recipient, amount, unique_ref });

                i += 1;
            }

            // Update global statistics
            self.update_global_stats(amount_to_distribute);
            self.update_token_stats(token, amount_to_distribute);
            self.update_user_stats(caller, amount_to_distribute, token);

            // Record distribution history
            self
                .record_distribution(
                    DistributionHistory {
                        caller,
                        token,
                        amount: amount_to_distribute,
                        recipients_count: recipients.len(),
                        unique_ref,
                        timestamp,
                    },
                );

            // Add summary event at the end
            self
                .emit(
                    Event::Distribution(
                        Distribution {
                            caller,
                            token,
                            amount: amount_to_distribute,
                            recipients_count: recipients.len(),
                            unique_ref,
                            recipients,
                        },
                    ),
                );
        }

        fn get_protocol_fee_percent(self: @ContractState) -> u256 {
            self.protocol_fee_percent.read()
        }

        fn set_protocol_fee_percent(ref self: ContractState, new_fee_percent: u256) {
            self.ownable.assert_only_owner();
            self.protocol_fee_percent.write(new_fee_percent);
        }

        fn get_protocol_fee_address(self: @ContractState) -> ContractAddress {
            self.protocol_fee_address.read()
        }

        fn set_protocol_fee_address(ref self: ContractState, new_fee_address: ContractAddress) {
            self.ownable.assert_only_owner();
            self.protocol_fee_address.write(new_fee_address);
        }

        fn get_balance(self: @ContractState) -> u256 {
            self.balance.read()
        }

        fn get_total_distributions(self: @ContractState) -> u256 {
            self.total_distributions.read()
        }

        fn get_total_distributed_amount(self: @ContractState) -> u256 {
            self.total_distributed_amount.read()
        }

        fn get_token_stats(self: @ContractState, token: ContractAddress) -> TokenStats {
            self.token_stats.read(token)
        }

        fn get_user_stats(self: @ContractState, user: ContractAddress) -> UserStats {
            self.user_stats.read(user)
        }

        fn get_distribution_history(
            self: @ContractState, start_id: u256, limit: u256,
        ) -> Array<DistributionHistory> {
            let mut history: Array<DistributionHistory> = ArrayTrait::new();
            let mut i = start_id;

            while i < start_id + limit {
                let distribution = self.distribution_history.read(i);
                history.append(distribution);
                i += 1;
            }
            history
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
