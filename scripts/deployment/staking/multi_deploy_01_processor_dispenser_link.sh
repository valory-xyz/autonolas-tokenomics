#!/bin/bash

# Chains the three cross-chain staking deployment steps for one network:
#   L1 deposit processor -> L2 target dispenser -> link the two.
#
# set -e is load-bearing here. Each step binds the NEXT one by address, and two of those bindings are
# `immutable`: DefaultDepositProcessorL1.l1Dispenser, and the aliased l1DepositProcessor that
# DefaultTargetDispenserL2 computes in its constructor. Without set -e a failed step would print its error,
# return non-zero, and the chain would continue with a stale or empty address from the globals — deploying a
# dispenser bound to the wrong processor, which cannot be corrected afterwards.
set -e

# Get network name from network_mainnet or network_sepolia or another testnet
network=${1%_*}

# Deploy Deposit Processor L1
# Get mainnet or testnet string from network_mainnet or network_sepolia or another testnet
./scripts/deployment/staking/deploy_*_${network}_deposit_processor.sh ${1#*_}

# No further L2 deployment is needed for ethereum. This is a legitimate early success, not a failure.
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
