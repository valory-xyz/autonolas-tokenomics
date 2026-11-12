// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

interface IDispenser {
    function owner() external view returns (address);
    function voteWeighting() external view returns (address);
    function paused() external view returns (uint8);
    function maxNumClaimingEpochs() external view returns (uint256);
    function maxNumStakingTargets() external view returns (uint256);
    function mapChainIdDepositProcessors(uint256) external view returns (address);
    function changeManagers(address, address) external;
    function setDepositProcessorChainIds(address[] memory, uint256[] memory) external;
    function changeOwner(address) external;
    function setPauseState(uint8) external;
    function changeImplementation(address) external;
}

// Proves, on a mainnet fork with the REAL deployed contracts, that the EOA config + ownership
// handover does not brick anything: every owner-gated function remains callable by the Timelock
// after handover, so any mutable misconfiguration is governance-recoverable.
contract ForkDispenserConfigHandover is Test {
    address constant PROXY    = 0x78Bd94F48CAe623CC74828eCbFEBE3bDF428D83D;
    address constant IMPL     = 0x6f44B0Ab54f0cD5854A21a9e71C78c4F7cDf28f7;
    address constant VW       = 0xe8748e2CE2a4621425499bd26Aa8EF95Cf0C0730;
    address constant DEPLOYER = 0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E;
    address constant TIMELOCK = 0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE;

    function _routes() internal pure returns (address[] memory p, uint256[] memory c) {
        p = new address[](9); c = new uint256[](9);
        c[0]=1;     p[0]=0x0984f182eBC49149406Cc3D579686AA8080AEa32;
        c[1]=42161; p[1]=0xFBB25d10a2Cd2c28403F6edb1D25C27F7Da60656;
        c[2]=100;   p[2]=0x307234E1eF3E493287C7914eeeBC946e6d5ea113;
        c[3]=10;    p[3]=0x914DBe131641374cb84eDf24087893Fe12D880Ad;
        c[4]=8453;  p[4]=0x4D3adDE29234E3431af001eb420d704a161103A3;
        c[5]=42220; p[5]=0x26c2527F6f8CdC75AaBE5d0E8379d62f25Fc8d49;
        c[6]=34443; p[6]=0xf1C564eA76A81f3dE1b4c53938B67C48104bc6cc;
        c[7]=137;   p[7]=0x293f01CBDF7dA067334d6701Aa7f748d0E76fe49;
        c[8]=4663;  p[8]=0xCd4dDd34C7a5C3dA5E9361ceDC8b6fa04b40f22E;
    }

    function test_config_handover_does_not_brick() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        IDispenser d = IDispenser(PROXY);
        (address[] memory procs, uint256[] memory cids) = _routes();

        // Preconditions (as deployed)
        assertEq(d.owner(), DEPLOYER, "pre owner");
        assertEq(d.voteWeighting(), address(0), "pre VW=0");
        assertEq(uint256(d.paused()), 2, "pre paused");
        assertEq(d.maxNumClaimingEpochs(), 1);
        assertEq(d.maxNumStakingTargets(), 10);

        // 1) EOA config
        vm.startPrank(DEPLOYER);
        d.changeManagers(address(0), VW);
        assertEq(d.voteWeighting(), VW, "VW wired");
        d.setDepositProcessorChainIds(procs, cids);
        for (uint256 i; i < 9; ++i) assertEq(d.mapChainIdDepositProcessors(cids[i]), procs[i], "route set");

        // routes are overwritable (not a one-shot brick)
        address[] memory one = new address[](1); uint256[] memory onec = new uint256[](1);
        one[0] = address(0xdEaD); onec[0] = 1; d.setDepositProcessorChainIds(one, onec);
        assertEq(d.mapChainIdDepositProcessors(1), address(0xdEaD), "overwritable");
        one[0] = procs[0]; d.setDepositProcessorChainIds(one, onec);
        assertEq(d.mapChainIdDepositProcessors(1), procs[0], "restorable");

        // 2) handover
        d.changeOwner(TIMELOCK);
        assertEq(d.owner(), TIMELOCK, "owner=timelock");
        vm.stopPrank();

        // 3) deployer is locked out afterwards (expected)
        vm.prank(DEPLOYER); vm.expectRevert(); d.setPauseState(uint8(0));

        // 4) Timelock retains FULL control => nothing bricked.
        // changeManagers requires paused (settle claims before a swap), so unpause LAST.
        vm.startPrank(TIMELOCK);
        d.setDepositProcessorChainIds(one, onec);         // can fix routes (any state)
        d.changeManagers(address(0), VW);                 // can re-wire managers (while paused)
        d.changeImplementation(IMPL);                     // can upgrade implementation
        d.setPauseState(uint8(0));                        // can unpause (activate) -- last
        assertEq(uint256(d.paused()), 0, "gov unpaused");
        d.changeOwner(DEPLOYER);                          // can transfer ownership again
        assertEq(d.owner(), DEPLOYER, "gov can transfer");
        vm.stopPrank();

        // immutables unchanged throughout
        assertEq(d.maxNumClaimingEpochs(), 1, "immutable epochs");
        assertEq(d.maxNumStakingTargets(), 10, "immutable targets");
    }
}
