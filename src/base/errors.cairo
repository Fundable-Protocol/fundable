/// Error messages for the Distributor contract
pub mod Errors {
    /// Thrown when attempting to create a stream or distribution with an empty recipients array
    pub const EMPTY_RECIPIENTS: felt252 = 'Error: Recipients array empty.';

    /// Thrown when amount is not enough
    pub const INSUFFICIENT_AMOUNT: felt252 = 'Error: Insufficient amount.';

    /// Thrown when the provided recipient address is invalid (e.g. zero address)
    pub const INVALID_RECIPIENT: felt252 = 'Error: Invalid recipient.';

    /// Thrown when an operation is attempted by someone who is not the intended recipient of the
    /// stream
    pub const WRONG_RECIPIENT: felt252 = 'Error: Not stream recipient.';

    /// Thrown when an operation is attempted by someone who is not the sender/creator of the stream
    pub const WRONG_SENDER: felt252 = 'Error: Not stream sender.';

    /// Thrown when attempting to create a stream or make a payment with zero tokens
    pub const ZERO_AMOUNT: felt252 = 'Error: Amount must be > 0.';

    /// Thrown when a stream is not transferable.
    pub const NON_TRANSFERABLE_STREAM: felt252 = 'Error: Non-transferrable stream';

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

    /// Thrown when campaign ref exists
    pub const CAMPAIGN_REF_EXISTS: felt252 = 'Error: Campaign Ref Exists';

    /// Thrown when campaign ref is emptu
    pub const CAMPAIGN_REF_EMPTY: felt252 = 'Error: Campaign Ref Is Required';

    /// Thrown when donating zero amount to a campaign
    pub const CANNOT_DENOTE_ZERO_AMOUNT: felt252 = 'Error: Cannot donate nothing';

    // Throw Error when campaign target has reached
    pub const TARGET_REACHED: felt252 = 'Error: Target Reached';

    // Throw Error when target is not campaign owner
    pub const CALLER_NOT_CAMPAIGN_OWNER: felt252 = 'Caller is Not Campaign Owner';

    // Throw Error when campaign target has not reached
    pub const TARGET_NOT_REACHED: felt252 = 'Error: Target Not Reached';

    pub const MORE_THAN_TARGET: felt252 = 'Error: More than Target';

    pub const CAMPAIGN_NOT_CLOSED: felt252 = 'Error: Campaign not closed';

    pub const DOUBLE_WITHDRAWAL: felt252 = 'Error: Double Withdrawal';

    pub const ZERO_ALLOWANCE: felt252 = 'Error: Zero allowance found';

    pub const WITHDRAWAL_FAILED: felt252 = 'Error: Withdraw failed';
}

