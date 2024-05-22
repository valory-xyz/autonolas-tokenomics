#!/bin/bash

# Enable nullglob to handle cases where no files match the pattern
shopt -s nullglob

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

# Function to extract interfaces with imports from a Solidity contract
function extract_interfaces_with_imports() {
    contract_path="$1"
    interfaces=$(grep -n "import .*;" "$contract_path" | grep -n "interface" | sed "s/^\([0-9]\+\):\(.*\)/\2/")
    echo "$interfaces"
}

# Array to store all import statements
all_imports=()

# Loop through all Solidity files in the contracts staking plus Tokenomics and Dispenser directory
echo "---------------------------"
for contract_file in "${contracts[@]}"; do
    contract_name=$(basename "$contract_file")
    echo "Contract Name: $contract_name"
    interfaces=$(extract_interfaces_with_imports "$contract_file")
    echo "Interfaces: $interfaces"
    echo "---------------------------"
  
    # Add import statements to all_imports array
    imports=$(echo "$interfaces" | grep -o "import .*;" | sort -u)
    all_imports+=($imports)
done 



# New array to store unique combinations of "import" and "interface"
all_imports_conc=()
# First we need to concatenated import-interface pairs
# Loop through the original all_imports array
for ((i = 0; i < ${#all_imports[@]}; i++)); do
    # If the current element is "import"
    if [[ "${all_imports[i]}" == "import" ]]; then
        # Concatenate "import" with the next element (interface) and add it to the new array
        all_imports_conc+=("${all_imports[i]} ${all_imports[i+1]}")
    fi
done

# Remove duplicates from all_imports array
all_imports_no_duplication=()

# Loop through the original array
for element in "${all_imports_conc[@]}"; do
    # Split the element by comma
    IFS=", " read -r -a parts <<< "$element"
    # Check if the combination of "import" and "interface" is not already in the new array
    if [[ ! " ${all_imports_no_duplication[*]} " =~ " ${parts[*]} " ]]; then
        # Add the combination to the new array
        all_imports_no_duplication+=("${parts[@]}")
    fi
done

# New array to store unique combinations of "import" and "interface"
all_imports_conc_n_d=()
# First we need to concatenated import-interface pairs
# Loop through the original all_imports array
for ((i = 0; i < ${#all_imports_no_duplication[@]}; i++)); do
    # If the current element is "import"
    if [[ "${all_imports_no_duplication[i]}" == "import" ]]; then
        # Concatenate "import" with the next element (interface) and add it to the new array
        all_imports_conc_n_d+=("${all_imports_no_duplication[i]} ${all_imports_no_duplication[i+1]}")
    fi
done


echo "Different Interfaces in all Tokenomcs contracts:"
# Loop through the array
for ((i = 0; i < ${#all_imports_conc_n_d[@]}; i++)); do
    # Current import statement
    import_stmt="${all_imports_conc_n_d[$i]}"
    
    # Extract the file name part from the import statement
    file_name=$(basename "$import_stmt")
    
    # Flag to determine if the import statement is distinct
    is_distinct=true
    
    # Check if the current file name is already included
    for ((j = i - 1; j >= 0; j--)); do
        if [[ $(basename "${all_imports_conc_n_d[$j]}") == "$file_name" ]]; then
            is_distinct=false
            break
        fi
    done
    
    # Display the import statement if it's distinct
    if $is_distinct; then
        ((count++))
        echo "$count. $import_stmt"
    fi
done

echo "Total Number of Different Interfaces: $count"





