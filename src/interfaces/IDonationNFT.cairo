use starknet::ContractAddress;
use crate::base::types::DonationMetadata;


#[starknet::interface]
pub trait IDonationNFT<TContractState> {
    fn mint_receipt(
        ref self: TContractState, to: ContractAddress, donation_data: DonationMetadata,
    ) -> u256;
    fn get_donation_data(self: @TContractState, token_id: u256) -> DonationMetadata;
}
