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
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Tokenomics.png) <br>
[Depository-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Depository.png) <br>
[Dispenser-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Dispenser.png) <br>
[Treasury-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/Treasury.png) <br>
[DonatorBlacklist-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/DonatorBlacklist.png) <br>
[TokenomicsProxy-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/TokenomicsProxy.png) <br>

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

Proxy Conclusions: <br>
- Implementation conforms on Universal Upgradeable Proxy Standard (UUPS) EIP-1822 standard
- Implementation address located in a unique storage slot in the proxy contract.
- Upgrade logic located in the implementation contract.
- Contract verification is possible, most evm block explorers support it. <br>
Well known vulnerabilities: <br>
- Uninitialized proxy: no ✔️
- Function clashing: no ✔️
- Selfdestruct: no ✔️ <br>
Tokenomics.sol as implementation should not contain delegatecall itself. <br>
Example of issue: https://github.com/YAcademy-Residents/Solidity-Proxy-Playground/tree/main/src/function_clashing/UUPS_functionClashing <br>

#### Updated contract storage
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/updated/Tokenomics.png) <br>
[Depository-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/updated/Depository.png) <br>
[Dispenser-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/updated/Dispenser.png) <br>
[Treasury-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/storage/updated/Treasury.png) <br>

All the contracts got reduced by a minimum of 2 slots, which results in contract size deployment as well.

### Fuzzing. Updated 15-12-22
#### In-place testing with Scribble
```
./scripts/scribble.sh Treasury.sol
./scripts/scribble.sh TokenomicsProxy.sol -- skipped, not suitable for testing with this tool
- I did not find a native way checking slot by index like sload(PROXY_TOKENOMICS)
./scripts/scribble.sh TokenomicsConstants.sol -- skipped, not suitable for testing with this tool
Scibble bugs, problem:
- Incorrect postprocessing pure/view function to public in instrumental version. As a result, it breaks a properly working test
- I did not find a native way to evaluate an expression like 1e27 * (1.02)^(x-9). This renders the check useless.
./scripts/scribble.sh Depository.sol
./scripts/scribble.sh Tokenomics.sol
```
All found issues are located in "Security issues"

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt) <br>
Short list: <br>
- ignores return value by IERC20(olas). Recommendation: needs to be fixed.
- performs a multiplication on the result of a division. Recommendation: must to be fixed.
- should emit an event. Recommendation: must to be fixed.
- lacks a zero-check. Recommendation: needs to be fixed.
- add a reentrancy guard for any blacklisted contract. Recommendation: must to be fixed (if planned external blacklist contract) 
- re-check gas optimization for delete mapUserBonds[bondIds[i]]. Recommendation: pay attention. 
- too similar variable. Recommendation: are welcome but no required to be fixed. Minor issue.

