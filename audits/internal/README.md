# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `383a4310270d801197bb45df408d19d16dbbfb54` or `v0.1.0.pre-internal-audit`<br> 

## Objectives
The audit focused on contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/contracts) 

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal/analysis/storage
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/Tokenomics.png
sol2uml storage contracts/ -f png -c Treasury -o audits/internal/analysis/storage          
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/Treasury.png
sol2uml storage contracts/ -f png -c Depository -o audits/internal/analysis/storage
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/Depository.png
sol2uml storage contracts/ -f png -c Dispenser -o audits/internal/analysis/storage          
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/Dispenser.png
storage contracts/ -f png -c DonatorBlacklist -o audits/internal/analysis/storage         
autonolas-tokenomics/audits/internal/analysis/storage/DonatorBlacklist.png
sol2uml storage contracts/ -f png -c TokenomicsProxy -o audits/internal/analysis/storage                
Generated png file autonolas-tokenomics/audits/internal/analysis/storage/TokenomicsProxy.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Tokenomics.png) 
[Depository-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Depository.png)
[Dispenser-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Dispenser.png)
[Treasury-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Treasury.png)
[DonatorBlacklist-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/DonatorBlacklist.png)
[TokenomicsProxy-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/TokenomicsProxy.png)

From the point of view of auditing a proxy contract, only 2 storage are important: Tokenomics and TokenomicsProxy. <br>
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Tokenomics.png) - 18 slots <br>
[TokenomicsProxy-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/TokenomicsProxy.png) - 0 slots <br>
When there will be future implementations, it is critical that the storage be used: current as is + new variables. <br>
One of the semi-automatic verification algorithms:
```
1. enable hardhat.config.js:
// storage layout tool
require('hardhat-storage-layout');
2. enable test Tokenomics.js
let storageLayout = true;
3. run npx hardhat test
4. Compare the number and content of slots for the current implementation and the future one.
```
The remaining storage layouts are useful for final optimization. <br>

### Security issues. Updated 12-12-22
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt)

#### Fixed point library update
Not an bug, but it is desirable in own codebase to switch on latest v3.0.0 of original https://github.com/paulrberg/prb-math <br>
Since our business logic does not involve the use of negative numbers (fKD), we need to unsigned 60.18-decimal fixed-point numbers. <br>
https://github.com/paulrberg/prb-math/blob/main/src/UD60x18.sol#L589 - сheaper and easier. <br>
https://github.com/paulrberg/prb-math/releases/tag/v3.0.0
```
Rename fromInt to toSD59x18 and toInt to fromSD59x18 (a69b4b) (@paulrberg)
Rename fromUint to toUD60x18 and toUint to fromUD60x18 (a69b4b) (@paulrberg)
```
```
Based on practical application, only the following functions are important to us: from(U)Int(latest:toXXYYx18), mul, div
https://github.com/paulrberg/prb-math/blob/main/test/ud60x18/conversion/to/to.t.sol
https://github.com/paulrberg/prb-math/blob/main/test/ud60x18/mathematical/mul/mul.t.sol
https://github.com/paulrberg/prb-math/blob/main/test/ud60x18/mathematical/div/div.t.sol
prb-math$ forge test
OK
```
I advise to always keep the value of `epsilonRate` low as needed. <br>
Since it has the property of an internal independent barrier.
```
    int256 fp1 = PRBMathSD59x18.fromInt(int256(incentives[1])) / 1e18;
    // Convert (codeUnits * devsPerCapital)
    int256 fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.epochPoint.devsPerCapital));
    // fp1 == codeUnits * devsPerCapital * treasuryRewards
    fp1 = fp1.mul(fp2);
    // fp2 = codeUnits * newOwners
    fp2 = PRBMathSD59x18.fromInt(int256(codeUnits * tp.epochPoint.numNewOwners));
    // fp = codeUnits * devsPerCapital * treasuryRewards + codeUnits * newOwners;
    int256 fp = fp1 + fp2;
    // fp = fp/100 - calculate the final value in fixed point
    fp = fp.div(PRBMathSD59x18.fromInt(100));
    // fKD in the state that is comparable with epsilon rate
    uint256 fKD = uint256(fp);

    // Compare with epsilon rate and choose the smallest one
    if (fKD > epsilonRate) {
        fKD = epsilonRate;
    }
```
#### Optimization and improvements
##### Unused event
This is not a runtime error, but the contract needs to be cleaned up to reduce the bytecode. <br>
[Unused event](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/unused_event.md)

##### Semantic versioning in tokenomics implementation
Needs to add a variable (constant) with the version number.

##### Improvement test if needed
Expicity test: all funds earmarked for developers and temporarily in the treasury are not movable by the owner of the treasury, and vice versa.

##### Optimization notices
Tokenomics.sol <br>
```
// fp = fp/100 - calculate the final value in fixed point
fp = fp.div(PRBMathSD59x18.fromInt(100));
PRBMathSD59x18.fromInt(100) => const
```