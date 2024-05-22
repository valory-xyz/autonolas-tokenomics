# Deployment sequence

## Arbitrum
1. On L1: deploy ArbitrumDepositProcessorL1
2. On L2: Calculate L2 alias for the ArbitrumDepositProcessorL1.address
3. On L2: Deploy ArbitrumTargetDispenserL2
4. On L1: In ArbitrumDepositProcessorL1 set ArbitrumTargetDispenserL2 to l2TargetDispenser.

## Gnosis
1. On L1: deploy GnosisDepositProcessorL1
2. On L2: deploy GnosisTargetDispenserL2
3. On L1: In GnosisDepositProcessorL1 set GnosisTargetDispenserL2 to l2TargetDispenser.

## Optimism / Base
1. On L1: deploy OptimismDepositProcessorL1
2. On L2: deploy OptimismTargetDispenserL2
3. On L1: In OptimismDepositProcessorL1 set OptimismTargetDispenserL2 to l2TargetDispenser.

## Polygon
1. On L1: deploy PolygonDepositProcessorL1
2. On L2: deploy PolygonTargetDispenserL2
3. On L1: In PolygonDepositProcessorL1 set PolygonTargetDispenserL2 to l2TargetDispenser.
4. On L2: In PolygonTargetDispenserL2 set PolygonDepositProcessorL1 to l1DepositProcessor.

## Wormhole
1. On L1: deploy WormholeDepositProcessorL1
2. On L2: deploy WormholeTargetDispenserL2
3. On L1: In WormholeDepositProcessorL1 set WormholeTargetDispenserL2 to l2TargetDispenser.