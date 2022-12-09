## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| Treasury-flatten.sol | 085a6c487ae7ed25a2fdd46d720d8dcff2c16047 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IERC20** | Interface |  |||
| └ | totalSupply | External ❗️ |   |NO❗️ |
| └ | balanceOf | External ❗️ |   |NO❗️ |
| └ | transfer | External ❗️ | 🛑  |NO❗️ |
| └ | allowance | External ❗️ |   |NO❗️ |
| └ | approve | External ❗️ | 🛑  |NO❗️ |
| └ | transferFrom | External ❗️ | 🛑  |NO❗️ |
||||||
| **IErrorsTokenomics** | Interface |  |||
||||||
| **GenericTokenomics** | Implementation | IErrorsTokenomics |||
| └ | initialize | Internal 🔒 | 🛑  | |
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | changeManagers | External ❗️ | 🛑  |NO❗️ |
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
| **ITokenomics** | Interface |  |||
| └ | effectiveBond | External ❗️ |   |NO❗️ |
| └ | checkpoint | External ❗️ | 🛑  |NO❗️ |
| └ | trackServiceDonations | External ❗️ | 🛑  |NO❗️ |
| └ | reserveAmountForBondProgram | External ❗️ | 🛑  |NO❗️ |
| └ | refundFromBondProgram | External ❗️ | 🛑  |NO❗️ |
| └ | accountOwnerIncentives | External ❗️ | 🛑  |NO❗️ |
| └ | getLastIDF | External ❗️ |   |NO❗️ |
| └ | serviceRegistry | External ❗️ |   |NO❗️ |
||||||
| **Treasury** | Implementation | GenericTokenomics |||
| └ | <Constructor> | Public ❗️ |  💵 | GenericTokenomics |
| └ | <Receive Ether> | External ❗️ |  💵 |NO❗️ |
| └ | depositTokenForOLAS | External ❗️ | 🛑  |NO❗️ |
| └ | depositServiceDonationsETH | External ❗️ |  💵 |NO❗️ |
| └ | withdraw | External ❗️ | 🛑  |NO❗️ |
| └ | withdrawToAccount | External ❗️ | 🛑  |NO❗️ |
| └ | enableToken | External ❗️ | 🛑  |NO❗️ |
| └ | disableToken | External ❗️ | 🛑  |NO❗️ |
| └ | isEnabled | External ❗️ |   |NO❗️ |
| └ | rebalanceTreasury | External ❗️ | 🛑  |NO❗️ |
| └ | drainServiceSlashedFunds | External ❗️ | 🛑  |NO❗️ |
| └ | pause | External ❗️ | 🛑  |NO❗️ |
| └ | unpause | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