##### Fixes
- [1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680](https://github.com/valory-xyz/autonolas-tokenomics/commit/1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680);
- [bb6a692b072cd91e6740d8f7081bf1753a81f1bb](https://github.com/valory-xyz/autonolas-tokenomics/commit/bb6a692b072cd91e6740d8f7081bf1753a81f1bb);
- [416eb7dd585f8a1e1daadd3a7e3e8d995336fc0d](https://github.com/valory-xyz/autonolas-tokenomics/commit/416eb7dd585f8a1e1daadd3a7e3e8d995336fc0d).

#### Problems found by manual analysis or semi-automatically
##### Treasury function depositServiceDonationsETH. 
```
Detected problem and needs an explanation.
As a result, there will be at least a desynchronization between the amount of eth on Treasury (this.balance) and 2 variables: ETHFromServices and ETHOwned.
if donationETH < msg.value then delta = msg.value - donationETH becomes irrelevant to anyone.
    ///if_succeeds {:msg "updated ETHFromServices"} ETHFromServices == old(ETHFromServices) + msg.value; !!! fails
    function depositServiceDonationsETH(uint256[] memory serviceIds, uint256[] memory amounts) external payable {
    ...
    // Accumulate received donation from services
    uint256 donationETH = ITokenomics(tokenomics).trackServiceDonations(msg.sender, serviceIds, amounts);
    donationETH += ETHFromServices;
    ETHFromServices = uint96(donationETH); !!! donationETH != msg.value
or with console.log
    console.log("ETH sended",msg.value);
    console.log("ETHFromServices before",ETHFromServices);
    // Accumulate received donation from services
    uint256 donationETH = ITokenomics(tokenomics).trackServiceDonations(msg.sender, serviceIds, amounts);
    int256 delta = int256(msg.value - donationETH);
    console.log("delta");
    console.logInt(delta); 
    console.log("donationETH calc",donationETH);
    donationETH += ETHFromServices;
    ETHFromServices = uint96(donationETH);
    console.log("ETHFromServices after",ETHFromServices);
    emit DepositETHFromServices(msg.sender, donationETH);

Deposits ETH from protocol-owned services
      ✓ Should fail when depositing a zero value
      ✓ Should fail when input arrays do not match
      ✓ Should fail when the amount does not match the total donation amounts
      ✓ Should fail when there is at least one zero donation amount passed
ETH sended 10000000000000000000000000
ETHFromServices before 0
delta
9999999000000000000000000
donationETH calc 1000000000000000000
ETHFromServices after 1000000000000000000
Even if in this case, this is due to "Mock"-tokenomics - but the logic as a whole needs to be corrected.
Please pay attention:
Ref: trackServiceDonations
donationETH = mapEpochTokenomics[curEpoch].epochPoint.totalDonationsETH + donationETH; ! so returned donationETH = x + msg.value;
```
Recommendation: must to be fixed. certain bug. 💥

##### Fixes
- [1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680](https://github.com/valory-xyz/autonolas-tokenomics/commit/1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680).

#### Depository function getPendingBonds. 
```
function getPendingBonds(address account) external view returns (uint256[] memory bondIds, uint256 payout) {
    uint256 numAccountBonds;
    // Calculate the number of pending bonds
    uint256 numBonds = bondCounter;
    bool[] memory positions = new bool[](numBonds);
    // Record the bond number if it belongs to the account address and was not yet redeemed
    for (uint256 i = 0; i < numBonds; i++) {
        if (mapUserBonds[i].account == account && mapUserBonds[i].payout > 0) {
    + block.timestamp >= mapUserBonds[bondId].maturity
    Otherwise:
    redeem(getPendingBonds()) can be fails on:
    bool matured = (block.timestamp >= mapUserBonds[bondIds[i]].maturity) && (pay > 0);
     // Revert if the bond does not exist or is not matured yet
    if (!matured) {
        revert BondNotRedeemable(bondIds[i]);
    }
Explanation: we rely on the presence of a helper view function for the function redeem(uint256[] memory bondIds), which will form the correct array of bondIds.
But, current getPendingBonds() returns the array of ids that does not satisfy the condition: block.timestamp >= mapUserBonds[bondIds[i]].maturity
Accordingly, the user does not have a function whose result can be safely used as redeem input.
```
Recommendation: must to be fixed. Bug from point view of UX. 🔶

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


#### Minor issue and necessary logical fixes
##### Unused event
This is not a runtime error, but the contract needs to be cleaned up to reduce the bytecode. <br>
[Unused event](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/unused_event.md) <br>
Recommendation: needs to be fixed. Non-critical. 

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


##### Semantic versioning in tokenomics implementation
Needs to add a variable (constant) with the version number. <br>
Recommendation: needs to be fixed. 

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


##### Treasury pause for some other functions.
```
Please pay attention: 
I marked the functions that need to be re-analyzed - whether they should also be paused.
Perhaps not a bug.
```
Recommendation: pay attention. 

##### Fixes
- Has left TODO-s, decision is pending.

##### Tokenomics epochLen can be zero by misconfig
```
    function initializeTokenomics(
        epochLen = _epochLen;
```
Recommendation: needs to be fixed.

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


##### Tokenomics && Treasury. Parameters must have reasonable lower bounds.
```
epochLen - Must have a minimum reasonable duration. The "physical" limit is 2 * time between blocks, but realistically should be something like a week.
function depositServiceDonationsETH - It is desirable to have the minimum reasonable amount of ETH(wei) and revert if msg.value < LIMIT.
From the point of view of calculations, minimum values are sufficient, for example 1gWei.
From the point of view of protection against "Dusting attack", we can set a reasonable minimum value that will allow anybody to send allowed values, but will limit explicit spam.
The latter also refers to the receive().
https://blockworks.co/news/defi-web-apps-block-users-hit-by-tornado-cash-dust-attack 
```
Recommendation: pay attention.

##### Fixes
- [e199c662e49a11c6531c8ee443ed4a1bf231c9ed](https://github.com/valory-xyz/autonolas-tokenomics/pull/59/commits/e199c662e49a11c6531c8ee443ed4a1bf231c9ed);
- Has left TODO-s, decision is pending.

### Improvements related to critical external updates
#### Update a external fixed point library and fixed point related code
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
Recommendation: must to be fixed. ✴️

##### Fixes
- [1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680](https://github.com/valory-xyz/autonolas-tokenomics/commit/1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680).


### Optimization
#### Depository reedem() && close() vs product.purchased.
```
function redeem(uint256[] memory bondIds) public returns (uint256 payout)
...
delete mapBondProducts[productId];
or
function close(uint256 productId) external
...
delete mapBondProducts[productId];
vs
function deposit(uint256 productId, uint256 tokenAmount)
...
    uint256 purchased = product.purchased + tokenAmount;
    product.purchased = uint224(purchased);
Thus, this information will be erased at the time of closing the product.
It makes the field product.purchased a waste of storage.
function deposit(uint256 productId, uint256 tokenAmount) ->
    ITreasury(treasury).depositTokenForOLAS(msg.sender, tokenAmount, token, payout);
    function depositTokenForOLAS(address account, uint256 tokenAmount, address token, uint256 olasMintAmount) 
        uint256 reserves = tokenInfo.reserves + tokenAmount;
        tokenInfo.reserves = uint224(reserves);
This data is accounted in the right place, i.e. in the Treasury. product.purchased = uint224(purchased) - useless
```
Recommendation: must to be fixed. in terms of useless spending of gas, this is a bug. ✴️

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


#### Tokenomics tp.epochPoint.endBlockNumber.
```
struct EpochPoint {
        // Epoch end block number
    // With the current number of seconds per block and the current block number, 2^32 - 1 is enough for the next 1600+ years
    uint32 endBlockNumber;
}
 grep -r endBlockNumber ./contracts/
./contracts/Tokenomics.sol:    uint32 endBlockNumber;
./contracts/Tokenomics.sol:        tp.epochPoint.endBlockNumber = uint32(block.number);
Only assigned but not used in any way.
All real calculations are based on `endTime`
```
Recommendation: needs to be fixed if it is not necessary for the excluded functionality.💹

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


#### Tokenomics.sol
```
// fp = fp/100 - calculate the final value in fixed point
fp = fp.div(PRBMathSD59x18.fromInt(100));
PRBMathSD59x18.fromInt(100) => const
```
Recommendation: needs to be fixed.
##### Fixes
- [1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680](https://github.com/valory-xyz/autonolas-tokenomics/commit/1c4ac57a7f5aa1cd017101f5bcb8d3c4e342b680).

#### Treasury.sol <br>
```
Try map instead of array
// Set of registered tokens
address[] public tokenRegistry;
logic of functions:
function enableToken(address token) external
function disableToken(address token) external
function isEnabled(address token) external view returns (bool enabled)

// Token address => token info related to bonding
mapping(address => TokenInfo) public mapTokens;
// Set of registered tokens
address[] public tokenRegistry;
=>
mapping(address => uint256) public mapTokensReserves;
mapping(address => bool) public mapTokenRegistry;
```
Recommendation: needs to be fixed. Not a bug, but should be a significant optimization. 💹

##### Fixes
- [327789af9b23c2d738986af731ea5fd728d1d548](https://github.com/valory-xyz/autonolas-tokenomics/pull/58/commits/327789af9b23c2d738986af731ea5fd728d1d548).


#### Delete IGenericBondCalculator(bondCalculator).checkLP(token)
Details in [slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt) <br>
Recommendation: needs to be fixed. Not a bug, but should be a optimize and eliminate unnecessary code. 💹

##### Fixes
- [47735d42e579a752518ab345fee613bf31a3e2f1](https://github.com/valory-xyz/autonolas-tokenomics/pull/57/commits/47735d42e579a752518ab345fee613bf31a3e2f1).


#### All contracts based on GenericTokenomics
To optimize storage usage avoid GenericTokenomics and re-optimize based on "Storage and proxy" information and approach. <br>
Recommendation: needs to be fixed. Not a bug, but should be a significant optimization. 💹

##### Fixes
- [369b2393cc1bf84e825629947f5af246971652ca](https://github.com/valory-xyz/autonolas-tokenomics/pull/59/commits/369b2393cc1bf84e825629947f5af246971652ca).


### Improvements to tests and code self-documentation.
#### Improvement test if needed
Expicity test: all funds earmarked for developers and temporarily in the treasury are not movable by the owner of the treasury, and vice versa. <br>
Notes: Fulfilled in fact with scribble. ✔️
#### Explanations for Tokenomics accountOwnerIncentives 
accountOwnerIncentives Requires additional explanation so uses non-obvious mechanics: <br>
```
mapUnitIncentives[unitTypes[i]][unitIds[i]].lastEpoch = 0;
which affects the following calls
trackServiceDonations
_trackServiceDonations
    if (lastEpoch == 0) {
        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
    } else if (lastEpoch < curEpoch) {
        // Finalize component rewards and top-ups if there were pending ones from the previous epoch
        _finalizeIncentivesForUnitId(lastEpoch, unitType, serviceUnitIds[j]);
        // Change the last epoch number
        mapUnitIncentives[unitType][serviceUnitIds[j]].lastEpoch = uint32(curEpoch);
    }
Since the "relations" between "opposite" processes accountOwnerIncentives and trackServiceDonations quite complex and they both called
_finalizeIncentivesForUnitId more explanation is needed.

```
- Added more documentation.

Recommendation: are welcome but no required to be fixed. Minor issue. 
#### Improved Mock contracts
I remade during audit a original MockRegistry.sol: function `drain() external returns (uint256 amount)` now actually sending a ETH. <br>
Notes: Please fixing tests/Mock for real sending a ETH. <br>
Recommendation: needs to be fixed. Without this, the rules written in the language scribble will not work correctly.

##### Fixes
- [37f22d484d8285f05ca7e560df8a39d45e04f805](https://github.com/valory-xyz/autonolas-tokenomics/pull/61/commits/37f22d484d8285f05ca7e560df8a39d45e04f805).