#[starknet::contract]
pub mod DonationNFT {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::base::types::DonationMetadata;
    use crate::interfaces::IDonationNFT::IDonationNFT;

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        owner: ContractAddress,
        donation_nfts: Map<(u256, u256), u256>, // (campaign_id, donation_id) -> token_id
        nft_minted: Map<(u256, u256), bool>, // (campaign_id, donation_id) -> minted status
        token_id_metadata: Map<u256, DonationMetadata>, // token_id -> DonationMetadata
        token_id_count: u256, // Counter for token IDs
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ReceiptMinted: ReceiptMinted,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct ReceiptMinted {
        token_id: u256,
        to: ContractAddress,
        donation_data: DonationMetadata,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        let name: ByteArray = "Fundable Donation NFT Receipt";
        let symbol: ByteArray = "FDNR";
        let base_uri: ByteArray = "https://example.com/receipts/";
        // Initialize the owner of the contract
        self.owner.write(owner);
        // Initialize the ERC721 component
        self.erc721.initializer(name, symbol, base_uri);
    }

    #[abi(embed_v0)]
    impl DonationNFTImpl of IDonationNFT<ContractState> {
        fn mint_receipt(
            ref self: ContractState, to: ContractAddress, donation_data: DonationMetadata,
        ) -> u256 {
            // Ensure the caller is the owner of the contract
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only the owner can mint NFTs');
            // Check if the NFT has already been minted for this campaign and donation
            let (campaign_id, donation_id) = (donation_data.campaign_id, donation_data.donation_id);
            let check = self.nft_minted.entry((campaign_id, donation_id)).read();
            assert(!check, 'NFT already minted');
            let token_id = self.token_id_count.read() + 1;

            // Store the donation data and update the mappings
            self.donation_nfts.entry((campaign_id, donation_id)).write(token_id);
            self.nft_minted.entry((campaign_id, donation_id)).write(true);
            self.token_id_metadata.entry(token_id).write(donation_data);
            self.token_id_count.write(token_id);
            // Mint the NFT
            self.erc721.mint(to, token_id);
            // Emit the Donation NFT minting event
            self.emit(ReceiptMinted { token_id, to, donation_data: donation_data });
            token_id
        }
        fn get_donation_data(self: @ContractState, token_id: u256) -> DonationMetadata {
            // Retrieve the donation data associated with the token_id
            let donation_data = self.token_id_metadata.entry(token_id).read();
            assert(donation_data.campaign_id != 0, 'Donation data not found');
            donation_data
        }
    }
}
