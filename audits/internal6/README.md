# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `c14746b4ddc2f7cf6db8a566b47b0dc596212a94` or `tag: v1.3.1-pre-internal-audit`<br> 

## Objectives
The audit focused on changes in tokonomics contract in this repo.

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```bash
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal6/
Generated png file audits/internal6/Tokenomics.png
```
From the point of view of auditing a proxy contract, only storage are important: Tokenomics. <br>
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal6/analysis/storage/Tokenomics.png) - 17 slots <br>
Current contract storage
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis2/storage/Tokenomics.png) - 17 slots <br>
OK.

### Security issues.
#### Medium/Notes. Re-math for updateInflation
```
Perhaps a more complex algorithm is needed so that the staking limit is not exceeded in the year of the change. To discussion.
```
[]

#### Medium/Notes. Not fixed TODO
```
grep -r TODO ./contracts/
./contracts/TokenomicsConstants.sol:            // TODO Shall it be 787_991_346e18 as a starting number?
./contracts/TokenomicsConstants.sol:            // TODO Shall it be 787_991_346e18 as a starting number?
./contracts/TokenomicsConstants.sol:            // TODO Shall it be 761_726_593e18 as a starting number?
./contracts/TokenomicsConstants.sol:            // TODO Shall it be 761_726_593e18 as a starting number?
```
[]

#### Low/Notes. Update version?
```
abstract contract TokenomicsConstants {
    // Tokenomics version number
    string public constant VERSION = "1.2.0";
```
[]

#### Low/Notes, No events for updateInflationPerSecond
```
updateInflationPerSecond()
no events for 
        // Update state variables
maxBond = uint96(curMaxBond);
effectiveBond = uint96(curEffectiveBond);
inflationPerSecond = uint96(curInflationPerSecond);
```
[]

