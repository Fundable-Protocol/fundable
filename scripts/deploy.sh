#!/bin/bash

# Configuration
ACCOUNT_NAME="dev"  # Replace with your account name
NETWORK="sepolia"         # Replace with your target network (sepolia, mainnet, etc.)
CLASS_HASH="0x074098b07d7dd86bdacd596d2de8e88f6ab9ecbf04c11646e33415eec3556c47"     # Replace with your contract's class hash after declaration    # Replace with the protocol owner address 
PROTOCOL_OWNER=0x023345e38d729e39128c0cF163e6916a343C18649f07FcC063014E63558B20f3
GENERAL_PROTOCOL_FEE_RATE=100
PROTOCOL_FEE_ADDRESS=0x023345e38d729e39128c0cF163e6916a343C18649f07FcC063014E63558B20f3

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