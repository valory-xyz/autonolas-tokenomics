// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Dispenser} from "../contracts/Dispenser.sol";
import {DispenserProxy} from "../contracts/proxies/DispenserProxy.sol";

// Stands in for the governance VoteWeighting (its real ctor is the same two-immutable shape,
// covered by the governance repo's own suite). Here we only rehearse the tokenomics-side
// deploy order + the circular-dependency break (proxy init with VW=0, then changeManagers).
contract MockVW {
    address public immutable ve;
    address public immutable dispenser;
    constructor(address _ve, address _dispenser) { ve = _ve; dispenser = _dispenser; }
}

contract ForkO4L1Rehearse is Test {
    address constant OLAS = 0x0001A500A6B18995B03f44bb040A5fFc28E45CB0;
    address constant TOKPROXY = 0xc096362fa6f4A4B1a9ea68b1043416f3381ce300;
    bytes32 constant RETAINER = bytes32(uint256(0xdEaD));
    address constant TREASURY = 0xa0DA53447C0f6C4987964d8463da7e6628B30f82;
    address constant VE = 0x7e01A500805f8A52Fad229b3015AD130A332B7b3;
    bytes32 constant PROXY_DISPENSER = 0x8bd249c73459f2c50400ebdc57436101fc7d9a76908baf1ba5be362b47b48f83;

    function test_l1_core_deploy_and_wire() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        // 1) Dispenser implementation (deploy_07a)
        Dispenser impl = new Dispenser(OLAS, TOKPROXY, RETAINER);
        assertEq(impl.olas(), OLAS, "impl olas");
        assertEq(impl.tokenomics(), TOKPROXY, "impl tokenomics");
        assertEq(impl.retainer(), RETAINER, "impl retainer");

        // 2) DispenserProxy with initialize(treasury, VW=0, 1, 10) -> paused, owner=deployer (deploy_07b)
        bytes memory initData = abi.encodeWithSelector(
            Dispenser.initialize.selector, TREASURY, address(0), uint256(1), uint256(10)
        );
        DispenserProxy proxy = new DispenserProxy(address(impl), initData);
        Dispenser disp = Dispenser(address(proxy));

        assertEq(address(uint160(uint256(vm.load(address(proxy), PROXY_DISPENSER)))), address(impl), "impl slot");
        assertEq(disp.owner(), address(this), "owner == deployer");
        assertEq(uint256(disp.paused()), 2, "paused == StakingIncentivesPaused");
        assertEq(disp.voteWeighting(), address(0), "VW zero at init (breaks the circular dep)");
        assertEq(disp.treasury(), TREASURY, "treasury wired");

        // 3) VoteWeighting binds THIS proxy (deploy_23: ctor(ve, proxy))
        MockVW vw = new MockVW(VE, address(proxy));
        assertEq(vw.dispenser(), address(proxy), "VW.dispenser == proxy");
        assertEq(vw.ve(), VE, "VW.ve == veOLAS");

        // 4) Wire VW while still paused + EOA-owned (script_dispenser_change_managers.sh)
        disp.changeManagers(address(0), address(vw));
        assertEq(disp.voteWeighting(), address(vw), "VW wired via changeManagers");
        assertEq(uint256(disp.paused()), 2, "still paused after wiring");

        emit log_named_address("Dispenser impl", address(impl));
        emit log_named_address("DispenserProxy", address(proxy));
    }
}
