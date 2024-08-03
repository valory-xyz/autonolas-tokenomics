Steps for deploying the tokenomics version 1.2 contracts are as follows:

1. EOA to deploy Tokenomics implementation (`TokenomicsThree`);
2. TokenomicsProxy to change Tokenomics implementation calling `changeTokenomicsImplementation(TokenomicsThree)`;
3. EOA to deploy Dispenser with VoteWeighting contract being deployed before that in `autonolas-governance`;
4. EOA to change Dispenser address in VoteWeighting calling `changeDispenser(Dispenser)`;
5. EOA to unpause staking incentives in Dispenser calling `setPauseState(0)`;
6. EOA to add a retainer address as a nominee in VoteWeighting;
7. EOA to deploy staking bridging contracts on L1 and L2 with StakingFactory contract being deployed before that in `autonolas-registries`;
8. EOA to set up correct L1->L2 links for all the bridging contracts calling `setL2TargetDispenser(L2 corresponding contract)`;
9. EOA to enable bridge deposit processors in Dispenser calling `setDepositProcessorChainIds()`;
10. EOA to transfer ownership rights of all the L2 bridging contracts to Timelock representation calling `changeOwner(Timelock)`;
11. EOA to transfer ownership rights of Dispenser to Timelock calling `changeOwner(Timelock)`;
12. DAO to change Tokenomics managers calling `changeManagers(ZeroAddress, ZeroAddress, Dispenser)`;
13. DAO to change staking parameters in Tokenomics calling `changeStakingParams()`;
14. DAO to change Treasury managers calling `changeManagers(ZeroAddress, ZeroAddress, Dispenser)`.

Note for updating VoteWeighting contract address in Dispenser, if required at some point of time.
As outlined in the C4R [issue 59](https://github.com/code-423n4/2024-05-olas-findings/issues/59), the following set of
steps must be taken into account in order to avoid possible staking inflation loss:
- Initiate claim of incentives for all the outstanding staking contract, as those are ownerless;
- Pause staking incentives;
- Change VoteWeighting contract;
- Unpause staking incentives.