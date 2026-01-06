#[cfg(test)]
mod test_consensual_cancel {
    use fundable::base::types::StreamStatus;
    use fundable::interfaces::IPaymentStream::{
        IPaymentStreamDispatcher, IPaymentStreamDispatcherTrait,
    };
    use fundable::payment_stream::PaymentStream::ConsensualCancel;
    use openzeppelin::account::interface::{ISRC6Dispatcher, ISRC6DispatcherTrait};
    use snforge_std::{
        ContractClassTrait, DeclareResultTrait, EventSpy, EventSpyAssertionsTrait, declare,
        mock_call, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
    };
    use starknet::{ContractAddress, contract_address_const};

    // Helper to setup the contract
    fn setup() -> (IPaymentStreamDispatcher, ContractAddress, ContractAddress, ContractAddress) {
        let contract = declare("PaymentStream").unwrap().contract_class();

        let protocol_owner = contract_address_const::<'owner'>();
        let fee_collector = contract_address_const::<'collector'>();
        let token = contract_address_const::<'token'>(); // Dummy token

        let mut calldata = ArrayTrait::new();
        protocol_owner.serialize(ref calldata);
        fee_collector.serialize(ref calldata);
        // general_protocol_fee_rate = 0
        0_u64.serialize(ref calldata);

        let (contract_address, _) = contract.deploy(@calldata).unwrap();
        let dispatcher = IPaymentStreamDispatcher { contract_address };

        (dispatcher, protocol_owner, fee_collector, token)
    }

    #[test]
    fn test_consensual_cancel_sender_initiated() {
        let (dispatcher, _owner, _collector, token) = setup();

        let stream_id = 1_u256;
        let sender = contract_address_const::<'sender'>();
        let recipient = contract_address_const::<'recipient'>();

        mock_call(token, selector!("transferFrom"), true, 1);
        mock_call(token, selector!("transfer"), true, 1);
        mock_call(token, selector!("balanceOf"), 1000_u256, 1);
        mock_call(token, selector!("allowance"), 1000_u256, 1);

        start_cheat_caller_address(dispatcher.contract_address, sender);

        dispatcher.create_stream(recipient, 1000_u256, 1000_u64, false, token, false);

        stop_cheat_caller_address(dispatcher.contract_address);

        // Sender wants to cancel. Recipient must sign.
        start_cheat_caller_address(dispatcher.contract_address, sender);

        // Mock the Recipient's signature verification
        mock_call(recipient, selector!("is_valid_signature"), 'VALID', 1);

        let mut spy = spy_events();

        let signature = array![1, 2];
        dispatcher.cancel_consensual(stream_id, signature);

        stop_cheat_caller_address(dispatcher.contract_address);

        let stream = dispatcher.get_stream(stream_id);
        assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');

        spy
            .assert_emitted(
                @array![
                    (
                        dispatcher.contract_address,
                        ConsensualCancel { stream_id, caller: sender, signer: recipient },
                    ),
                ],
            );
    }

    #[test]
    fn test_consensual_cancel_recipient_initiated() {
        let (dispatcher, _owner, _collector, token) = setup();

        let sender = contract_address_const::<'sender'>();
        let recipient = contract_address_const::<'recipient'>();
        let stream_id = 1_u256;

        mock_call(token, selector!("transferFrom"), true, 1);
        mock_call(token, selector!("transfer"), true, 1);
        mock_call(token, selector!("balanceOf"), 1000_u256, 1);
        mock_call(token, selector!("allowance"), 1000_u256, 1);

        start_cheat_caller_address(dispatcher.contract_address, sender);
        dispatcher.create_stream(recipient, 1000_u256, 1000_u64, false, token, false);
        stop_cheat_caller_address(dispatcher.contract_address);

        // Recipient executes cancel, Sender signs
        start_cheat_caller_address(dispatcher.contract_address, recipient);

        mock_call(sender, selector!("is_valid_signature"), 'VALID', 1);

        let mut spy = spy_events();
        dispatcher.cancel_consensual(stream_id, array![3, 4]);

        stop_cheat_caller_address(dispatcher.contract_address);

        let stream = dispatcher.get_stream(stream_id);
        assert(stream.status == StreamStatus::Canceled, 'Stream not canceled');

        spy
            .assert_emitted(
                @array![
                    (
                        dispatcher.contract_address,
                        ConsensualCancel { stream_id, caller: recipient, signer: sender },
                    ),
                ],
            );
    }
}
