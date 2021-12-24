// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

/// @title ServiceProxyMaster - Wrapper of the multisignature wallet Gnosis Safe v1.3.0.
/// @author Alkesandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceProxyMaster is GnosisSafeL2 {
    constructor() GnosisSafeL2() {}
}
