# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `ae0cfff0aa6bcde59f1e9442777f3ab427b6d050` or `tag: v1.2.0-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to PooA Staking in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/contracts) 

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal4/analysis/storage
Generated png file audits/internal4/analysis/storage/Tokenomics.png
sol2uml storage contracts/ -f png -c Dispenser -o audits/internal4/analysis/storage          
Generated png file audits/internal4/analysis/storage/Dispenser.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Tokenomics.png) <br>
[Dispenser-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Dispenser.png) <br>
[storage_hardhat_test.md](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/storage_hardhat_test.md) <br>
current deployed: <br>
[Tokenomics-storage-current](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal2/analysis/storage/Tokenomics.png) <br>
The new slot allocation for Tokenomics (critical as proxy pattern) does not affect the previous one. 

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/slither_full.txt) <br>

