#!/bin/bash

# Configuration
ACCOUNT_NAME="dev_mainnet"  # Replace with your account name
NETWORK="mainnet"         # Replace with your target network (sepolia, mainnet, etc.)
CLASS_HASH="0x00d4848abd500e9daa9a64ce23976308fdebee4fa322ac8ce008b72cbf4b4465"     # Replace with your contract's class hash after declaration    # Replace with the protocol owner address 
PROTOCOL_OWNER=0x004bB7b2bb4180Eb1da851497715A07abC6DcB64f81f7A7e4a3fb7d3ea04D9Fc
GENERAL_PROTOCOL_FEE_RATE=100
PROTOCOL_FEE_ADDRESS=0x004bB7b2bb4180Eb1da851497715A07abC6DcB64f81f7A7e4a3fb7d3ea04D9Fc

# Check if sncast is installed
if ! command -v sncast &> /dev/null; then
    echo "Error: sncast is not installed. Please install Starknet Foundry first."
    exit 1
fi

# Validate required parameters
if [ -z "$CLASS_HASH" ]; then
    echo "Error: CLASS_HASH is not set. Please set it in the script."
    exit 1
fi

if [ -z "$PROTOCOL_OWNER" ]; then
    echo "Error: PROTOCOL_OWNER is not set. Please set it in the script."
    exit 1
fi

# Deploy the contract
echo "Deploying contract with class hash $CLASS_HASH on $NETWORK..."
DEPLOY_OUTPUT=$(sncast --account $ACCOUNT_NAME \
    deploy \
    --network $NETWORK \
    --class-hash $CLASS_HASH \
    --constructor-calldata $PROTOCOL_OWNER $GENERAL_PROTOCOL_FEE_RATE $PROTOCOL_FEE_ADDRESS)

# Check if the deployment was successful
if [ $? -eq 0 ]; then
    echo "Contract deployment completed successfully!"
    echo "$DEPLOY_OUTPUT"
    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep "contract_address" | awk '{print $2}')
    if [ -n "$CONTRACT_ADDRESS" ]; then
        echo "new_contract_address: $CONTRACT_ADDRESS" >> deployment_state.txt
        echo "Updated deployment_state.txt with new contract address."
    else
        echo "Could not extract contract address from deployment output."
    fi
else
    echo "Error: Contract deployment failed."
    echo "$DEPLOY_OUTPUT"
    exit 1
fi 