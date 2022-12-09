## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| Dispenser-flatten.sol | 42abbedf5d70aae0dcac9e2070385a732a546901 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **IErrorsTokenomics** | Interface |  |||
||||||
| **GenericTokenomics** | Implementation | IErrorsTokenomics |||
| └ | initialize | Internal 🔒 | 🛑  | |
| └ | changeOwner | External ❗️ | 🛑  |NO❗️ |
| └ | changeManagers | External ❗️ | 🛑  |NO❗️ |
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
| **ITreasury** | Interface |  |||
| └ | depositTokenForOLAS | External ❗️ | 🛑  |NO❗️ |
| └ | depositServiceDonationsETH | External ❗️ |  💵 |NO❗️ |
| └ | isEnabled | External ❗️ |   |NO❗️ |
| └ | checkPair | External ❗️ | 🛑  |NO❗️ |
| └ | withdrawToAccount | External ❗️ | 🛑  |NO❗️ |
| └ | rebalanceTreasury | External ❗️ | 🛑  |NO❗️ |
||||||
| **Dispenser** | Implementation | GenericTokenomics |||
| └ | <Constructor> | Public ❗️ | 🛑  | GenericTokenomics |
| └ | claimOwnerIncentives | External ❗️ | 🛑  |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
