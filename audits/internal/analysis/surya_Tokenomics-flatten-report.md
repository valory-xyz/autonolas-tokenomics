## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| Tokenomics-flatten.sol | eb81ea57a249da88c70fcea067e88fbf08329a20 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **PRBMath** | Library |  |||
| └ | exp2 | Internal 🔒 |   | |
| └ | mostSignificantBit | Internal 🔒 |   | |
| └ | mulDiv | Internal 🔒 |   | |
| └ | mulDivFixedPoint | Internal 🔒 |   | |
| └ | mulDivSigned | Internal 🔒 |   | |
| └ | sqrt | Internal 🔒 |   | |
||||||
| **PRBMathSD59x18** | Library |  |||
| └ | abs | Internal 🔒 |   | |
| └ | avg | Internal 🔒 |   | |
| └ | ceil | Internal 🔒 |   | |
| └ | div | Internal 🔒 |   | |
| └ | e | Internal 🔒 |   | |
| └ | exp | Internal 🔒 |   | |
| └ | exp2 | Internal 🔒 |   | |
| └ | floor | Internal 🔒 |   | |
| └ | frac | Internal 🔒 |   | |
| └ | fromInt | Internal 🔒 |   | |
| └ | gm | Internal 🔒 |   | |
| └ | inv | Internal 🔒 |   | |
| └ | ln | Internal 🔒 |   | |
| └ | log10 | Internal 🔒 |   | |
| └ | log2 | Internal 🔒 |   | |
| └ | mul | Internal 🔒 |   | |
| └ | pi | Internal 🔒 |   | |
| └ | pow | Internal 🔒 |   | |
| └ | powu | Internal 🔒 |   | |
| └ | scale | Internal 🔒 |   | |
| └ | sqrt | Internal 🔒 |   | |
| └ | toInt | Internal 🔒 |   | |
||||||
| **IErrorsTokenomics** | Interface |  |||
||||||
| **GenericTokenomics** | Implementation | IErrorsTokenomics |||
| └ | initialize | Internal 🔒 | 🛑  | |
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | changeManagers | External ❗️ | 🛑  |NO❗️ |
||||||
| **TokenomicsConstants** | Implementation |  |||
| └ | getSupplyCapForYear | Public ❗️ |   |NO❗️ |
| └ | getInflationForYear | Public ❗️ |   |NO❗️ |
||||||
| **IDonatorBlacklist** | Interface |  |||
| └ | isDonatorBlacklisted | External ❗️ |   |NO❗️ |
||||||
| **IOLAS** | Interface |  |||
| └ | mint | External ❗️ | 🛑  |NO❗️ |
| └ | timeLaunch | External ❗️ |   |NO❗️ |
| └ | inflationRemainder | External ❗️ |   |NO❗️ |
| └ | decimals | External ❗️ |   |NO❗️ |
| └ | transfer | External ❗️ | 🛑  |NO❗️ |
||||||
| **IServiceTokenomics** | Interface |  |||
| └ | exists | External ❗️ |   |NO❗️ |
| └ | getUnitIdsOfService | External ❗️ |   |NO❗️ |
| └ | drain | External ❗️ | 🛑  |NO❗️ |
||||||
| **IToken** | Interface |  |||
| └ | balanceOf | External ❗️ |   |NO❗️ |
| └ | ownerOf | External ❗️ |   |NO❗️ |
| └ | totalSupply | External ❗️ |   |NO❗️ |
||||||
| **ITreasury** | Interface |  |||
| └ | depositTokenForOLAS | External ❗️ | 🛑  |NO❗️ |
| └ | depositServiceDonationsETH | External ❗️ |  💵 |NO❗️ |
| └ | isEnabled | External ❗️ |   |NO❗️ |
| └ | checkPair | External ❗️ | 🛑  |NO❗️ |
| └ | withdrawToAccount | External ❗️ | 🛑  |NO❗️ |
| └ | rebalanceTreasury | External ❗️ | 🛑  |NO❗️ |
||||||
| **IVotingEscrow** | Interface |  |||
| └ | getVotes | External ❗️ |   |NO❗️ |
| └ | balanceOfAt | External ❗️ |   |NO❗️ |
| └ | totalSupplyAt | External ❗️ |   |NO❗️ |
||||||
| **Tokenomics** | Implementation | TokenomicsConstants, GenericTokenomics |||
| └ | <Constructor> | Public ❗️ | 🛑  | TokenomicsConstants GenericTokenomics |
| └ | initializeTokenomics | External ❗️ | 🛑  |NO❗️ |
| └ | tokenomicsImplementation | External ❗️ |   |NO❗️ |
| └ | changeTokenomicsImplementation | External ❗️ | 🛑  |NO❗️ |
| └ | _adjustMaxBond | Internal 🔒 | 🛑  | |
| └ | changeTokenomicsParameters | External ❗️ | 🛑  |NO❗️ |
| └ | changeIncentiveFractions | External ❗️ | 🛑  |NO❗️ |
| └ | changeRegistries | External ❗️ | 🛑  |NO❗️ |
| └ | changeDonatorBlacklist | External ❗️ | 🛑  |NO❗️ |
| └ | reserveAmountForBondProgram | External ❗️ | 🛑  |NO❗️ |
| └ | refundFromBondProgram | External ❗️ | 🛑  |NO❗️ |
| └ | _finalizeIncentivesForUnitId | Internal 🔒 | 🛑  | |
| └ | _trackServiceDonations | Internal 🔒 | 🛑  | |
| └ | trackServiceDonations | External ❗️ | 🛑  |NO❗️ |
| └ | checkpoint | External ❗️ | 🛑  |NO❗️ |
| └ | getInflationPerEpoch | External ❗️ |   |NO❗️ |
| └ | getEpochPoint | External ❗️ |   |NO❗️ |
| └ | getUnitPoint | External ❗️ |   |NO❗️ |
| └ | getIDF | External ❗️ |   |NO❗️ |
| └ | getLastIDF | External ❗️ |   |NO❗️ |
| └ | accountOwnerIncentives | External ❗️ | 🛑  |NO❗️ |
| └ | getOwnerIncentives | External ❗️ |   |NO❗️ |
| └ | getIncentiveBalances | External ❗️ |   |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
