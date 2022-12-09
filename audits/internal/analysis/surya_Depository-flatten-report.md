## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| Depository-flatten.sol | ad20d99ebcbb3a4d78e8dfb4af9e3affe8c0723c |


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
| **IGenericBondCalculator** | Interface |  |||
| └ | calculatePayoutOLAS | External ❗️ |   |NO❗️ |
| └ | getCurrentPriceLP | External ❗️ |   |NO❗️ |
| └ | checkLP | External ❗️ | 🛑  |NO❗️ |
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
| **Depository** | Implementation | GenericTokenomics |||
| └ | <Constructor> | Public ❗️ | 🛑  | GenericTokenomics |
| └ | changeBondCalculator | External ❗️ | 🛑  |NO❗️ |
| └ | deposit | External ❗️ | 🛑  |NO❗️ |
| └ | redeem | Public ❗️ | 🛑  |NO❗️ |
| └ | getPendingBonds | External ❗️ |   |NO❗️ |
| └ | getBondStatus | External ❗️ |   |NO❗️ |
| └ | create | External ❗️ | 🛑  |NO❗️ |
| └ | close | External ❗️ | 🛑  |NO❗️ |
| └ | isActiveProduct | External ❗️ |   |NO❗️ |
| └ | getActiveProducts | External ❗️ |   |NO❗️ |
| └ | getCurrentPriceLP | External ❗️ |   |NO❗️ |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
