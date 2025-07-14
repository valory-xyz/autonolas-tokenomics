#!/bin/bash

# Get network name from network_mainnet or network_sepolia or another testnet
network=${1%_*}

# Deploy Deposit Processor L1
# Get mainnet or testnet string from network_mainnet or network_sepolia or another testnet
./scripts/deployment/staking/deploy_*_${network}_deposit_processor.sh ${1#*_}

# No further L2 deployment is needed for ethereum
if [ "$network" == "eth" ]; then
  exit 0
fi

# Deploy Target Dispenser L2
./scripts/deployment/staking/${network}/deploy_*_${network}_target_dispenser.sh $1

# Set TargetDispenserL2 in DepositProcessorL1
./scripts/deployment/staking/script_01_set_target_dispenser_l2.sh $1

# Set fxRootTunnel as DepositProcessorL1 in TargetDispenserL2 on Polygon
if [ "$network" == "polygon" ]; then
  ./scripts/deployment/staking/script_03_set_deposit_processor_l1_polygon.sh $1
fi