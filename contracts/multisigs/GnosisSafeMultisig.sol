// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import "../interfaces/IMultisig.sol";

/// @title Gnosis Safe - Smart contract for Gnosis Safe multisig implementation of a generic multisig interface
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GnosisSafeMultisig {
    // Selector of the Gnosis Safe setup function
    bytes4 internal constant _GNOSIS_SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Gnosis Safe
    address payable public immutable gnosisSafeL2;
    // Gnosis Safe Factory
    address public immutable gnosisSafeProxyFactory;

    constructor (address payable _gnosisSafeL2, address _gnosisSafeProxyFactory) {
        gnosisSafeL2 = _gnosisSafeL2;
        gnosisSafeProxyFactory = _gnosisSafeProxyFactory;
    }

    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig)
    {
        // TODO Parse the data field into the correct values re: gnosis safe setup. For now just hardcode
        address to;
        bytes memory payload;
        address fallbackHandler;
        address paymentToken;
        uint256 payment;
        address payable paymentReceiver;
        uint256 nonce;
        bytes memory safeParams = abi.encodeWithSelector(_GNOSIS_SAFE_SETUP_SELECTOR, owners, threshold,
            to, payload, fallbackHandler, paymentToken, payment, paymentReceiver);

        GnosisSafeProxyFactory gFactory = GnosisSafeProxyFactory(gnosisSafeProxyFactory);
        GnosisSafeProxy gProxy = gFactory.createProxyWithNonce(gnosisSafeL2, safeParams, nonce);
        multisig = address(gProxy);
    }
}