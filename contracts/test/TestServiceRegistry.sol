// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import "../ServiceRegistry.sol";

contract TestServiceRegistry is ServiceRegistry {

    constructor(address _agentRegistry, address payable _gnosisSafeL2, address _gnosisSafeProxyFactory)
        ServiceRegistry(_agentRegistry, _gnosisSafeL2, _gnosisSafeProxyFactory) {}

    // Create a safe contract with the parameters passed and check it via GnosisSafeL2
    function createCheckSafe(GnosisParams memory gParams) public {
        bytes memory safeParams = abi.encodeWithSelector(_GNOSIS_SAFE_SETUP_SELECTOR, gParams.agentInstances,
            gParams.threshold, gParams.to, gParams.data, gParams.fallbackHandler, gParams.paymentToken, gParams.payment,
            gParams.paymentReceiver);

        GnosisSafeProxyFactory gFactory = GnosisSafeProxyFactory(gnosisSafeProxyFactory);
        GnosisSafeProxy gProxy = gFactory.createProxyWithNonce(gnosisSafeL2, safeParams, gParams.nonce);

        address payable gAddress = payable(address(gProxy));
        GnosisSafeL2 gSafe = GnosisSafeL2(gAddress);
        require(gSafe.getThreshold() == gParams.threshold, "Threshold does not match");
        address[] memory gSafeInstances = gSafe.getOwners();
        for (uint256 i = 0; i < gParams.agentInstances.length; i++) {
            require(gSafeInstances[i] == gParams.agentInstances[i], "Owners are wrong");
        }
    }
}
