// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";

/// @title ServiceProxy - Wrapper of the generic proxy contract based on Gnosis Safe Proxy.
/// @author Alkesandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceProxy is GnosisSafeProxy {
    // The ServiceProxy is not utilized at the moment as ServiceProxyFactory based on GnosisSafeProxyFactory
    // utilizes GnosisSafeProxy contracts internally.
    constructor(address _singleton) GnosisSafeProxy (_singleton) {}
}
