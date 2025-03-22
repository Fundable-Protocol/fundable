use fp::UFixedPoint123x128;
use starknet::ContractAddress;
use crate::base::types::{ProtocolMetrics, Stream, StreamMetrics};

/// @title IPaymentStream
/// @notice Creates and manages payment streams with linear streaming functions.
#[starknet::interface]
pub trait IPaymentStream<TContractState> {
    /// @notice Creates a new stream by setting the start time and wrapping it in an NFT.
    /// @param recipient The address receiving the tokens
    /// @param total_amount The total amount to be streamed
    /// @param start_time The timestamp when the stream starts
    /// @param end_time The timestamp when the stream ends
    /// @param cancelable Boolean indicating if the stream can be canceled
    /// @param token The contract address of the ERC-20 token to be streamed
    /// @return The ID of the newly created stream
    fn create_stream(
        ref self: TContractState,
        recipient: ContractAddress,
        total_amount: u256,
        start_time: u64,
        end_time: u64,
        cancelable: bool,
        token: ContractAddress,
    ) -> u256;

    /// @notice Withdraws the provided amount minus the protocol fee to the provided address
    /// @param stream_id The ID of the stream to withdraw from
    /// @param amount The amount to withdraw
    /// @param to The address receiving the withdrawn tokens
    /// @return A tuple of (withdrawn_amount, protocol_fee_amount)
    fn withdraw(
        ref self: TContractState, stream_id: u256, amount: u256, to: ContractAddress,
    ) -> (u128, u128);

    /// @notice Withdraws the entire withdrawable amount minus the protocol fee
    /// @param stream_id The ID of the stream to withdraw from
    /// @param to The address receiving the withdrawn tokens
    /// @return A tuple of (withdrawn_amount, protocol_fee_amount)
    fn withdraw_max(ref self: TContractState, stream_id: u256, to: ContractAddress) -> (u128, u128);

    /// @notice withdraws protocol fee to the provided recipient
    /// @param amount Amount of fee to be withdrawn from fee holder
    /// @param recipient Receiver of the token withdrawn
    fn withdraw_protocol_fee(
        ref self: TContractState, recipient: ContractAddress, amount: u256, token: ContractAddress,
    );

    /// @notice withdraws total accumulated protocol fee to the provided recipient
    /// @param recipient Receiver of the token withdrawn
    fn withdraw_max_protocol_fee(
        ref self: TContractState, recipient: ContractAddress, token: ContractAddress,
    );

    /// @notice updates the percentage fee for the protocol
    /// @param new_percentage The new percentage fee to be collected
    fn update_percentage_protocol_fee(ref self: TContractState, new_percentage: u16);

    /// @notice updates the fee collector address
    /// @param new_fee_collector The new contract address to hold fees collected
    fn update_fee_collector(ref self: TContractState, new_fee_collector: ContractAddress);

    /// @notice updates the protocol owner address
    /// @param new_protocol_owner The new protocol owner's address
    fn update_protocol_owner(ref self: TContractState, new_protocol_owner: ContractAddress);

    /// @notice returns the fee collector address
    fn get_fee_collector(self: @TContractState) -> ContractAddress;

    /// @notice Cancels the stream
    /// @param stream_id The ID of the stream to cancel
    fn cancel(ref self: TContractState, stream_id: u256);

    /// @notice Pauses the stream
    /// @param stream_id The ID of the stream to pause
    fn pause(ref self: TContractState, stream_id: u256);

    /// @notice Restarts the stream with the provided rate per second
    /// @param stream_id The ID of the stream to restart
    /// @param rate_per_second The amount by which the debt increases every second
    fn restart(ref self: TContractState, stream_id: u256, rate_per_second: UFixedPoint123x128);

    /// @notice Voids a stream, making it permanently inactive
    /// @param stream_id The ID of the stream to void
    fn void(ref self: TContractState, stream_id: u256);

