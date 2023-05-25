# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `f7af7bf3383dfd62136ab78aa17beaf25a05a330` or `v1.0.1.pre-internal-audit`<br> 

## Objectives
The audit focused on changes in tokonomics contract in this repo.

## Flatten version
```bash
surya flatten Tokenomics.sol 

Error found while parsing the following file: autonolas-tokenomics/node_modules/@prb/math/src/ud60x18/ValueType.sol

npx hardhat flatten
Error HH603: Hardhat flatten doesn't support cyclic dependencies.

HardhatError: HH603: Hardhat flatten doesn't support cyclic dependencies.
```
The new version of repo (as it is tentatively clear the reason for updating the library prb/math) is not compatible with existing tools for flatten.

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal/analysis/storage
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/Tokenomics.png
sol2uml storage contracts/ -f png -c TokenomicsProxy -o audits/internal/analysis/storage                
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/TokenomicsProxy.png
```
From the point of view of auditing a proxy contract, only 2 storage are important: Tokenomics and TokenomicsProxy. <br>
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal2/analysis/storage/Tokenomics.png) - 16 slots <br>
[TokenomicsProxy-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal2/analysis/storage/TokenomicsProxy.png) - 0 slots <br>
When there will be future implementations, it is critical that the storage be used: current as is + new variables. <br>
Current contract storage
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/updated/Tokenomics.png) <br>
OK.

### Security issues.
No issue.

#### Notes
```
grep -r solidity contracts/*
contracts/Depository.sol:pragma solidity ^0.8.18;
contracts/Dispenser.sol:pragma solidity ^0.8.18;
contracts/DonatorBlacklist.sol:pragma solidity ^0.8.18;
contracts/GenericBondCalculator.sol:pragma solidity ^0.8.18;
contracts/interfaces/ITokenomics.sol:pragma solidity ^0.8.18;
contracts/interfaces/IVotingEscrow.sol:pragma solidity ^0.8.18;
contracts/interfaces/ITreasury.sol:pragma solidity ^0.8.18;
contracts/interfaces/IServiceRegistry.sol:pragma solidity ^0.8.18;
contracts/interfaces/IOLAS.sol:pragma solidity ^0.8.18;
contracts/interfaces/IErrorsTokenomics.sol:pragma solidity ^0.8.18;
contracts/interfaces/IToken.sol:pragma solidity ^0.8.18;
contracts/interfaces/IDonatorBlacklist.sol:pragma solidity ^0.8.18;
contracts/interfaces/IGenericBondCalculator.sol:pragma solidity ^0.8.18;
contracts/interfaces/IUniswapV2Pair.sol:pragma solidity ^0.8.18;
contracts/TokenomicsConstants.sol:pragma solidity ^0.8.20;
contracts/TokenomicsProxy.sol:pragma solidity ^0.8.18;
contracts/Tokenomics.sol:pragma solidity ^0.8.20;
contracts/Treasury.sol:pragma solidity ^0.8.18;
```
Should we update all versions at the same time?
