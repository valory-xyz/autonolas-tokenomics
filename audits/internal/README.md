# Internal audit of autonolas-registries
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `383a4310270d801197bb45df408d19d16dbbfb54` or `v0.1.0.pre-internal-audit`<br> 

## Objectives
The audit focused on contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/contracts) 

### Security issues. Updated 09-12-22
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt)

