# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `383a4310270d801197bb45df408d19d16dbbfb54` or `v0.1.0.pre-internal-audit`<br> 

## Objectives
The audit focused on contracts in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/contracts) 

### Security issues. Updated 12-12-22
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt)

### Fixed point library update
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
#### Unused event
This is not a runtime error, but the contract needs to be cleaned up to reduce the bytecode. <br>
[Unused event](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/unused_event.md)

#### Optimization notices
Tokenomics.sol <br>
```
// fp = fp/100 - calculate the final value in fixed point
fp = fp.div(PRBMathSD59x18.fromInt(100));
PRBMathSD59x18.fromInt(100) => const
```