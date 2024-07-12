Steps for deploying the tokenomics version 1.2 contracts are as follows:

1. EOA to deploy Tokenomics implementation (`TokenomicsThree`);
2. TokenomicsProxy to change Tokenomics implementation calling `changeTokenomicsImplementation(TokenomicsThree)`;
3. EOA to deploy Dispenser (`DispenserTwo`) with VoteWeighting contract being deployed before that in `autonolas-governance`;
4. EOA to deploy staking bridging contracts;
5. EOA to set up correct L1->L2 links for all the bridging contracts calling `setL2TargetDispenser(L2 corresponding contract)`;
6. EOA to transfer ownership rights of Dispenser to Timelock calling `changeOwner(Timelock)`;
7. DAO to change Tokenomics managers calling `changeManagers(ZeroAddress, ZeroAddress, DispenserTwo)`;
8. DAO to change staking parameters in Tokenomics calling `changeStakingParams()`;
9. DAO to enable bridge deposit processors in Dispenser calling `setDepositProcessorChainIds()`.

Note for updating VoteWeighting contract address in Dispenser, if required at some point of time.
As outlined in the C4R [issue 59](https://github.com/code-423n4/2024-05-olas-findings/issues/59), the following set of
steps must be taken into account in order to avoid possible staking inflation loss:
- Initiate claim of incentives for all the outstanding staking contract, as those are ownerless;
- Pause staking incentives;
- Change VoteWeighting contract;
- Unpause staking incentives.