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
    /// FIXED: Shortened to fit felt252 (31 char limit)
    pub const ZERO_AMOUNT: felt252 = 'Error: Zero amount not allowed';

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

    /// Thrown when stream is not active
    pub const STREAM_NOT_ACTIVE: felt252 = 'Stream is not active';

    /// Thrown when stream is voided
    pub const STREAM_VOIDED: felt252 = 'Stream is voided';

    /// Thrown when stream is canceled
    pub const STREAM_CANCELED: felt252 = 'Stream is canceled';

    /// Thrown when fee is too high
    pub const FEE_TOO_HIGH: felt252 = 'fee too high';

    /// Thrown when fee percentage is invalid
    pub const INVALID_FEE_PERCENTAGE: felt252 = 'invalid fee percentage';

    /// Thrown when collector address is the same
    pub const SAME_COLLECTOR_ADDRESS: felt252 = 'same collector address';

    /// Thrown when current owner is the same as new owner
    pub const SAME_OWNER: felt252 = 'current owner == new_owner';

    /// Thrown when only NFT owner can delegate
    pub const ONLY_NFT_OWNER_CAN_DELEGATE: felt252 = 'Only the NFT owner can delegate';

    /// Thrown when stream already has a delegate
    pub const STREAM_HAS_DELEGATE: felt252 = 'Stream already has a delegate';

    // Thrown when stream is not paused
    pub const STREAM_NOT_PAUSED: felt252 = 'Stream is not paused';

    /// Thrown when campaign ref exists
    pub const CAMPAIGN_REF_EXISTS: felt252 = 'Error: Campaign Ref Exists';

    /// Thrown when campaign ref is empty
    pub const CAMPAIGN_REF_EMPTY: felt252 = 'Error: Campaign Ref Is Required';

    /// Thrown when donating zero amount to a campaign
    /// FIXED: Shortened to fit felt252 (31 char limit)
    pub const CANNOT_DENOTE_ZERO_AMOUNT: felt252 = 'Error: Cannot denote zero amt';

    // Throw Error when campaign target has reached
    /// FIXED: Shortened to fit felt252 (31 char limit)
    pub const TARGET_REACHED: felt252 = 'Error: Target already reached';

    // Throw Error when target is not campaign owner
    pub const CALLER_NOT_CAMPAIGN_OWNER: felt252 = 'Caller is Not Campaign Owner';

    // Throw Error when campaign target has not reached
    pub const TARGET_NOT_REACHED: felt252 = 'Error: Target Not Reached';

    pub const MORE_THAN_TARGET: felt252 = 'Error: More than Target';

    pub const CAMPAIGN_NOT_CLOSED: felt252 = 'Error: Campaign not closed';

    pub const CAMPAIGN_NOT_CANCELLED: felt252 = 'Error: Campaign not cancelled';

    pub const CAMPAIGN_CLOSED: felt252 = 'Error: Campaign closed';

    pub const CAMPAIGN_HAS_DONATIONS: felt252 = 'Error: Campaign has donations';

    /// FIXED: Shortened to fit felt252 (31 char limit)
    pub const DOUBLE_WITHDRAWAL: felt252 = 'Error: Double withdrawal';

    pub const CAMPAIGN_WITHDRAWN: felt252 = 'Error: Campaign Withdrawn';

    pub const ZERO_ALLOWANCE: felt252 = 'Error: Zero allowance found';

    pub const WITHDRAWAL_FAILED: felt252 = 'Error: Withdraw failed';

    /// Thrown when an operation leads to an overflow
    pub const OPERATION_OVERFLOW: felt252 = 'Error: Operation overflow';

    pub const CAMPAIGN_NOT_FOUND: felt252 = 'Error: Campaign Not Found';

    pub const REFUND_ALREADY_CLAIMED: felt252 = 'Error: Refund already claimed';

    pub const DONATION_NOT_FOUND: felt252 = 'Error: Donation not found';

    // ======================================
    // BATCH DONATION ERRORS - ALL SHORTENED
    // ======================================

    /// Thrown when batch donation array is empty
    pub const EMPTY_CAMPAIGN_ARRAY: felt252 = 'Empty campaign array';

    /// Thrown when batch donation array exceeds maximum size
    pub const BATCH_SIZE_TOO_LARGE: felt252 = 'Batch size too large';

    /// Thrown when donor has insufficient balance for batch donation
    pub const INSUFFICIENT_BALANCE: felt252 = 'Insufficient balance';

    /// Thrown when amount in batch donation must be positive
    pub const AMOUNT_MUST_BE_POSITIVE: felt252 = 'Amount must be > 0';

    /// Thrown when campaign does not exist in batch donation
    pub const CAMPAIGN_DOES_NOT_EXIST: felt252 = 'Campaign does not exist';

    /// Thrown when campaign is closed in batch donation
    pub const CAMPAIGN_IS_CLOSED: felt252 = 'Campaign is closed';

    /// Thrown when campaign goal is already reached in batch donation
    pub const CAMPAIGN_GOAL_REACHED: felt252 = 'Campaign goal reached';

    /// Thrown when amount calculation overflows
    pub const AMOUNT_OVERFLOW: felt252 = 'Amount overflow';

    /// Thrown when total calculation overflows
    pub const TOTAL_OVERFLOW: felt252 = 'Total overflow';

    /// Thrown when token transfer fails in batch donation
    pub const TRANSFER_FAILED: felt252 = 'Transfer failed';

    /// Thrown when total amount must be positive
    pub const TOTAL_AMOUNT_POSITIVE: felt252 = 'Total amount must be > 0';

    // ======================================
    // NFT ERRORS - ALL SHORTENED
    // ======================================

    /// Thrown when caller is not the donor for NFT minting
    pub const CALLER_NOT_DONOR: felt252 = 'Caller is not the donor';

    /// Thrown when NFT is already minted for a donation
    pub const NFT_ALREADY_MINTED: felt252 = 'NFT already minted';

    /// Thrown when donation data is not found for NFT
    pub const DONATION_DATA_NOT_FOUND: felt252 = 'Donation data not found';

    /// Thrown when NFT contract is not configured
    pub const NFT_CONTRACT_NOT_SET: felt252 = 'NFT contract not configured';
}