    /// @notice Returns the stream data for the given ID
    /// @param stream_id The stream ID for the query
    /// @return The Stream struct containing all stream data
    fn get_stream(self: @TContractState, stream_id: u256) -> Stream;

    /// @notice Calculates the amount that the recipient can withdraw
    /// @param stream_id The stream ID for the query
    /// @return The amount that can be withdrawn
    fn get_withdrawable_amount(self: @TContractState, stream_id: u256) -> u256;

    /// @notice Returns whether the stream is currently active
    /// @param stream_id The stream ID for the query
    /// @return Boolean indicating if the stream is active
    fn is_stream_active(self: @TContractState, stream_id: u256) -> bool;

    /// @notice Returns the time at which the total debt exceeds stream balance
    /// @param stream_id The stream ID for the query
    /// @return The timestamp when the stream will be depleted
    fn get_depletion_time(self: @TContractState, stream_id: u256) -> u64;

    /// @notice Returns the total amount owed by the sender to the recipient
    /// @param stream_id The stream ID for the query
    /// @return The total debt amount
    fn get_total_debt(self: @TContractState, stream_id: u256) -> u256;

    /// @notice Returns the amount of debt not covered by the stream balance
    /// @param stream_id The stream ID for the query
    /// @return The uncovered debt amount
    fn get_uncovered_debt(self: @TContractState, stream_id: u256) -> u256;

    /// @notice Returns the amount of debt covered by the stream balance
    /// @param stream_id The stream ID for the query
    /// @return The covered debt amount
    fn get_covered_debt(self: @TContractState, stream_id: u256) -> u256;

    /// @notice Returns the amount that the sender can be refunded
    /// @param stream_id The stream ID for the query
    /// @return The refundable amount
    fn get_refundable_amount(self: @TContractState, stream_id: u256) -> u256;

    /// @notice Returns the total number of currently active streams
    /// @return The count of active streams in the protocol
    fn get_active_streams_count(self: @TContractState) -> u256;

    /// @notice Returns the token decimals
    /// @params stream_id The unique identifier of the stream
    /// @return Token decimals
    fn get_token_decimals(self: @TContractState, stream_id: u256) -> u8;

    /// @notice Returns the total amount distributed for a specific token
    /// @param token The contract address of the token to query
    /// @return Total amount distributed for the specified token
    fn get_token_distribution(self: @TContractState, token: ContractAddress) -> u256;

    /// @notice Retrieves the analytics metrics for a specific stream
    /// @param stream_id The unique identifier of the stream
    /// @return StreamMetrics containing detailed stream analytics
    fn get_stream_metrics(self: @TContractState, stream_id: u256) -> StreamMetrics;

    /// @notice Retrieves overall protocol-level streaming metrics
    /// @return ProtocolMetrics containing comprehensive protocol analytics
    fn get_protocol_metrics(self: @TContractState) -> ProtocolMetrics;

    /// @notice Delegate a contract address to a stream
    /// @param stream_id The stream ID for the query
    /// @param delegate The address to delegate a stream to
    /// @return Boolean indicating if the stream delegation is successsful
    fn delegate_stream(
        ref self: TContractState, stream_id: u256, delegate: ContractAddress,
    ) -> bool;

    /// @notice Revoke a delegation on a stream
    /// @param stream_id The stream ID for the query
    /// @return Boolean indicating if the stream delegation is revoked
    fn revoke_delegation(ref self: TContractState, stream_id: u256) -> bool;

    /// @notice returns the delegated address from a stream
    fn get_stream_delegate(self: @TContractState, stream_id: u256) -> ContractAddress;

    /// @notice Updates the rate per second for the stream
    /// @param stream_id The ID of the stream to update
    /// @param new_rate_per_second The new rate per second for the stream
    fn update_stream_rate(
        ref self: TContractState, stream_id: u256, new_rate_per_second: UFixedPoint123x128,
    );
}
