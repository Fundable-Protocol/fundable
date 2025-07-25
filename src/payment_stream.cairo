#[starknet::contract]
pub mod PaymentStream {
    use core::num::traits::{Bounded, Zero};
    use core::traits::Into;
    use fundable::interfaces::IPaymentStream::IPaymentStream;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    use openzeppelin::token::erc20::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
        IERC20MetadataDispatcherTrait,
    };
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec,
    };
    use starknet::{
        ClassHash, ContractAddress, get_block_timestamp, get_caller_address, get_contract_address,
    };
    use crate::base::errors::Errors::{
        DECIMALS_TOO_HIGH, FEE_TOO_HIGH, INSUFFICIENT_ALLOWANCE, INSUFFICIENT_AMOUNT,
        INVALID_RECIPIENT, INVALID_TOKEN, NON_TRANSFERABLE_STREAM, ONLY_NFT_OWNER_CAN_DELEGATE,
        OVERDEPOSIT, SAME_COLLECTOR_ADDRESS, SAME_OWNER, STREAM_CANCELED, STREAM_HAS_DELEGATE,
        STREAM_NOT_ACTIVE, STREAM_NOT_PAUSED, TOO_SHORT_DURATION, UNEXISTING_STREAM,
        WRONG_RECIPIENT, WRONG_RECIPIENT_OR_DELEGATE, WRONG_SENDER, ZERO_AMOUNT,
    };
    use crate::base::types::{ProtocolMetrics, Stream, StreamMetrics, StreamStatus};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: Src5Event);
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    component!(path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    const PROTOCOL_OWNER_ROLE: felt252 = selector!("PROTOCOL_OWNER");
    // Note: STREAM_ADMIN_ROLE removed - using stream-specific access control

    const MAX_FEE: u256 = 5000;
    const SECONDS_PER_HOUR: u64 = 3600;
    const PRECISION_SCALE: u256 = 1000000000000000000; // 1e18 for fixed-point precision


    #[storage]
    struct Storage {
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        next_stream_id: u256,
        streams: Map<u256, Stream>,
        protocol_fee_rate: Map<ContractAddress, u64>, // Single source of truth for fee rates
        general_protocol_fee_rate: u64,
        fee_collector: ContractAddress,
        protocol_owner: ContractAddress,
        protocol_revenue: Map<ContractAddress, u256>, // Track collected fees
        total_active_streams: u256,
        stream_metrics: Map<u256, StreamMetrics>,
        protocol_metrics: ProtocolMetrics,
        stream_delegates: Map<u256, ContractAddress>,
        delegation_history: Map<u256, Vec<ContractAddress>>,
        aggregate_balance: Map<ContractAddress, u256>,
        snapshot_debt: Map<u256, u256>,
        snapshot_time: Map<u256, u64>,
        paused_rates: Map<u256, u256>,
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        Src5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        StreamCreated: StreamCreated,
        StreamWithdrawn: StreamWithdrawn,
        StreamCanceled: StreamCanceled,
        StreamPaused: StreamPaused,
        StreamRestarted: StreamRestarted,
        FeeCollected: FeeCollected,
        WithdrawalSuccessful: WithdrawalSuccessful,
        DelegationGranted: DelegationGranted,
        DelegationRevoked: DelegationRevoked,
        StreamTransferabilitySet: StreamTransferabilitySet,
        StreamTransferred: StreamTransferred,
        ProtocolFeeSet: ProtocolFeeSet,
        GeneralProtocolFeeSet: GeneralProtocolFeeSet,
        ProtocolRevenueCollected: ProtocolRevenueCollected,
        StreamDeposit: StreamDeposit,
        Recover: Recover,
        RefundFromStream: RefundFromStream,
        FeeCollectorUpdated: FeeCollectorUpdated,
        ProtocolOwnerUpdated: ProtocolOwnerUpdated,
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
        transferable: bool,
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
        rate_per_second: u256,
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

    #[derive(Drop, starknet::Event)]
    struct StreamTransferabilitySet {
        #[key]
        stream_id: u256,
        transferable: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamTransferred {
        #[key]
        stream_id: u256,
        new_recipient: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ProtocolFeeSet {
        #[key]
        token: ContractAddress,
        set_by: ContractAddress,
        new_fee: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct GeneralProtocolFeeSet {
        #[key]
        set_by: ContractAddress,
        new_fee: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct ProtocolRevenueCollected {
        #[key]
        token: ContractAddress,
        collected_by: ContractAddress,
        sent_to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamDeposit {
        #[key]
        stream_id: u256,
        funder: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeCollectorUpdated {
        #[key]
        new_fee_collector: ContractAddress,
        #[key]
        old_fee_collector: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ProtocolOwnerUpdated {
        #[key]
        new_protocol_owner: ContractAddress,
        #[key]
        old_protocol_owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Recover {
        #[key]
        pub sender: ContractAddress,
        pub to: ContractAddress,
        pub surplus: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RefundFromStream {
        #[key]
        stream_id: u256,
        sender: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        protocol_owner: ContractAddress,
        general_protocol_fee_rate: u64,
        protocol_fee_address: ContractAddress,
    ) {
        self.accesscontrol.initializer();
        self.protocol_owner.write(protocol_owner);
        self.general_protocol_fee_rate.write(general_protocol_fee_rate);
        self.fee_collector.write(protocol_fee_address);
        self.accesscontrol._grant_role(PROTOCOL_OWNER_ROLE, protocol_owner);
        self.erc721.initializer("PaymentStream", "STREAM", "https://paymentstream.io/");
    }

    /// @notice Calculates the rate of tokens per second for a stream with fixed-point precision
    /// @param total_amount The total amount of tokens to be streamed
    /// @param duration The duration of the stream in hours
    /// @return The rate of tokens per second scaled by PRECISION_SCALE
    fn calculate_stream_rate(total_amount: u256, duration: u64) -> u256 {
        if duration == 0 {
            return 0_u64.into();
        }

        // Convert duration from hours to seconds
        let duration_in_seconds = (duration * SECONDS_PER_HOUR);

        // Check for potential overflow before scaling
        let max_safe_amount = Bounded::MAX / PRECISION_SCALE;
        assert(total_amount <= max_safe_amount, 'Amount too large for scaling');

        // Safe multiplication: total_amount * PRECISION_SCALE
        let scaled_total = total_amount * PRECISION_SCALE;

        // Calculate scaled rate: scaled_total / duration_in_seconds
        // Returns rate scaled by PRECISION_SCALE (tokens per second * 1e18)
        let scaled_rate = scaled_total / duration_in_seconds.into();
        return scaled_rate;
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_stream_exists(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(!stream.sender.is_zero(), UNEXISTING_STREAM);
        }

        fn assert_stream_sender_access(self: @ContractState, stream_id: u256) {
            self.assert_stream_exists(stream_id);
            let stream = self.streams.read(stream_id);
            let caller = get_caller_address();
            assert(caller == stream.sender, WRONG_SENDER);
        }

        /// @notice Safely multiplies two numbers and checks for overflow
        /// @param a First number
        /// @param b Second number
        /// @return The product if no overflow, panics otherwise
        fn safe_multiply(self: @ContractState, a: u256, b: u256) -> u256 {
            // Check for overflow: if a > 0 and b > MAX/a, then overflow
            if a > 0 {
                let max_val: u256 = Bounded::MAX;
                assert(b <= max_val / a, 'Multiplication overflow');
            }
            a * b
        }

        /// @notice Safely performs scaled multiplication: (a * b) / scale
        /// @param a First number
        /// @param b Second number
        /// @param scale Scale factor
        /// @return The scaled product
        fn safe_scaled_multiply(self: @ContractState, a: u256, b: u256, scale: u256) -> u256 {
            let product = self.safe_multiply(a, b);
            product / scale
        }

        /// @notice Gets the scaled rate per second for internal calculations
        /// @param stream_id The stream ID
        /// @return The scaled rate per second (multiplied by PRECISION_SCALE)
        fn _get_scaled_rate_per_second(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            stream.rate_per_second.into()
        }

        fn assert_is_sender(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(get_caller_address() == stream.sender, WRONG_SENDER);
        }

        fn assert_is_recipient(self: @ContractState, stream_id: u256) {
            let recipient = self.erc721.owner_of(stream_id);
            assert(get_caller_address() == recipient, WRONG_RECIPIENT);
        }

        fn assert_is_transferable(self: @ContractState, stream_id: u256) {
            let stream = self.streams.read(stream_id);
            assert(stream.transferable, NON_TRANSFERABLE_STREAM);
        }

        /// @notice Calculates the protocol fee using high-precision fixed-point arithmetic
        /// @param amount The amount to calculate fee from
        /// @param token_address The token address to get fee rate for
        /// @return The protocol fee amount
        fn _calculate_protocol_fee(
            self: @ContractState, amount: u256, token_address: ContractAddress,
        ) -> u256 {
            let fee_rate = self.protocol_fee_rate.read(token_address);
            assert(fee_rate <= MAX_FEE.try_into().unwrap(), FEE_TOO_HIGH);

            let rate = if fee_rate == 0 {
                self.general_protocol_fee_rate.read() // 1% = 100 basis points
            } else {
                fee_rate
            };

            // For small amounts, use high-precision arithmetic to avoid truncation to zero
            if amount < 10000_u256 {
                // Use PRECISION_SCALE for higher precision on small amounts
                // Safe calculation: (amount * PRECISION_SCALE * rate) / (10000 * PRECISION_SCALE)
                let scaled_amount = self.safe_multiply(amount, PRECISION_SCALE);
                let scaled_fee_numerator = self.safe_multiply(scaled_amount, rate.into());
                let scaled_denominator = self.safe_multiply(10000_u256, PRECISION_SCALE);
                scaled_fee_numerator / scaled_denominator
            } else {
                // Standard calculation for larger amounts with overflow protection
                let fee_numerator = self.safe_multiply(amount, rate.into());
                fee_numerator / 10000_u256
            }
        }

        fn collect_protocol_fee(ref self: ContractState, token: ContractAddress, amount: u256) {
            self.reentrancy_guard.start();
            let fee_collector: ContractAddress = self.fee_collector.read();
            assert(fee_collector.is_non_zero(), INVALID_RECIPIENT);
            IERC20Dispatcher { contract_address: token }.transfer(fee_collector, amount);
            self.reentrancy_guard.end();
        }

        // Updated to check NFT ownership or delegate
        fn assert_is_recipient_or_delegate(self: @ContractState, stream_id: u256) {
            let caller = get_caller_address();
            let recipient = self.erc721.owner_of(stream_id);
            let approved = self.erc721.get_approved(stream_id);
            let delegate = self.stream_delegates.read(stream_id);
            assert(
                caller == recipient || caller == approved || caller == delegate,
                WRONG_RECIPIENT_OR_DELEGATE,
            );
        }

        fn _deposit(ref self: ContractState, stream_id: u256, amount: u256) {
            // Check: the stream exists
            self.assert_stream_exists(stream_id);

            // Check: the deposit amount is not zero
            assert(amount > 0, ZERO_AMOUNT);

            let mut stream = self.streams.read(stream_id);
            let mut stream_metrics = self.stream_metrics.read(stream_id);
            let deposit_diff = stream.total_amount - stream_metrics.total_deposited;
            assert(deposit_diff >= amount, OVERDEPOSIT);

            // Check: stream is not canceled
            assert(stream.status != StreamStatus::Canceled, STREAM_CANCELED);

            let token_address = stream.token;

            // Effect: update the stream balance by adding the deposit amount
            stream.balance += amount;
            self.streams.write(stream_id, stream);

            // Update stream metrics
            stream_metrics.total_deposited += amount;
            stream_metrics.last_activity = get_block_timestamp();
            self.stream_metrics.write(stream_id, stream_metrics);

            let aggregate_balance = self.aggregate_balance.read(token_address) + amount;
            self.aggregate_balance.write(token_address, aggregate_balance);

            // Interaction: transfer the tokens from the sender to the contract
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            token_dispatcher.transfer_from(get_caller_address(), get_contract_address(), amount);

            // Log the deposit through an event
            self
                .emit(
                    Event::StreamDeposit(
                        StreamDeposit { stream_id, funder: get_caller_address(), amount },
                    ),
                );
        }

        /// @notice Calculates the ongoing debt since last snapshot
        /// @param stream_id The ID of the stream
        /// @return The ongoing debt in actual token units (not scaled)
        fn _ongoing_debt_scaled(self: @ContractState, stream_id: u256) -> u256 {
            let current_time = get_block_timestamp();
            let snapshot_time = self.snapshot_time.read(stream_id);
            let stream = self.streams.read(stream_id);

            // If stream is paused or current time is before snapshot time, return 0
            if stream.status != StreamStatus::Active || current_time <= snapshot_time {
                return 0_u256;
            }

            // Calculate elapsed time since last snapshot
            let elapsed_time = (current_time - snapshot_time).into();

            // Calculate ongoing debt using scaled rate with overflow protection
            // rate_per_second is already scaled by PRECISION_SCALE
            let rate_per_second_scaled = self._get_scaled_rate_per_second(stream_id);

            // Use safe scaled multiplication to calculate debt
            self.safe_scaled_multiply(elapsed_time, rate_per_second_scaled, PRECISION_SCALE)
        }

        /// @notice Calculates the total debt of a stream
        /// @param stream_id The ID of the stream
        /// @return The total debt in token decimals
        fn _total_debt(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            let duration_in_seconds = stream.duration * SECONDS_PER_HOUR;
            let duration_passed = get_block_timestamp() - stream.start_time;

            if duration_passed >= duration_in_seconds {
                return stream.total_amount;
            }

            let ongoing_debt_scaled = self._ongoing_debt_scaled(stream_id);
            let snapshot_debt_scaled = self.snapshot_debt.read(stream_id);

            // Total debt in scaled form
            let total_debt_scaled = ongoing_debt_scaled + snapshot_debt_scaled;

            // Convert from scaled form to token decimals
            total_debt_scaled
        }

        /// @notice Updates the snapshot for a stream
        /// @param stream_id The ID of the stream
        fn _update_snapshot(ref self: ContractState, stream_id: u256) {
            let ongoing_debt_scaled = self._ongoing_debt_scaled(stream_id);
            if ongoing_debt_scaled > 0 {
                let current_snapshot_debt = self.snapshot_debt.read(stream_id);
                self.snapshot_debt.write(stream_id, current_snapshot_debt + ongoing_debt_scaled);
            }
            self.snapshot_time.write(stream_id, get_block_timestamp());
        }

        /// @notice Calculates the withdrawable amount for a stream
        /// @param stream_id The ID of the stream
        /// @return The withdrawable amount
        fn _withdrawable_amount(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            let total_debt = self._total_debt(stream_id);

            // For paused streams, use the snapshot debt (frozen at pause time)
            if stream.status == StreamStatus::Paused {
                let snapshot_debt = self.snapshot_debt.read(stream_id);

                // The withdrawable amount is the snapshot debt minus what's already withdrawn
                if snapshot_debt > stream.withdrawn_amount {
                    snapshot_debt - stream.withdrawn_amount
                } else {
                    0_u256
                }
            } else {
                // For active streams, the withdrawable amount is the minimum of stream balance and
                // total debt
                total_debt - stream.withdrawn_amount
            }
        }

        fn _create_stream(
            ref self: ContractState,
            recipient: ContractAddress,
            total_amount: u256,
            duration: u64,
            cancelable: bool,
            token: ContractAddress,
            transferable: bool,
        ) -> u256 {
            assert(!recipient.is_zero(), INVALID_RECIPIENT);
            assert(total_amount > 0, ZERO_AMOUNT);
            assert(duration >= 1, TOO_SHORT_DURATION);
            assert(!token.is_zero(), INVALID_TOKEN);

            let stream_id = self.next_stream_id.read();
            self.next_stream_id.write(stream_id + 1);

            let erc20_dispatcher = IERC20MetadataDispatcher { contract_address: token };
            let token_decimals = erc20_dispatcher.decimals();
            assert(token_decimals <= 18, DECIMALS_TOO_HIGH);

            let rate_per_second = calculate_stream_rate(total_amount, duration);

            // Create new stream
            let stream = Stream {
                sender: get_caller_address(),
                token,
                token_decimals,
                total_amount,
                balance: 0,
                recipient,
                duration,
                withdrawn_amount: 0,
                cancelable,
                status: StreamStatus::Active,
                rate_per_second,
                last_update_time: get_block_timestamp(),
                transferable,
                start_time: get_block_timestamp(),
                end_time: get_block_timestamp() + duration * SECONDS_PER_HOUR,
            };

            self.snapshot_time.write(stream_id, get_block_timestamp());

            // Initialize stream metrics
            let metrics = StreamMetrics {
                last_activity: get_block_timestamp(),
                total_withdrawn: 0,
                total_deposited: 0,
                withdrawal_count: 0,
                pause_count: 0,
                total_delegations: 0,
                current_delegate: 0.try_into().unwrap(),
                last_delegation_time: 0,
            };

            self.streams.write(stream_id, stream);
            self.stream_metrics.write(stream_id, metrics);
            self.erc721.mint(recipient, stream_id);

            let protocol_metrics = self.protocol_metrics.read();
            self
                .protocol_metrics
                .write(
                    ProtocolMetrics {
                        total_active_streams: protocol_metrics.total_active_streams + 1,
                        total_tokens_to_stream: protocol_metrics.total_tokens_to_stream
                            + total_amount,
                        total_streams_created: protocol_metrics.total_streams_created + 1,
                        total_delegations: protocol_metrics.total_delegations,
                    },
                );

            self
                .emit(
                    Event::StreamCreated(
                        StreamCreated {
                            stream_id,
                            sender: get_caller_address(),
                            recipient,
                            total_amount,
                            token,
                            transferable,
                        },
                    ),
                );
            stream_id
        }

        /// @notice Sets the protocol fee rate for a token
        /// @param token The token address
        /// @param new_fee_rate The new fee rate in basis points (e.g., 100 = 1%)
        fn _set_protocol_fee_rate(
            ref self: ContractState, token: ContractAddress, new_fee_rate: u64,
        ) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);
            assert(new_fee_rate <= MAX_FEE.try_into().unwrap(), FEE_TOO_HIGH);

            let current_fee_rate = self.protocol_fee_rate.read(token);
            if current_fee_rate != new_fee_rate {
                self.protocol_fee_rate.write(token, new_fee_rate);

                self
                    .emit(
                        ProtocolFeeSet {
                            token, set_by: get_caller_address(), new_fee: new_fee_rate,
                        },
                    );
            }
        }

        /// @notice Internal function to handle withdrawals
        /// @param stream_id The ID of the stream to withdraw from
        /// @param amount The amount to withdraw
        /// @param to The address receiving the withdrawn tokens
        /// @return A tuple of (withdrawn_amount, protocol_fee_amount)
        fn _withdraw(
            ref self: ContractState, stream_id: u256, amount: u256, to: ContractAddress,
        ) -> (u128, u128) {
            assert(!to.is_zero(), INVALID_RECIPIENT);
            let mut stream = self.streams.read(stream_id);
            // @dev Allow stream creator to withdraw funds when a stream is canceled.
            if stream.sender != get_caller_address() {
                self.assert_is_recipient_or_delegate(stream_id);
            }

            // Stream creator can only withdraw when a stream is not paused
            if stream.sender == get_caller_address() {
                assert(stream.status != StreamStatus::Paused, STREAM_NOT_PAUSED);
            }

            if get_block_timestamp() > stream.end_time {
                stream.status = StreamStatus::Completed;
            }

            // Update snapshot before calculating withdrawable amount
            self._update_snapshot(stream_id);

            let withdrawable_amount = self._withdrawable_amount(stream_id);
            assert(withdrawable_amount >= amount, INSUFFICIENT_AMOUNT);
            assert(amount > 0, ZERO_AMOUNT);

            // Calculate fee using new fixed-point system
            let token_address = stream.token;
            let fee = self._calculate_protocol_fee(amount, token_address);
            let net_amount: u256 = (amount - fee);
            let current_balance = stream.balance - stream.withdrawn_amount;

            // Check if current balance is sufficient for withdrawal
            assert(current_balance >= amount, INSUFFICIENT_AMOUNT);

            // === REENTRANCY PROTECTION: Update ALL state before external calls ===

            // Update stream's withdrawn amount and balance
            stream.withdrawn_amount += amount;
            stream.balance -= amount;
            self.streams.write(stream_id, stream);

            // Update aggregate balance
            let aggregate_balance = self.aggregate_balance.read(token_address) - amount;
            self.aggregate_balance.write(token_address, aggregate_balance);

            // Update snapshot after withdrawal
            self._update_snapshot(stream_id);

            // Update stream metrics
            let mut metrics = self.stream_metrics.read(stream_id);
            metrics.total_withdrawn += amount;
            metrics.withdrawal_count += 1;
            metrics.last_activity = get_block_timestamp();
            self.stream_metrics.write(stream_id, metrics);

            // === ALL STATE UPDATES COMPLETE - NOW SAFE TO MAKE EXTERNAL CALLS ===

            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

            self.collect_protocol_fee(token_address, fee);
            token_dispatcher.transfer(to, net_amount);

            self
                .emit(
                    StreamWithdrawn {
                        stream_id,
                        recipient: to,
                        amount: net_amount,
                        protocol_fee: fee.try_into().unwrap(),
                    },
                );

            (net_amount.try_into().unwrap(), fee.try_into().unwrap())
        }

        /// @notice Internal function to handle refunds to stream creator
        /// @param stream_id The ID of the stream to refund from
        /// @param amount The amount to refund
        fn _refund(ref self: ContractState, stream_id: u256, amount: u256) {
            let stream = self.streams.read(stream_id);
            let token_address = stream.token;
            let sender = stream.sender;

            // === REENTRANCY PROTECTION: Update state before external calls ===

            // Update aggregate balance
            let aggregate_balance = self.aggregate_balance.read(token_address) - amount;
            self.aggregate_balance.write(token_address, aggregate_balance);

            // === STATE UPDATES COMPLETE - NOW SAFE TO MAKE EXTERNAL CALLS ===

            // Transfer tokens back to sender
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            token_dispatcher.transfer(sender, amount);

            // Emit event
            self.emit(RefundFromStream { stream_id, sender, amount });
        }
    }

    #[abi(embed_v0)]
    impl PaymentStreamImpl of IPaymentStream<ContractState> {
        /// @notice Creates a new stream and funds it with tokens in a single transaction
        /// @dev Combines the create_stream and deposit functions into one efficient operation
        fn create_stream(
            ref self: ContractState,
            recipient: ContractAddress,
            total_amount: u256,
            duration: u64,
            cancelable: bool,
            token: ContractAddress,
            transferable: bool,
        ) -> u256 {
            // Check token allowance first to avoid creating a stream we can't fund
            let caller = get_caller_address();
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let allowance = token_dispatcher.allowance(caller, get_contract_address());

            // Ensure we have enough allowance for the deposit
            assert(allowance >= total_amount, INSUFFICIENT_ALLOWANCE);

            // Now create the stream as we know we have sufficient allowance
            let stream_id = self
                ._create_stream(recipient, total_amount, duration, cancelable, token, transferable);

            // Transfer the tokens from the sender to the contract
            self._deposit(stream_id, total_amount);

            stream_id
        }

        // fn deposit(ref self: ContractState, stream_id: u256, amount: u256) {
        //     // Call the internal deposit function
        //     self._deposit(stream_id, amount);
        // }

        // fn deposit_and_pause(ref self: ContractState, stream_id: u256, amount: u256) {
        //     // First deposit additional funds
        //     self._deposit(stream_id, amount);

        //     // Then pause the stream
        //     self.pause(stream_id);
        // }

        fn withdraw(
            ref self: ContractState, stream_id: u256, amount: u256, to: ContractAddress,
        ) -> (u128, u128) {
            self.reentrancy_guard.start();
            let result = self._withdraw(stream_id, amount, to);
            self.reentrancy_guard.end();
            result
        }

        fn withdraw_max(
            ref self: ContractState, stream_id: u256, to: ContractAddress,
        ) -> (u128, u128) {
            self.reentrancy_guard.start();
            let withdrawable_amount = self._withdrawable_amount(stream_id);
            let result = self._withdraw(stream_id, withdrawable_amount, to);
            self.reentrancy_guard.end();
            result
        }

        fn transfer_stream(
            ref self: ContractState, stream_id: u256, new_recipient: ContractAddress,
        ) {
            self.reentrancy_guard.start();
            
            // Verify stream exists
            self.assert_stream_exists(stream_id);

            // Verify the caller is the stream recipient
            self.assert_is_recipient(stream_id);

            // Verify the stream is transferable
            self.assert_is_transferable(stream_id);

            // Verify valid new recipient
            assert(new_recipient.is_non_zero(), INVALID_RECIPIENT);

            // Get current stream details
            let mut stream = self.streams.read(stream_id);

            // Update recipient
            stream.recipient = new_recipient;

            // Save updated stream
            self.streams.write(stream_id, stream);

            // Transfer the NFT to the new recipient
            let current_owner = self.erc721.owner_of(stream_id);
            self.erc721.transfer(current_owner, new_recipient, stream_id);

            // Emit event about stream transfer
            self.emit(StreamTransferred { stream_id, new_recipient });
            
            self.reentrancy_guard.end();
        }

        fn set_transferability(ref self: ContractState, stream_id: u256, transferable: bool) {
            // Verify stream exists
            self.assert_stream_exists(stream_id);

            // Verify the caller is the stream owner (sender)
            self.assert_is_sender(stream_id);

            // Get current stream details
            let mut stream = self.streams.read(stream_id);

            // Update transferability if it's different from current setting
            if stream.transferable != transferable {
                stream.transferable = transferable;
            }
            // Save updated stream
            self.streams.write(stream_id, stream);

            // Emit event about transferability change
            self.emit(StreamTransferabilitySet { stream_id, transferable });
        }

        fn update_fee_collector(ref self: ContractState, new_fee_collector: ContractAddress) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            let fee_collector = self.fee_collector.read();
            assert(!new_fee_collector.is_zero(), INVALID_RECIPIENT);
            assert(new_fee_collector != fee_collector, SAME_COLLECTOR_ADDRESS);

            self.fee_collector.write(new_fee_collector);
            self.emit(FeeCollectorUpdated { new_fee_collector, old_fee_collector: fee_collector });
        }

        fn update_protocol_owner(ref self: ContractState, new_protocol_owner: ContractAddress) {
            let current_owner = self.protocol_owner.read();
            assert(!new_protocol_owner.is_zero(), INVALID_RECIPIENT);
            assert(new_protocol_owner != current_owner, SAME_OWNER);

            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            self.protocol_owner.write(new_protocol_owner);

            self.accesscontrol.revoke_role(PROTOCOL_OWNER_ROLE, current_owner);
            self.accesscontrol._grant_role(PROTOCOL_OWNER_ROLE, new_protocol_owner);
            self
                .emit(
                    ProtocolOwnerUpdated { new_protocol_owner, old_protocol_owner: current_owner },
                );
        }

        fn get_fee_collector(self: @ContractState) -> ContractAddress {
            self.fee_collector.read()
        }

        fn pause(ref self: ContractState, stream_id: u256) {
            // Ensure the caller is the stream sender
            self.assert_stream_sender_access(stream_id);
            let mut stream = self.streams.read(stream_id);

            self.assert_stream_exists(stream_id);
            assert(stream.status != StreamStatus::Canceled, STREAM_NOT_ACTIVE);

            // Only decrement counter if stream was active
            if stream.status == StreamStatus::Active {
                let protocol_metrics = self.protocol_metrics.read();
                self
                    .protocol_metrics
                    .write(
                        ProtocolMetrics {
                            total_active_streams: protocol_metrics.total_active_streams - 1,
                            total_tokens_to_stream: protocol_metrics.total_tokens_to_stream,
                            total_streams_created: protocol_metrics.total_streams_created,
                            total_delegations: protocol_metrics.total_delegations,
                        },
                    );
            }

            // Update snapshot BEFORE pausing to capture debt up to pause time
            self._update_snapshot(stream_id);

            // Store the current rate before pausing
            self.paused_rates.write(stream_id, stream.rate_per_second);

            // Update the last update time to current block timestamp
            stream.last_update_time = get_block_timestamp();
            let pause_time = stream.last_update_time;

            // Set rate to zero and update status
            stream.rate_per_second = 0_u64.into();
            stream.status = StreamStatus::Paused;
            self.streams.write(stream_id, stream);

            // Update stream metrics
            let mut metrics = self.stream_metrics.read(stream_id);
            metrics.pause_count += 1;
            metrics.last_activity = get_block_timestamp();
            self.stream_metrics.write(stream_id, metrics);

            self.emit(StreamPaused { stream_id, pause_time: pause_time });
        }

        fn cancel(ref self: ContractState, stream_id: u256) {
            self.reentrancy_guard.start();
            
            // Ensure the caller is the stream sender
            self.assert_stream_sender_access(stream_id);

            // Retrieve the stream
            let mut stream = self.streams.read(stream_id);

            let stream_balance = stream.balance;
            let token_address = stream.token;
            let recipient = stream.recipient;

            // Ensure the stream is active before cancellation
            self.assert_stream_exists(stream_id);

            // Only decrement counter if stream was active
            if stream.status == StreamStatus::Active {
                let protocol_metrics = self.protocol_metrics.read();
                self
                    .protocol_metrics
                    .write(
                        ProtocolMetrics {
                            total_active_streams: protocol_metrics.total_active_streams - 1,
                            total_tokens_to_stream: protocol_metrics.total_tokens_to_stream,
                            total_streams_created: protocol_metrics.total_streams_created,
                            total_delegations: protocol_metrics.total_delegations,
                        },
                    );
            }

            // Update snapshot before calculations
            self._update_snapshot(stream_id);

            // Calculate total debt (amount streamed but not withdrawn)
            let total_debt = self._total_debt(stream_id);

            // Calculate amounts for recipient and sender
            let amount_due_to_recipient = if total_debt > stream.withdrawn_amount {
                total_debt - stream.withdrawn_amount
            } else {
                0_u256
            };

            let refundable_amount = if stream_balance > total_debt {
                stream_balance - total_debt
            } else {
                0_u256
            };

            // === REENTRANCY PROTECTION: Update ALL state before external calls ===

            // Update the stream status to canceled
            stream.status = StreamStatus::Canceled;

            // Update stream balance and withdrawn amount
            if amount_due_to_recipient > 0 {
                stream.withdrawn_amount += amount_due_to_recipient;
                stream.balance -= amount_due_to_recipient;
            }

            // Update aggregate balance
            let total_amount_to_transfer = amount_due_to_recipient + refundable_amount;
            if total_amount_to_transfer > 0 {
                let aggregate_balance = self.aggregate_balance.read(token_address)
                    - total_amount_to_transfer;
                self.aggregate_balance.write(token_address, aggregate_balance);
            }

            // Update stream metrics for recipient payment
            if amount_due_to_recipient > 0 {
                let mut metrics = self.stream_metrics.read(stream_id);
                metrics.total_withdrawn += amount_due_to_recipient;
                metrics.withdrawal_count += 1;
                metrics.last_activity = get_block_timestamp();
                self.stream_metrics.write(stream_id, metrics);
            }

            // Update final snapshot
            self._update_snapshot(stream_id);

            let stream_sender = stream.sender;

            // Write updated stream state
            self.streams.write(stream_id, stream);

            // Burn the NFT
            self.erc721.burn(stream_id);

            // === ALL STATE UPDATES COMPLETE - NOW SAFE TO MAKE EXTERNAL CALLS ===

            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };

            // Pay recipient their due amount (with protocol fee)
            if amount_due_to_recipient > 0 {
                let fee = self._calculate_protocol_fee(amount_due_to_recipient, token_address);
                let net_amount = amount_due_to_recipient - fee;

                // Transfer fee to collector and net amount to recipient
                self.collect_protocol_fee(token_address, fee);
                token_dispatcher.transfer(recipient, net_amount);

                // Emit withdrawal event
                self
                    .emit(
                        StreamWithdrawn {
                            stream_id,
                            recipient,
                            amount: net_amount,
                            protocol_fee: fee.try_into().unwrap(),
                        },
                    );
            }

            // Refund excess to sender
            if refundable_amount > 0 {
                token_dispatcher.transfer(stream_sender, refundable_amount);
                self
                    .emit(
                        RefundFromStream {
                            stream_id, sender: stream_sender, amount: refundable_amount,
                        },
                    );
            }

            // Emit cancellation event
            self.emit(StreamCanceled { stream_id });
            
            self.reentrancy_guard.end();
        }

        fn restart(ref self: ContractState, stream_id: u256) {
            // Ensure the caller is the stream sender
            self.assert_stream_sender_access(stream_id);
            let mut stream = self.streams.read(stream_id);

            self.assert_stream_exists(stream_id);
            assert(stream.status != StreamStatus::Canceled, STREAM_NOT_ACTIVE);

            // Only increment counter if stream was paused
            assert(stream.status == StreamStatus::Paused, STREAM_NOT_PAUSED);

            let protocol_metrics = self.protocol_metrics.read();
            self
                .protocol_metrics
                .write(
                    ProtocolMetrics {
                        total_active_streams: protocol_metrics.total_active_streams + 1,
                        total_tokens_to_stream: protocol_metrics.total_tokens_to_stream,
                        total_streams_created: protocol_metrics.total_streams_created,
                        total_delegations: protocol_metrics.total_delegations,
                    },
                );

            // Get the stored rate from when the stream was paused
            let stored_rate = self.paused_rates.read(stream_id);

            // Update stream with new rate, status, and current timestamp
            stream.rate_per_second = stored_rate;
            stream.status = StreamStatus::Active;
            stream.last_update_time = get_block_timestamp();
            self.streams.write(stream_id, stream);

            // Clear the stored rate
            self.paused_rates.write(stream_id, 0_u64.into());

            self.emit(StreamRestarted { stream_id, rate_per_second: stored_rate });
        }

        fn get_stream(self: @ContractState, stream_id: u256) -> Stream {
            self.streams.read(stream_id)
        }

        fn get_withdrawable_amount(self: @ContractState, stream_id: u256) -> u256 {
            self._withdrawable_amount(stream_id)
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
            let stream = self.streams.read(stream_id);

            // If stream is not active or has no rate, return 0
            if stream.status != StreamStatus::Active || stream.rate_per_second == 0_u256 {
                return 0_u64;
            }

            // return the difference between the first_update_time and the current time
            let current_time = get_block_timestamp();
            let first_update_time = stream.start_time;
            let time_since_first_update = current_time - first_update_time;
            let time_specified = stream.duration * SECONDS_PER_HOUR;
            let time_remaining = time_specified - time_since_first_update;
            return time_remaining;
        }

        fn get_token_decimals(self: @ContractState, stream_id: u256) -> u8 {
            self.streams.read(stream_id).token_decimals
        }

        fn get_total_debt(self: @ContractState, stream_id: u256) -> u256 {
            self._total_debt(stream_id)
        }

        fn get_uncovered_debt(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            let total_debt = self._total_debt(stream_id);

            // If total debt is greater than balance, return the difference
            // Otherwise return 0 (all debt is covered)
            if total_debt > stream.balance {
                total_debt - stream.balance
            } else {
                0_u256
            }
        }

        fn get_covered_debt(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            let total_debt = self._total_debt(stream_id);

            // If balance is greater than total debt, all debt is covered
            // Otherwise, the balance amount is covered
            if stream.balance >= total_debt {
                total_debt
            } else {
                stream.balance
            }
        }

        // fn get_refundable_amount(self: @ContractState, stream_id: u256) -> u256 {
        //     let stream = self.streams.read(stream_id);

        //     // If stream is not active, return 0
        //     if stream.status != StreamStatus::Active {
        //         return 0_u256;
        //     }

        //     // Calculate total debt (amount streamed but not withdrawn)
        //     let total_debt = self._total_debt(stream_id);

        //     // Calculate refundable amount as the excess balance after accounting for debt
        //     if stream.balance > total_debt {
        //         stream.balance - total_debt
        //     } else {
        //         0_u256
        //     }
        // }

        fn get_active_streams_count(self: @ContractState) -> u256 {
            self.protocol_metrics.read().total_active_streams
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
            assert(delegate.is_non_zero(), INVALID_RECIPIENT);

            // Check NFT ownership instead of recipient field
            let nft_owner = self.erc721.owner_of(stream_id);
            assert(nft_owner == get_caller_address(), ONLY_NFT_OWNER_CAN_DELEGATE);

            let current_delegate = self.stream_delegates.read(stream_id);
            assert(current_delegate.is_zero(), STREAM_HAS_DELEGATE);

            self.stream_delegates.write(stream_id, delegate);
            self.delegation_history.entry(stream_id).push(delegate);

            // Update stream metrics
            let mut metrics = self.stream_metrics.read(stream_id);
            metrics.total_delegations += 1;
            metrics.current_delegate = delegate;
            metrics.last_delegation_time = get_block_timestamp();
            metrics.last_activity = get_block_timestamp();
            self.stream_metrics.write(stream_id, metrics);

            // Update protocol metrics
            let mut protocol_metrics = self.protocol_metrics.read();
            protocol_metrics.total_delegations += 1;
            self.protocol_metrics.write(protocol_metrics);

            self.emit(DelegationGranted { stream_id, delegator: get_caller_address(), delegate });
            true
        }

        fn revoke_delegation(ref self: ContractState, stream_id: u256) -> bool {
            self.assert_stream_exists(stream_id);
            self.assert_is_recipient(stream_id);
            let delegate = self.stream_delegates.read(stream_id);
            assert(delegate.is_non_zero(), UNEXISTING_STREAM);
            self.stream_delegates.write(stream_id, 0.try_into().unwrap());
            self.emit(DelegationRevoked { stream_id, delegator: get_caller_address(), delegate });
            true
        }

        fn get_stream_delegate(self: @ContractState, stream_id: u256) -> ContractAddress {
            self.stream_delegates.read(stream_id)
        }

        fn is_stream(self: @ContractState, stream_id: u256) -> bool {
            let stream: Stream = self.streams.read(stream_id);
            if stream.status == StreamStatus::Active {
                return true;
            }
            false
        }

        fn is_paused(self: @ContractState, stream_id: u256) -> bool {
            let stream: Stream = self.streams.read(stream_id);
            if stream.status == StreamStatus::Paused {
                return true;
            }
            false
        }

        fn get_sender(self: @ContractState, stream_id: u256) -> ContractAddress {
            let stream: Stream = self.streams.read(stream_id);

            return stream.sender;
        }

        fn get_recipient(self: @ContractState, stream_id: u256) -> ContractAddress {
            self.erc721.owner_of(stream_id)
        }

        fn get_token(self: @ContractState, stream_id: u256) -> ContractAddress {
            let stream: Stream = self.streams.read(stream_id);

            return stream.token;
        }

        fn get_rate_per_second(self: @ContractState, stream_id: u256) -> u256 {
            let stream = self.streams.read(stream_id);
            let scaled_rate = stream.rate_per_second.into();
            // Convert from scaled rate back to actual rate per second for user-facing API
            scaled_rate / PRECISION_SCALE
        }

        fn get_aggregate_balance(self: @ContractState, token: ContractAddress) -> u256 {
            self.aggregate_balance.read(token)
        }

        fn recover(ref self: ContractState, token: ContractAddress, to: ContractAddress) -> u256 {
            assert(!to.is_zero(), INVALID_RECIPIENT);
            assert(!token.is_zero(), INVALID_TOKEN);
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);

            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let surplus = token_dispatcher.balance_of(get_contract_address())
                - self.aggregate_balance.read(token);

            assert(surplus > 0, ZERO_AMOUNT);

            token_dispatcher.transfer(to, surplus);

            self.emit(Recover { sender: get_contract_address(), to, surplus });

            surplus
        }

        /// @notice Sets the protocol fee rate for a specific token
        /// @param token The token address to set the fee rate for
        /// @param new_fee_rate The new fee rate in basis points (e.g., 100 = 1%)
        fn set_protocol_fee_rate(
            ref self: ContractState, token: ContractAddress, new_fee_rate: u64,
        ) {
            self._set_protocol_fee_rate(token, new_fee_rate);
        }

        /// @notice Gets the protocol fee rate for a specific token
        /// @param token The token address to get the fee rate for
        /// @return The current fee rate in basis points
        fn get_protocol_fee_rate(self: @ContractState, token: ContractAddress) -> u64 {
            self.protocol_fee_rate.read(token)
        }

        fn set_general_protocol_fee_rate(
            ref self: ContractState, new_general_protocol_fee_rate: u64,
        ) {
            self.general_protocol_fee_rate.write(new_general_protocol_fee_rate);
            self
                .emit(
                    GeneralProtocolFeeSet {
                        set_by: get_caller_address(), new_fee: new_general_protocol_fee_rate,
                    },
                );
        }

        fn get_general_protocol_fee_rate(self: @ContractState) -> u64 {
            self.general_protocol_fee_rate.read()
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(PROTOCOL_OWNER_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }
}
