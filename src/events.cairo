// Event Documentation

// These events are designed to track payment stream life cycle.  Let's analyze the structure and
// implementation of the events;

// Event Structure
// The events are structured into enum that tracks all the major stream operations as follows;

#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    StreamCreated: StreamCreated,
    StreamWithdrawn: StreamWithdrawn,
    StreamCanceled: StreamCanceled,
    StreamPaused: StreamPaused,
    StreamRestarted: StreamRestarted,
    StreamVoided: StreamVoided,
}

// The various event variants link to distinct lifecycle events for streams
// while keeping stream_id as the essential indexed parameter.
// The design structure facilitates both stream event filtering processes and stream event tracking
// operations.

// Event Implementation Details

// 1. StreamCreated Event

#[derive(Drop, starknet::Event)]
struct StreamCreated {
    #[key]
    stream_id: u256,
    sender: ContractAddress,
    recipient: ContractAddress,
    total_amount: u256,
    token: ContractAddress,
}

// The stream creation triggers this event.
// Includes all essential stream parameters
// The database indexes the event queries through the stream_id parameter for fast retrieval.

#[derive(Drop, starknet::Event)]
struct StreamWithdrawn {
    #[key]
    stream_id: u256,
    recipient: ContractAddress,
    amount: u256,
    protocol_fee: u128,
}

// Tracks token withdrawals
// Includes protocol fee information
// Maintains consistent stream_id indexing

// Stream State Change Events

// StreamCanceled: Records stream cancellation with remaining balance
// StreamPaused: This records stream pause timing using Unix timestamp values.
// StreamRestarted: The stream restart event writes timestamp information in the log format.
// StreamVoided: This event enables users to store stream void records which include a reason for
// the void.

/// Evens Emision Patterns
/// When events are emitted, they follow specific patterns

// Example 1: Creating a stream
fn create_stream(
    ref self: ContractState,
    recipient: ContractAddress,
    total_amount: u256,
    start_time: u64,
    end_time: u64,
    cancelable: bool,
    token: ContractAddress,
    transferable: bool,
) -> u256 {
    // ... stream creation logic ...

    // Emit StreamCreated event
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

// Example 2: Withdrawing from a stream
fn withdraw(
    ref self: ContractState, stream_id: u256, amount: u256, to: ContractAddress,
) -> (u128, u128) {
    // ... withdrawal logic ...

    // Emit StreamWithdrawn event
    self
        .emit(
            Event::StreamWithdrawn(
                StreamWithdrawn {
                    stream_id, recipient: to, amount: net_amount, protocol_fee: fee_into_u128,
                },
            ),
        );

    (net_amount_into_u128, fee_into_u128)
}
