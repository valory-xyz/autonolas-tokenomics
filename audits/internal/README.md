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

### Fuzzing. Updated 14-12-22
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
```
All found issues are located in "Security issues"

### Security issues. Updated 14-12-22
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal/analysis/slither_full.txt) <br>
Short list: <br>
- ignores return value by IERC20(olas). details in slither-full
- performs a multiplication on the result of a division. details in slither-full 
- should emit an event. details in slither-full
- lacks a zero-check. details in slither-full
- add a reentrancy guard for any blacklisted contract. details in slither-full
- re-check gas optimization for delete mapUserBonds[bondIds[i]]. details in slither-full 
- too similar variable. details in slither-full 

#### Problems found by manual analysis or semi-automatically
##### Treasury function depositServiceDonationsETH. detected with Scribble
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
##### Treasury function drainServiceSlashedFunds.  manual analysis
```
Please pay attention: 
The problem is very similar to the previous one. As we receive ETH, but no updated ETHOwned. Receive ETH just locked in the contract.
```
##### Treasury open issue ref: paused. manual analysis
```
Please pay attention: 
I marked the functions that need to be re-analyzed - whether they should also be paused.
Perhaps not a bug.
```

##### Depository  getPendingBonds. manual analysis
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

##### Depository reedem() && close() vs product.purchased. manual analysis
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
###### Tokenomics.sol
```
// fp = fp/100 - calculate the final value in fixed point
fp = fp.div(PRBMathSD59x18.fromInt(100));
PRBMathSD59x18.fromInt(100) => const
```
###### Treasury.sol <br>
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
###### Delete IGenericBondCalculator(bondCalculator).checkLP(token)
Details in slither-full.
###### All contracts based on GenericTokenomics
To optimize storage usage avoid GenericTokenomics and re-optimize based on "Storage and proxy" information and approach.