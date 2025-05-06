use fp::UFixedPoint123x128;
use starknet::ContractAddress;

/// @notice Struct containing all data for a single stream
#[derive(Drop, Serde, starknet::Store)]
pub struct Stream {
    pub sender: ContractAddress,
    pub recipient: ContractAddress,
    pub total_amount: u256,
    pub withdrawn_amount: u256,
    pub duration: u64,
    pub cancelable: bool,
    pub token: ContractAddress,
    pub token_decimals: u8,
    pub balance: u256,
    pub status: StreamStatus,
    pub rate_per_second: UFixedPoint123x128,
    pub last_update_time: u64,
    pub transferable: bool,
}

#[derive(Drop, starknet::Event)]
pub struct Distribution {
    #[key]
    pub caller: ContractAddress,
    #[key]
    pub token: ContractAddress,
    #[key]
    pub amount: u256,
    #[key]
    pub recipients_count: u32,
}

#[derive(Drop, starknet::Event)]
pub struct WeightedDistribution {
    #[key]
    pub caller: ContractAddress,
    #[key]
    pub token: ContractAddress,
    #[key]
    pub recipient: ContractAddress,
    #[key]
    pub amount: u256,
}

/// @notice Enum representing the possible states of a stream
#[derive(Drop, Serde, starknet::Store, PartialEq)]
#[allow(starknet::store_no_default_variant)]
pub enum StreamStatus {
    Active, // Stream is actively streaming tokens
    Canceled, // Stream has been canceled by the sender
    Completed, // Stream has completed its full duration smart 
    Paused, // Stream is temporarily paused
    Voided // Stream has been permanently voided
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct TokenStats {
    pub total_amount: u256, // Total amount distributed for this token
    pub distribution_count: u256, // Number of distributions involving this token
    pub last_distribution_time: u64, // Timestamp of the last distribution for this token
    pub unique_recipients: u256 // Count of unique recipients
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct UserStats {
    pub distributions_initiated: u256, // Number of distributions initiated by the user
    pub total_amount_distributed: u256, // Total amount distributed by the user
    pub last_distribution_time: u64, // Timestamp of the last distribution by the user
    pub unique_tokens_used: u256 // Count of unique tokens used by the user
}

#[derive(Drop, Serde, starknet::Store)]
pub struct DistributionHistory {
    #[key]
    pub caller: ContractAddress,
    pub token: ContractAddress,
    pub amount: u256,
    pub recipients_count: u32,
    pub timestamp: u64,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct StreamMetrics {
    last_activity: u64,
    total_withdrawn: u256,
    withdrawal_count: u32,
    pause_count: u32,
    // delegation metrics
    total_delegations: u64,
    current_delegate: ContractAddress,
    last_delegation_time: u64,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct ProtocolMetrics {
    pub total_active_streams: u256,
    pub total_tokens_to_stream: u256,
    pub total_streams_created: u256,
    pub total_delegations: u64,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Campaigns {
    pub campaign_id: u256,
    pub owner: ContractAddress,
    pub target_amount: u256,
    pub current_amount: u256,
    pub asset: felt252,
    pub is_closed: bool,
    pub is_goal_reached: bool,
    pub campaign_reference: felt252,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Donations {
    pub donor: ContractAddress,
    pub campaign_id: u256,
    pub amount: u256,
    pub asset: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct CampaignWithdrawal {
    pub owner: ContractAddress,
    pub campaign_id: u256,
    pub amount: u256,
    pub asset: u256,
}

#[derive(Drop, Serde)]
pub struct Recipient {
    address: ContractAddress,
    name: felt252,
    amount: u256,
}

#[derive(Drop, Serde)]
pub struct DirectDeposit {
    name: felt252,
    token_address: ContractAddress,
    payment_date: u64,
    recipients: Array<Recipient>,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct DirectDepositPayment {
    recipient: ContractAddress,
    amount: u256,
    token_address: ContractAddress,
    payment_date: u64,
    direct_deposit_id: u256,
}

#[derive(Drop, Serde, starknet::Store)]
pub struct DirectDepositHistory {
    caller: ContractAddress,
    total_amount: u256,
    token_address: ContractAddress,
    number_of_recipient: u256,
    timestamp: u64,
}
