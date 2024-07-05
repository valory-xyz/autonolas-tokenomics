# Internal audit of autonolas-tokenomics
The review has been performed based on the contract code in the following repository:<br>
`https://github.com/valory-xyz/autonolas-tokenomics` <br>
commit: `357539f11e3386c18bc9370d4cd20066c7fc0599` or `tag: v1.2.2-pre-internal-audit`<br> 

## Objectives
The audit focused on fixing contracts related to PoAA Staking after C4A.

### Coverage
Hardhat coverage has been performed before the audit and can be found here:
```sh
---------------------------------|----------|----------|----------|----------|----------------|
File                             |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
---------------------------------|----------|----------|----------|----------|----------------|
 contracts/                      |    99.64 |    96.79 |      100 |    98.09 |                |

  Dispenser.sol                  |    98.94 |    90.65 |      100 |    93.86 |... 0,1188,1246 |

 contracts/staking/              |    97.52 |    90.83 |    98.36 |    93.97 |                |
  ArbitrumDepositProcessorL1.sol |      100 |    96.15 |      100 |    97.14 |            157 |
  ArbitrumTargetDispenserL2.sol  |      100 |      100 |      100 |      100 |                |
  DefaultDepositProcessorL1.sol  |      100 |    90.63 |      100 |    94.83 |    134,227,235 |
  DefaultTargetDispenserL2.sol   |     97.5 |     87.8 |      100 |    92.52 |... 459,489,511 |
  EthereumDepositProcessor.sol   |    85.71 |    88.89 |      100 |    86.11 |... 109,112,114 |
  GnosisDepositProcessorL1.sol   |      100 |      100 |      100 |      100 |                |
  GnosisTargetDispenserL2.sol    |      100 |      100 |      100 |      100 |                |
  OptimismDepositProcessorL1.sol |      100 |      100 |      100 |      100 |                |
  OptimismTargetDispenserL2.sol  |      100 |      100 |      100 |      100 |                |
  PolygonDepositProcessorL1.sol  |    91.67 |       80 |       80 |    84.21 |     97,105,110 |
  PolygonTargetDispenserL2.sol   |      100 |       50 |      100 |    81.82 |          68,73 |
  WormholeDepositProcessorL1.sol |      100 |      100 |      100 |      100 |                |
  WormholeTargetDispenserL2.sol  |      100 |    91.67 |      100 |    96.77 |            114 |
 
---------------------------------|----------|----------|----------|----------|----------------|
```
Please, pay attention.

#### Checking the corrections made after C4A
##### Bridging
67. Withheld tokens could become unsynchronized by using retry-ability of bridging protocols #67
https://github.com/code-423n4/2024-05-olas-findings/issues/67
[x] fixed

54. OptimismTargetDispenserL2:syncWithheldTokens is callable with no sanity check on payloads and can lead to permanent loss of withheld token amounts #54
https://github.com/code-423n4/2024-05-olas-findings/issues/54
20. Users will lose all ETH sent as cost parameter in transactions to and from Optimism #20
https://github.com/code-423n4/2024-05-olas-findings/issues/20
4. The msg.value - cost for multiple cross-chain bridges are not refunded to users #4
https://github.com/code-423n4/2024-05-olas-findings/issues/4
[x] fixed

32. Refunds for unconsumed gas will be lost due to incorrect refund chain ID #32
https://github.com/code-423n4/2024-05-olas-findings/issues/32
[x] fixed

29. Attacker can cancel claimed staking incentives on Arbitrum #29
https://github.com/code-423n4/2024-05-olas-findings/issues/29
[x] fixed

26. Non-normalized amounts sent via Wormhole lead to failure to redeem incentives #26 
https://github.com/code-423n4/2024-05-olas-findings/issues/26
[x] fixed

22. Arbitrary tokens and data can be bridged to GnosisTargetDispenserL2 to manipulate staking incentives #22
https://github.com/code-423n4/2024-05-olas-findings/issues/22
[x] fixed

5. The refundAccount is erroneously set to msg.sender instead of tx.origin when refundAccount specified as address(0) #5
https://github.com/code-423n4/2024-05-olas-findings/issues/5
[x] fixed

##### Dispenser
61. Loss of incentives if total weight in an epoch is zero #61
https://github.com/code-423n4/2024-05-olas-findings/issues/61
[x] fixed

56. In retain function checkpoint nominee function is not called which can cause zero amount of tokens being retained. #56
https://github.com/code-423n4/2024-05-olas-findings/issues/56
[x] fixed

38. Removed nominee doesn't receive staking incentives for the epoch in which they were removed which is against the intended behaviour #38
https://github.com/code-423n4/2024-05-olas-findings/issues/38
[x] fixed

27. Unauthorized claiming of staking incentives for retainer #27
https://github.com/code-423n4/2024-05-olas-findings/issues/27
[x] fixed

##### No need to change the code, just add information to the documentation
59. Changing VoteWeighting contract can result in lost staking incentives #59
https://github.com/code-423n4/2024-05-olas-findings/issues/59
[x] fixed

#### Low issue
107. QA Report #107
https://github.com/code-423n4/2024-05-olas-findings/issues/107
```
[N-44] Missing event for critical changes addNomenee in Dispenser
```
110. QA Report #110
https://github.com/code-423n4/2024-05-olas-findings/issues/110
```
[NonCritical-9] Missing events in sensitive function setL2TargetDispenser(address l2Dispenser)
```
113. QA Report #113
https://github.com/code-423n4/2024-05-olas-findings/issues/113
```
[L-08] Use abi.encodeCall() instead of abi.encodeWithSignature()/abi.encodeWithSelector() 
grep -r encodeWithSelec ./contracts/    
./contracts/staking/OptimismDepositProcessorL1.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives, batchHash));
./contracts/staking/OptimismTargetDispenserL2.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount, batchHash));
./contracts/staking/ArbitrumTargetDispenserL2.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount, batchHash));
./contracts/staking/GnosisTargetDispenserL2.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(amount, batchHash));
./contracts/staking/ArbitrumDepositProcessorL1.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives, batchHash));
./contracts/staking/GnosisDepositProcessorL1.sol:        bytes memory data = abi.encodeWithSelector(RECEIVE_MESSAGE, abi.encode(targets, stakingIncentives, batchHash));
```
