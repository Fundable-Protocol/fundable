/// Error messages for the Distributor contract
pub mod Errors {
    /// Thrown when attempting to create a stream or distribution with an empty recipients array
    pub const EMPTY_RECIPIENTS: felt252 = 'Error: Recipients array empty.';

    /// Thrown when the provided recipient address is invalid (e.g. zero address)
    pub const INVALID_RECIPIENT: felt252 = 'Error: Invalid recipient.';

    /// Thrown when an operation is attempted by someone who is not the intended recipient of the
    /// stream
    pub const WRONG_RECIPIENT: felt252 = 'Error: Not stream recipient.';

    /// Thrown when an operation is attempted by someone who is not the sender/creator of the stream
    pub const WRONG_SENDER: felt252 = 'Error: Not stream sender.';

    /// Thrown when attempting to create a stream or make a payment with zero tokens
    pub const ZERO_AMOUNT: felt252 = 'Error: Amount must be > 0.';

    /// Thrown when the contract does not have sufficient allowance to transfer tokens on behalf of
    /// the sender
    pub const INSUFFICIENT_ALLOWANCE: felt252 = 'Error: Insufficient allowance.';

    /// Thrown when an invalid or unsupported token address is provided
    pub const INVALID_TOKEN: felt252 = 'Error: Invalid token address.';

    /// Thrown when the lengths of recipients and amounts arrays do not match in batch operations
    pub const ARRAY_LEN_MISMATCH: felt252 = 'Error: Arrays length mismatch.';

    /// Thrown when trying to interact with a stream that does not exist or has been deleted
    pub const UNEXISTING_STREAM: felt252 = 'Error: Stream does not exist.';

    /// Thrown when attempting to create a stream where the end time is before the start time
    pub const END_BEFORE_START: felt252 = 'Error: End time < start time.';

    /// Thrown when a too low duration is provided.
    pub const TOO_SHORT_DURATION: felt252 = 'Error: Duration is too short';


    /// Thrown when token decimals > 18
    pub const DECIMALS_TOO_HIGH: felt252 = 'Error: Decimals too high.';

    /// Thrown when a protocol address is not set
    pub const PROTOCOL_FEE_ADDRESS_NOT_SET: felt252 = 'Error: Zero Protocol address';

    /// Thrown when wrong recipient or delegate
    pub const WRONG_RECIPIENT_OR_DELEGATE: felt252 = 'WRONG_RECIPIENT_OR_DELEGATE';
}

