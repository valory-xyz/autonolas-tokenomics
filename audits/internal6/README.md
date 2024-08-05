# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `12101b49a2dcdc7a7378f416ddb1611e10459b67` or `tag: v1.3.0-pre-internal-audit`<br> 

## Objectives
The audit focused on contracts related to AIP-1 implementation (Bonding) in this repo.

### Flatten version
Flatten version of contracts. [contracts](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal5/analysis/contracts) 

### Coverage: N/A
In this commit, the tests are in the process of being reworked and therefore the coverage section does not make sense.

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal4/analysis/storage
Generated png file audits/internal5/analysis/storage/Tokenomics.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal5/analysis/storage/Tokenomics.png) <br>
current deployed: <br>
[Tokenomics-storage-current](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Tokenomics.png) <br>
The new slot allocation for Tokenomics (critical as proxy pattern) does not affect the previous one. 

### Security issues.
#### Problems found instrumentally
Several checks are obtained automatically. They are commented. Some issues found need to be fixed. <br>
All automatic warnings are listed in the following file, concerns of which we address in more detail below: <br>
[slither-full](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal5/analysis/slither_full.txt) <br>

#### Issue
1. minOLASLeftoverAmount never setupped/updated
```
    // Minimum amount of supply such that any value below is given to the bonding account in order to close the product
    uint256 public minOLASLeftoverAmount;
```
[x] fixed

2. Reentrancy after ERC721 "safe" mint in deposit
```
	External calls:
	- _safeMint(msg.sender,bondId) (Depository-flatten.sol#891)
		- require(bool,string)(ERC721TokenReceiver(to).onERC721Received(msg.sender,address(0),id,) == ERC721TokenReceiver.onERC721Received.selector,UNSAFE_RECIPIENT) (Depository-flatten.sol#461-465)
	After adding _safeMint(msg.sender, bondId), it became clearly susceptible reentrancy attack.
    We need to add explicit protection against reentrancy.
```
[x] fixed

#### General notes: more tests need to be done, needed re-audit later
```
trackServiceDonations requires a large number of tests and coverage of all scenarios.
```
[x] noted

#### Notes for discussion: epsilonRate
```
in this implementation epsilonRate is deprecated and simply not used. perhaps it makes sense (?) to use this dimensionless coefficient as a limiter.
// The IDF depends on the epsilonRate value, idf = 1 + epsilonRate, and epsilonRate is bound by 17 with 18 decimals
new
// IDF = 1 + normalized booster
idf = 1e18 + discountBooster;
maybe idf = min(1e18 + discountBooster, 1e18 + epsilonRate)
Moreover, according to calculations discountBooster <= 1e18 << max(epsilonRate)
```
[x] IDF is never bigger than 2e18 by design

### Re-audit 02.08.24
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `c76a04a64fd450e1a7a34873ea49b6a4b4b0b856` or `tag: v1.3.0-internal-audit2`<br> 

### Coverage
```
---------------------------------|----------|----------|----------|----------|----------------|
File                             |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
---------------------------------|----------|----------|----------|----------|----------------|
 contracts/                      |    98.83 |    96.45 |    95.51 |    97.79 |                |
  BondCalculator.sol             |    97.44 |       98 |    85.71 |    97.22 |        181,299 |
  Depository.sol                 |    95.56 |    92.71 |    81.25 |    93.49 |... 605,608,615 |
  Dispenser.sol                  |    98.95 |    93.06 |      100 |    96.24 |... 0,1209,1267 |
---------------------------------|----------|----------|----------|----------|----------------|
```
Please, pay attention.

### Storage and proxy
Using sol2uml tools: https://github.com/naddison36/sol2uml <br>
```
npm link sol2uml --only=production
sol2uml storage contracts/ -f png -c Tokenomics -o audits/internal6/analysis/storage
Generated png file audits/internal6/analysis/storage/Tokenomics.png
```
[Tokenomics-storage](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal6/analysis/storage/Tokenomics.png) <br>
current deployed: <br>
[Tokenomics-storage-current](https://github.com/valory-xyz/autonolas-tokenomics/blob/main/audits/internal4/analysis/storage/Tokenomics.png) <br>
The new slot allocation for Tokenomics (critical as proxy pattern) does not affect the previous one.

### Issue
I don't see any problems.
