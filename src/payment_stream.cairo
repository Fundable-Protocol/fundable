#[starknet::contract]
mod PaymentStream {
    use core::num::traits::Zero;
    use core::traits::Into;
    use fp::UFixedPoint123x128;
    use fundable::interfaces::IPaymentStream::IPaymentStream;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
        IERC20MetadataDispatcherTrait,
    };
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{
        ContractAddress, contract_address_const, get_block_timestamp, get_caller_address,
        get_contract_address,
    };
    use crate::base::errors::Errors::{
        DECIMALS_TOO_HIGH, END_BEFORE_START, INSUFFICIENT_ALLOWANCE, INVALID_RECIPIENT,
        INVALID_TOKEN, TOO_SHORT_DURATION, UNEXISTING_STREAM, WRONG_RECIPIENT,
        WRONG_RECIPIENT_OR_DELEGATE, WRONG_SENDER, ZERO_AMOUNT,
    };
    use crate::base::types::{ProtocolMetrics, Stream, StreamMetrics, StreamStatus};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: Src5Event);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    const PROTOCOL_OWNER_ROLE: felt252 = selector!("PROTOCOL_OWNER");
    const STREAM_ADMIN_ROLE: felt252 = selector!("STREAM_ADMIN");


    #[storage]
    struct Storage {
        next_stream_id: u256,
        streams: Map<u256, Stream>,
        protocol_fee_percentage: u16,
        fee_collector: ContractAddress,
        protocol_owner: ContractAddress,
        accumulated_fees: Map<ContractAddress, u256>,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        total_active_streams: u256,
        total_distributed: Map<ContractAddress, u256>,
        stream_metrics: Map<u256, StreamMetrics>,
        protocol_metrics: ProtocolMetrics,
        stream_delegates: Map<u256, ContractAddress>,
        delegation_history: Map<u256, Vec<ContractAddress>>,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StreamRateUpdated: StreamRateUpdated,
        StreamCreated: StreamCreated,
        StreamWithdrawn: StreamWithdrawn,
        StreamCanceled: StreamCanceled,
        StreamPaused: StreamPaused,
        StreamRestarted: StreamRestarted,
        StreamVoided: StreamVoided,
        FeeCollected: FeeCollected,
        WithdrawalSuccessful: WithdrawalSuccessful,
        #[flat]
        Src5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        DelegationGranted: DelegationGranted,
        DelegationRevoked: DelegationRevoked,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamRateUpdated {
        #[key]
        stream_id: u256,
        old_rate: UFixedPoint123x128,
        new_rate: UFixedPoint123x128,
        update_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeCollected {
        #[key]
        from: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalSuccessful {
        #[key]
        token: ContractAddress,
        amount: u256,
        recipient: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamCreated {
        #[key]
        stream_id: u256,
        sender: ContractAddress,
        recipient: ContractAddress,
        total_amount: u256,
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamWithdrawn {
        #[key]
        stream_id: u256,
        recipient: ContractAddress,
        amount: u256,
        protocol_fee: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamCanceled {
        #[key]
        stream_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamPaused {
        #[key]
        stream_id: u256,
        pause_time: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamRestarted {
        #[key]
        stream_id: u256,
        rate_per_second: UFixedPoint123x128,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamVoided {
        #[key]
        stream_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegationGranted {
        #[key]
        stream_id: u256,
        delegator: ContractAddress,
        delegate: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct DelegationRevoked {
        #[key]
        stream_id: u256,
        delegator: ContractAddress,
        delegate: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, protocol_owner: ContractAddress) {
        self.accesscontrol.initializer();
        self.protocol_owner.write(protocol_owner);
        self.accesscontrol._grant_role(PROTOCOL_OWNER_ROLE, protocol_owner);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_stream_exists(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(!stream.sender.is_zero(), UNEXISTING_STREAM);
        }

        fn assert_is_recipient(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(get_caller_address() == stream.recipient, WRONG_RECIPIENT);
        }

        fn assert_is_sender(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(get_caller_address() == stream.sender, WRONG_SENDER);
        }

        fn calculate_stream_rate(
            self: @ContractState, total_amount: u256, duration: u64,
        ) -> UFixedPoint123x128 {
            if duration == 0 {
                return 0_u64.into();
            }
            let num: UFixedPoint123x128 = total_amount.into();
            let divisor: UFixedPoint123x128 = duration.into();
            let rate = num / divisor;
            return rate;
        }

        /// @notice points basis: 100pbs = 1%
        fn calculate_protocol_fee(self: @ContractState, total_amount: u256) -> u256 {
            let protocol_fee_percentage = self.protocol_fee_percentage.read();
            let fee = (total_amount * protocol_fee_percentage.into()) / 10000;
            fee
        }

        fn collect_protocol_fee(
            self: @ContractState, sender: ContractAddress, token: ContractAddress, amount: u256,
        ) {
            let fee_collector: ContractAddress = self.fee_collector.read();
            assert(fee_collector.is_non_zero(), INVALID_RECIPIENT);
            IERC20Dispatcher { contract_address: token }
                .transfer_from(sender, fee_collector, amount);
        }

        fn assert_is_recipient_or_delegate(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            let caller = get_caller_address();
            if caller != stream.recipient {
                let delegate = self.stream_delegates.read(stream_id);
                assert(caller == delegate, WRONG_RECIPIENT_OR_DELEGATE);
            }
        }
    }

    #[abi(embed_v0)]
    impl PaymentStreamImpl of IPaymentStream<ContractState> {
        fn create_stream(
            ref self: ContractState,
            recipient: ContractAddress,
            total_amount: u256,
            start_time: u64,
            end_time: u64,
            cancelable: bool,
            token: ContractAddress,
        ) -> u256 {
            // Validate inputs
            assert(!recipient.is_zero(), INVALID_RECIPIENT);
            assert(total_amount > 0, ZERO_AMOUNT);
            assert(end_time > start_time, END_BEFORE_START);
            assert(!token.is_zero(), INVALID_TOKEN);

            let stream_id = self.next_stream_id.read();
            self.next_stream_id.write(stream_id + 1);

            // Calculate rate using FixedPoint
            let duration = end_time - start_time;
            assert(duration >= 1, TOO_SHORT_DURATION);
            let rate_per_second = self.calculate_stream_rate(total_amount, duration);

            let erc20_dispatcher = IERC20MetadataDispatcher { contract_address: token };
            let token_decimals = erc20_dispatcher.decimals();
            assert(token_decimals <= 18, DECIMALS_TOO_HIGH);

            // Create new stream
            let stream = Stream {
                sender: get_caller_address(),
                recipient,
                token,
                token_decimals,
                total_amount,
                start_time,
                end_time,
                withdrawn_amount: 0,
                cancelable,
                status: StreamStatus::Active,
                rate_per_second,
                last_update_time: start_time,
            };

            self.accesscontrol._grant_role(STREAM_ADMIN_ROLE, stream.sender);
            self.streams.write(stream_id, stream);

            let protocol_metrics = self.protocol_metrics.read();
            self
                .protocol_metrics
                .write(
                    ProtocolMetrics {
                        total_active_streams: protocol_metrics.total_active_streams + 1,
                        total_tokens_distributed: protocol_metrics.total_tokens_distributed
                            + total_amount,
                        total_streams_created: protocol_metrics.total_streams_created + 1,
                        total_delegations: protocol_metrics.total_delegations + 1,
                    },
                );

            self
                .emit(
                    Event::StreamCreated(
                        StreamCreated {
                            stream_id, sender: get_caller_address(), recipient, total_amount, token,
                        },
                    ),
                );

            stream_id
        }


        fn withdraw(
            ref self: ContractState, stream_id: u256, amount: u256, to: ContractAddress,
        ) -> (u128, u128) {
            self.assert_is_recipient_or_delegate(stream_id);
            assert(amount > 0, ZERO_AMOUNT);
            assert(to.is_non_zero(), INVALID_RECIPIENT);

            let stream = self.streams.read(stream_id);
            let fee = self.calculate_protocol_fee(amount);
            let net_amount = (amount - fee);
            let token_address = stream.token;
            let sender = get_caller_address();
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let contract_allowance = token_dispatcher.allowance(sender, get_contract_address());

            assert(contract_allowance >= amount, INSUFFICIENT_ALLOWANCE);
            /// @dev converting fee and net_amount into u128 type
            let net_amount_into_u128 = net_amount.try_into().unwrap();
            let fee_into_u128 = fee.try_into().unwrap();

            self.collect_protocol_fee(sender, token_address, fee);

            self
                .emit(
                    StreamWithdrawn {
                        stream_id, recipient: to, amount: net_amount, protocol_fee: fee_into_u128,
                    },
                );

            (net_amount_into_u128, fee_into_u128)
        }

        fn withdraw_max(
            ref self: ContractState, stream_id: u256, to: ContractAddress,
        ) -> (u128, u128) {
            self.assert_is_recipient_or_delegate(stream_id);
            assert(to.is_non_zero(), INVALID_RECIPIENT);

            let stream = self.streams.read(stream_id);
            let token_address = stream.token;
            let sender = stream.sender;
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let max_amount = token_dispatcher.balance_of(sender);
            let fee = self.calculate_protocol_fee(max_amount);
            let net_amount = (max_amount - fee);

            /// @dev converting fee and net_amount into u128 type
            let fee_into_u128 = fee.try_into().unwrap();
            let net_amount_into_u128 = net_amount.try_into().unwrap();

            token_dispatcher
                .transfer_from(sender, to, net_amount); // todo: check if this is correct
            self.collect_protocol_fee(sender, token_address, fee);

            self
                .emit(
                    StreamWithdrawn {
                        stream_id, recipient: to, amount: net_amount, protocol_fee: fee_into_u128,
                    },
                );

            (net_amount_into_u128, fee_into_u128)
        }

        fn withdraw_protocol_fee(
            ref self: ContractState,
            recipient: ContractAddress,
            amount: u256,
            token: ContractAddress,
        ) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);
            assert(amount > 0, ZERO_AMOUNT);
            assert(recipient.is_non_zero(), INVALID_RECIPIENT);

            let fee_collector = self.fee_collector.read();
            let _success = IERC20Dispatcher { contract_address: token }
                .transfer_from(fee_collector, recipient, amount);
            assert(_success, 'token withdrawal fail...');

            let accumulated_fees = self.accumulated_fees.read(token);
            self.accumulated_fees.write(token, accumulated_fees - amount);

            self.emit(WithdrawalSuccessful { token, amount, recipient });
        }

        fn withdraw_max_protocol_fee(
            ref self: ContractState, recipient: ContractAddress, token: ContractAddress,
        ) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);
            assert(recipient.is_non_zero(), INVALID_RECIPIENT);

            let fee_collector = self.fee_collector.read();

            assert(fee_collector.is_non_zero(), INVALID_RECIPIENT);

            let max_amount = IERC20Dispatcher { contract_address: token }.balance_of(fee_collector);

            let _success = IERC20Dispatcher { contract_address: token }
                .transfer_from(fee_collector, recipient, max_amount);
            assert(_success, 'token withdrawal fail...');

            let accumulated_fees = self.accumulated_fees.read(token);
            self.accumulated_fees.write(token, accumulated_fees - max_amount);

            self.emit(WithdrawalSuccessful { token, amount: max_amount, recipient });
        }

        fn update_percentage_protocol_fee(ref self: ContractState, new_percentage: u16) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            let protocol_fee_percentage = self.protocol_fee_percentage.read();
            assert(
                new_percentage > 0 && new_percentage != protocol_fee_percentage,
                'invalid fee percentage',
            );

            self.protocol_fee_percentage.write(new_percentage);
        }

        fn update_fee_collector(ref self: ContractState, new_fee_collector: ContractAddress) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            let fee_collector = self.fee_collector.read();
            assert(new_fee_collector.is_non_zero(), INVALID_RECIPIENT);
            assert(new_fee_collector != fee_collector, 'same collector address');

            self.fee_collector.write(new_fee_collector);
        }

        fn update_protocol_owner(ref self: ContractState, new_protocol_owner: ContractAddress) {
            let current_owner = self.protocol_owner.read();
            assert(new_protocol_owner.is_non_zero(), INVALID_RECIPIENT);
            assert(new_protocol_owner != current_owner, 'current owner == new_owner');

            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            self.protocol_owner.write(new_protocol_owner);

            self.accesscontrol.revoke_role(PROTOCOL_OWNER_ROLE, current_owner);
            self.accesscontrol._grant_role(PROTOCOL_OWNER_ROLE, new_protocol_owner);
        }

        fn get_fee_collector(self: @ContractState) -> ContractAddress {
            self.fee_collector.read()
        }

        fn cancel(ref self: ContractState, stream_id: u256) {
            // Ensure the caller has the STREAM_ADMIN_ROLE
            self.accesscontrol.assert_only_role(STREAM_ADMIN_ROLE);

            // Retrieve the stream
            let mut stream = self.streams.read(stream_id);

            // Ensure the stream is active before cancellation
            self.assert_stream_exists(stream_id);
            assert(stream.status == StreamStatus::Active, 'Stream is not Active');
            // Update the stream status to canceled
            stream.status = StreamStatus::Canceled;
            // Update the stream recipient back to the sender
            stream.recipient = stream.sender;

            // Update the stream end time
            stream.end_time = get_block_timestamp();

            // Handle refunding unclaimed funds
            let recipient = get_caller_address();

            // Calculate the amount that can be refunded
            let refundable_amount = stream.total_amount - stream.withdrawn_amount;
            // Update Stream in State
            self.streams.write(stream_id, stream);

            if refundable_amount > 0 {
                self.withdraw_max(stream_id, recipient);
            }

            // Emit an event for stream cancellation
            self.emit(StreamCanceled { stream_id });
        }

        fn pause(ref self: ContractState, stream_id: u256) {
            let mut stream = self.streams.read(stream_id);

            self.assert_stream_exists(stream_id);
            assert(stream.status != StreamStatus::Canceled, 'Stream is not active');

            stream.status = StreamStatus::Paused;
            self.streams.write(stream_id, stream);

            self.emit(StreamPaused { stream_id, pause_time: starknet::get_block_timestamp() });
        }

        fn restart(ref self: ContractState, stream_id: u256, rate_per_second: UFixedPoint123x128) {
            let mut stream = self.streams.read(stream_id);

            self.assert_stream_exists(stream_id);
            assert(stream.status != StreamStatus::Canceled, 'Stream is not active');

            stream.status = StreamStatus::Active;
            stream.rate_per_second = rate_per_second;
            self.streams.write(stream_id, stream);

            self.emit(StreamRestarted { stream_id, rate_per_second });
        }

        fn void(ref self: ContractState, stream_id: u256) {
            let mut stream = self.streams.read(stream_id);

            self.assert_stream_exists(stream_id);
            assert(stream.status != StreamStatus::Canceled, 'Stream is not active');

            stream.status = StreamStatus::Voided;
            self.streams.write(stream_id, stream);

            self.emit(StreamVoided { stream_id });
        }

        fn get_stream(self: @ContractState, stream_id: u256) -> Stream {
            // Return dummy stream
            // Stream {
            //     sender: starknet::contract_address_const::<0>(),
            //     recipient: starknet::contract_address_const::<0>(),
            //     token: starknet::contract_address_const::<0>(),
            //     total_amount: 0_u256,
            //     start_time: 0_u64,
            //     end_time: 0_u64,
            //     withdrawn_amount: 0_u256,
            //     cancelable: false,
            //     status: StreamStatus::Active,
            //     rate_per_second: 0,
            //     last_update_time: 0,
            // }

            self.streams.read(stream_id)
        }

        fn get_withdrawable_amount(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn is_stream_active(self: @ContractState, stream_id: u256) -> bool {
            // Return dummy status
            let mut stream = self.streams.read(stream_id);

            if (stream.status == StreamStatus::Active) {
                return true;
            } else {
                return false;
            }
        }

        fn get_depletion_time(self: @ContractState, stream_id: u256) -> u64 {
            // Return dummy timestamp
            0_u64
        }

        fn get_token_decimals(self: @ContractState, stream_id: u256) -> u8 {
            self.streams.read(stream_id).token_decimals
        }

        fn get_total_debt(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn get_uncovered_debt(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn get_covered_debt(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn get_refundable_amount(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn get_active_streams_count(self: @ContractState) -> u256 {
            self.total_active_streams.read()
        }

        fn get_token_distribution(self: @ContractState, token: ContractAddress) -> u256 {
            self.total_distributed.read(token)
        }

        fn get_stream_metrics(self: @ContractState, stream_id: u256) -> StreamMetrics {
            self.stream_metrics.read(stream_id)
        }

        fn get_protocol_metrics(self: @ContractState) -> ProtocolMetrics {
            self.protocol_metrics.read()
        }

        fn delegate_stream(
            ref self: ContractState, stream_id: u256, delegate: ContractAddress,
        ) -> bool {
            self.assert_stream_exists(stream_id);
            self.assert_is_sender(stream_id);
            assert(delegate.is_non_zero(), INVALID_RECIPIENT);
            self.stream_delegates.write(stream_id, delegate);
            self.delegation_history.entry(stream_id).append().write(delegate);
            self.emit(DelegationGranted { stream_id, delegator: get_caller_address(), delegate });
            true
        }

        fn revoke_delegation(ref self: ContractState, stream_id: u256) -> bool {
            self.assert_stream_exists(stream_id);
            self.assert_is_sender(stream_id);
            let delegate = self.stream_delegates.read(stream_id);
            assert(delegate.is_non_zero(), UNEXISTING_STREAM);
            self.stream_delegates.write(stream_id, contract_address_const::<0x0>());
            self.emit(DelegationRevoked { stream_id, delegator: get_caller_address(), delegate });
            true
        }

        fn get_stream_delegate(self: @ContractState, stream_id: u256) -> ContractAddress {
            self.stream_delegates.read(stream_id)
        }

        fn update_stream_rate(
            ref self: ContractState, stream_id: u256, new_rate_per_second: UFixedPoint123x128,
        ) {
            let caller = get_caller_address();
            let zero_amount: UFixedPoint123x128 = 0.into();
            let total = new_rate_per_second + zero_amount;
            let z: u256 = total.into();
            assert(z > 0, ZERO_AMOUNT);
            assert(self.streams.read(stream_id).sender == caller, WRONG_SENDER);

            let stream: Stream = self.streams.read(stream_id);
            assert!(stream.status == StreamStatus::Active, "Stream is not active");

            let new_stream = Stream {
                rate_per_second: new_rate_per_second,
                sender: stream.sender,
                recipient: stream.recipient,
                token: stream.token,
                token_decimals: stream.token_decimals,
                total_amount: stream.total_amount,
                start_time: stream.start_time,
                end_time: stream.end_time,
                withdrawn_amount: stream.withdrawn_amount,
                cancelable: stream.cancelable,
                status: stream.status,
                last_update_time: starknet::get_block_timestamp(),
            };

            self.streams.write(stream_id, new_stream);
            self
                .emit(
                    Event::StreamRateUpdated(
                        StreamRateUpdated {
                            stream_id,
                            old_rate: stream.rate_per_second,
                            new_rate: new_rate_per_second,
                            update_time: starknet::get_block_timestamp(),
                        },
                    ),
                );
        }
    }
}
