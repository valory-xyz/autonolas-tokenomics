// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IToken {
    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStaking {
    function deposit(uint256 stakingAmount) external;
}

interface IStakingFactory {
    function verifyInstance(address instance) external view returns (bool);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Target address verification failed.
/// @param target Target address.
error TargetVerificationFailed(address target);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @title EthereumDepositProcessor - Smart contract for processing tokens and data on L1.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract EthereumDepositProcessor {
    event StakingTargetDeposited(address indexed target, uint256 amount);

    // OLAS address
    address public immutable olas;
    // Tokenomics dispenser address
    address public immutable dispenser;
    // Staking proxy factory address
    address public immutable stakingFactory;
    // Reentrancy lock
    uint8 internal _locked;

    /// @dev EthereumDepositProcessor constructor.
    /// @param _olas OLAS token address.
    /// @param _dispenser Tokenomics dispenser address.
    /// @param _stakingFactory Service staking proxy factory address
    constructor(address _olas, address _dispenser, address _stakingFactory) {
        // Check for zero addresses
        if (_olas == address(0) || _dispenser == address(0) || _stakingFactory == address(0)) {
            revert ZeroAddress();
        }

        olas = _olas;
        dispenser = _dispenser;
        stakingFactory = _stakingFactory;
        _locked = 1;
    }

    /// @dev Deposits staking amounts for corresponding targets.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    function _deposit(address[] memory targets, uint256[] memory stakingAmounts) internal {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Traverse all the targets
        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 amount = stakingAmounts[i];

            // Check the target validity address and staking parameters
            bool success = IStakingFactory(stakingFactory).verifyInstance(target);
            if (!success) {
                revert TargetVerificationFailed(target);
            }

            // Approve the OLAS amount for the staking target
            IToken(olas).approve(target, amount);
            IStaking(target).deposit(amount);

            emit StakingTargetDeposited(target, amount);
        }

        _locked = 1;
    }

    /// @dev Deposits a single staking amount for a corresponding target.
    /// @param target Staking target addresses.
    /// @param stakingAmount Corresponding staking amount.
    function sendMessage(
        address target,
        uint256 stakingAmount,
        bytes memory,
        uint256
    ) external {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != dispenser) {
            revert ManagerOnly(dispenser, msg.sender);
        }

        // Construct one-element arrays from targets and amounts
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory stakingAmounts = new uint256[](1);
        stakingAmounts[0] = stakingAmount;

        // Deposit OLAS to staking contracts
        _deposit(targets, stakingAmounts);
    }


    /// @dev Deposits a batch of staking amounts for corresponding targets.
    /// @param targets Set of staking target addresses.
    /// @param stakingAmounts Corresponding set of staking amounts.
    function sendMessageBatch(
        address[] memory targets,
        uint256[] memory stakingAmounts,
        bytes memory,
        uint256
    ) external {
        // Check for the dispenser contract to be the msg.sender
        if (msg.sender != dispenser) {
            revert ManagerOnly(dispenser, msg.sender);
        }

        // Send the message to L2
        _deposit(targets, stakingAmounts);
    }

    /// @dev Gets the maximum number of token decimals able to be transferred across the bridge.
    /// @notice This function is implemented for the compatibility purposes only, as no cross-bridge is happening on L1.
    /// @return Number of supported decimals.
    function getBridgingDecimals() external pure returns (uint256) {
        return 18;
    }
}
