# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `4e5f57f192c54ed7c8572159d20e1a5d79cdd4d0` or `v1.0.2.pre-internal-audi`<br> 

## Objectives
The audit focused on changes in Depository contract in this repo.

## Flatten version
```bash
surya flatten Depository.sol > ../audits/internal3/analysis/contracts/Depository.sol
```

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage contracts/ -f png -c Depository -o audits/internal3/analysis/storage         
Generated png file /home/andrey/valory/autonolas-tokenomics/audits/internal3/analysis/storage/Depository.png
```
New `Depository` does not depend on the previous implementation of the `Depository` and does not "share" a common storage. <br>
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
