use starknet::ContractAddress;

/// Interface for the distribution contract
#[starknet::interface]
pub trait IDirectDeposit<TContractState> {
    fn create_direct_deposit(
        ref self: TContractState,
        name: u256,
        recipients: Array<ContractAddress>,
        token_address: ContractAddress,
        payment_date: u64,
    );

    fn add_recipient(ref self: TContractState, recipient: ContractAddress, direct_deposit_id: u256);
    fn handle_direct_deposit_payment(ref self: TContractState, direct_deposit_id: u256);

    // READ FUNCTIONS
    fn get_direct_deposit(ref self: TContractState, direct_deposit_id: u256);
}
