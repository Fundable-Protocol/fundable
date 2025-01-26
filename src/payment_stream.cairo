#[starknet::contract]
mod PaymentStream {
    use starknet::{get_block_timestamp, get_caller_address, contract_address_const, storage::Map,};
    use core::traits::Into;
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use crate::base::types::{Stream, StreamStatus};
    use fundable::interfaces::IPaymentStream::IPaymentStream;

    #[storage]
    struct Storage {
        next_stream_id: u256,
        streams: Map<u256, Stream>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StreamCreated: StreamCreated,
        StreamWithdrawn: StreamWithdrawn,
        StreamCanceled: StreamCanceled,
        StreamPaused: StreamPaused,
        StreamRestarted: StreamRestarted,
        StreamVoided: StreamVoided
    }

    #[derive(Drop, starknet::Event)]
    struct StreamCreated {
        #[key]
        stream_id: u256,
        sender: ContractAddress,
        recipient: ContractAddress,
        total_amount: u256,
        token: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct StreamWithdrawn {
        #[key]
        stream_id: u256,
        recipient: ContractAddress,
        amount: u256,
        protocol_fee: u128
    }

    #[derive(Drop, starknet::Event)]
    struct StreamCanceled {
        #[key]
        stream_id: u256
    }

    #[derive(Drop, starknet::Event)]
    struct StreamPaused {
        #[key]
        stream_id: u256,
        pause_time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct StreamRestarted {
        #[key]
        stream_id: u256,
        rate_per_second: u256
    }

    #[derive(Drop, starknet::Event)]
    struct StreamVoided {
        #[key]
        stream_id: u256
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_stream_exists(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(!stream.sender.is_zero(), 'Stream does not exist');
        }

        fn assert_is_recipient(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(get_caller_address() == stream.recipient, 'Not stream recipient');
        }

        fn assert_is_sender(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(get_caller_address() == stream.sender, 'Not stream sender');
        }

        fn calculate_stream_rate(total_amount: u256, duration: u64) -> u256 {
            if duration == 0 {
                return 0;
            }
            total_amount / duration.into()
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
            assert(!recipient.is_zero(), 'Invalid recipient');
            assert(total_amount > 0, 'Amount must be > 0');
            assert(end_time > start_time, 'End time before start time');
            assert(!token.is_zero(), 'Invalid token address');

            let stream_id = self.next_stream_id.read();
            self.next_stream_id.write(stream_id + 1);

            // Create new stream
            let stream = Stream {
                sender: get_caller_address(),
                recipient,
                token,
                total_amount,
                start_time,
                end_time,
                withdrawn_amount: 0,
                cancelable,
                status: StreamStatus::Active,
                rate_per_second: 0,
                last_update_time: 0,
            };

            self.streams.write(stream_id, stream);

            self
                .emit(
                    Event::StreamCreated(
                        StreamCreated {
                            stream_id, sender: get_caller_address(), recipient, total_amount, token
                        }
                    )
                );

            stream_id
        }

        fn withdraw(
            ref self: ContractState, stream_id: u256, amount: u256, to: ContractAddress
        ) -> (u128, u128) {
            // Return dummy values for (withdrawn_amount, protocol_fee_amount)
            (0_u128, 0_u128)
        }

        fn withdraw_max(
            ref self: ContractState, stream_id: u256, to: ContractAddress
        ) -> (u128, u128) {
            // Return dummy values for (withdrawn_amount, protocol_fee_amount)
            (0_u128, 0_u128)
        }

        fn cancel(ref self: ContractState, stream_id: u256) { // Empty implementation
        // todo!()
        }

        fn pause(ref self: ContractState, stream_id: u256) { // Empty implementation
        // todo!()
        }

        fn restart(
            ref self: ContractState, stream_id: u256, rate_per_second: u256
        ) { // Empty implementation
        //  todo!()
        }

        fn void(ref self: ContractState, stream_id: u256) { // Empty implementation
        //  todo!()
        }

        fn get_stream(self: @ContractState, stream_id: u256) -> Stream {
            // Return dummy stream
            Stream {
                sender: starknet::contract_address_const::<0>(),
                recipient: starknet::contract_address_const::<0>(),
                token: starknet::contract_address_const::<0>(),
                total_amount: 0_u256,
                start_time: 0_u64,
                end_time: 0_u64,
                withdrawn_amount: 0_u256,
                cancelable: false,
                status: StreamStatus::Active,
                rate_per_second: 0,
                last_update_time: 0,
            }
        }

        fn get_withdrawable_amount(self: @ContractState, stream_id: u256) -> u256 {
            // Return dummy amount
            0_u256
        }

        fn is_stream_active(self: @ContractState, stream_id: u256) -> bool {
            // Return dummy status
            false
        }

        fn get_depletion_time(self: @ContractState, stream_id: u256) -> u64 {
            // Return dummy timestamp
            0_u64
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
    }
}
