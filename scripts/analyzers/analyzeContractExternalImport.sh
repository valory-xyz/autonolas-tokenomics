#!/bin/bash

# Enable nullglob to handle cases where no files match the pattern
shopt -s nullglob

# Function to extract non-interface imports from a Solidity contract
function extract_external_imports() {
    contract_path="$1"
    imports=$(grep "import .*;" "$contract_path" | grep -v "interface")
    echo "$imports"
}


contracts=(
    contracts/staking/*.sol 
    contracts/TokenomicsConstants.sol 
    contracts/Tokenomics.sol 
    contracts/Dispenser.sol 
    contracts/interfaces/IToken.sol 
    contracts/interfaces/IDonatorBlacklist.sol 
    contracts/interfaces/IErrorsTokenomics.sol 
    contracts/interfaces/IOLAS.sol 
    contracts/interfaces/IServiceRegistry.sol 
    contracts/interfaces/ITreasury.sol 
    contracts/interfaces/IVotingEscrow.sol 
    contracts/interfaces/ITokenomics.sol
)

# Array to store all import statements
all_imports=()

# Loop through all Solidity files in the staking contracts  
echo "---------------------------"
for contract_file in "${contracts[@]}"; do
    contract_name=$(basename "$contract_file")
    echo "Contract Name: $contract_name"
    external_imports=$(extract_external_imports "$contract_file")
    echo "External Imports: $external_imports"
    echo "---------------------------"
    all_imports+=("$external_imports")
done 


#This script can be improved, is currently not complete