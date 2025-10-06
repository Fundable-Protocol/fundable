#!/bin/bash

# Configuration
ACCOUNT_NAME="dev_mainnet"  # account name
NETWORK="mainnet"         # target network (sepolia, mainnet, etc.)
CONTRACT_NAME="PaymentStream"  # The contract name

# Check if sncast is installed
if ! command -v sncast &> /dev/null; then
    echo "Error: sncast is not installed. Please install Starknet Foundry first."
    exit 1
fi

# Declare the contract
echo "Declaring contract $CONTRACT_NAME on $NETWORK..."
sncast --account $ACCOUNT_NAME \
    declare \
    --network $NETWORK \
    --contract-name $CONTRACT_NAME
    

# Check if the declaration was successful
if [ $? -eq 0 ]; then
    echo "Contract declaration completed successfully!"
else
    echo "Error: Contract declaration failed."
    exit 1
fi 