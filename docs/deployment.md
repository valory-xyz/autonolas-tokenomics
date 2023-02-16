Steps for deploying the tokenomics contracts are as follows:

1. EOA to deploy DonatorBlacklist;
2. EOA to deploy Tokenomics;
3. EOA to deploy TokenomicsProxy;
4. EOA to deploy Treasury;
5. EOA to deploy GenericBondCalculator;
6. EOA to deploy Depository;
7. EOA to deploy Dispenser;
8. EOA to change Tokenomics managers calling `changeManagers(Treasury, Depository, Dispenser)`;
9. EOA to change Treasury managers calling `changeManagers(ZeroAddress, Depository, Dispenser)`;
10. EOA to transfer ownership rights of TokenomicsProxy to Timelock calling `changeOwner(Timelock)`;
11. EOA to transfer ownership rights of Treasury to Timelock calling `changeOwner(Timelock)`;
12. EOA to transfer ownership rights of Depository to Timelock calling `changeOwner(Timelock)`;
13. EOA to transfer ownership rights of Dispenser to Timelock calling `changeOwner(Timelock)`;
14. Timelock to transfer the minter role of OLAS to the Treasury calling `changeMinter(Treasury)`;
15. ServiceRegistry to transfer the drainer role to the Treasury calling `changeDrainer(Treasury)`.