// The following code is from flattening this file: GenericBondCalculator.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// The following code is from flattening this import statement in: GenericBondCalculator.sol
// import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/node_modules/@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol
pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

// The following code is from flattening this import statement in: GenericBondCalculator.sol
// import "./interfaces/ITokenomics.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-tokenomics/contracts/interfaces/ITokenomics.sol
pragma solidity ^0.8.17;

/// @dev Interface for tokenomics management.
interface ITokenomics {
    /// @dev Gets effective bond (bond left).
    /// @return Effective bond.
    function effectiveBond() external pure returns (uint256);

    /// @dev Record global data to the checkpoint
    function checkpoint() external returns (bool);

    /// @dev Tracks the deposited ETH service donations during the current epoch.
    /// @notice This function is only called by the treasury where the validity of arrays and values has been performed.
    /// @param account Account address.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of ETH amounts provided by services.
    /// @return donationETH Overall service donation amount in ETH.
    function trackServiceDonations(address account, uint256[] memory serviceIds, uint256[] memory amounts) external
        returns (uint256 donationETH);

    /// @dev Reserves OLAS amount from the effective bond to be minted during a bond program.
    /// @notice Programs exceeding the limit in the epoch are not allowed.
    /// @param amount Requested amount for the bond program.
    /// @return True if effective bond threshold is not reached.
    function reserveAmountForBondProgram(uint256 amount) external returns(bool);

    /// @dev Refunds unused bond program amount.
    /// @param amount Amount to be refunded from the bond program.
    function refundFromBondProgram(uint256 amount) external;

    /// @dev Gets component / agent owner incentives and clears the balances.
    /// @param account Account address.
    /// @param unitTypes Set of unit types (component / agent).
    /// @param unitIds Set of corresponding unit Ids where account is the owner.
    /// @return reward Reward amount.
    /// @return topUp Top-up amount.
    function accountOwnerIncentives(address account, uint256[] memory unitTypes, uint256[] memory unitIds) external
        returns (uint256 reward, uint256 topUp);

    /// @dev Gets inverse discount factor with the multiple of 1e18 of the last epoch.
    /// @return idf Discount factor with the multiple of 1e18.
    function getLastIDF() external view returns (uint256 idf);

    /// @dev Gets the service registry contract address
    /// @return Service registry contract address;
    function serviceRegistry() external view returns (address);
}


/// @title GenericBondSwap - Smart contract for generic bond calculation mechanisms in exchange for OLAS tokens.
/// @dev The bond calculation mechanism is based on the UniswapV2Pair contract.
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GenericBondCalculator {
    // OLAS contract address
    address immutable olas;
    // Tokenomics contract address
    address immutable tokenomics;

    /// @dev Generic Bond Calcolator constructor
    /// @param _olas OLAS contract address.
    /// @param _tokenomics Tokenomics contract address.
    constructor(address _olas, address _tokenomics) {
        olas = _olas;
        tokenomics = _tokenomics;
    }

    /// @dev Calculates the amount of OLAS tokens based on the bonding calculator mechanism.
    /// @notice Currently there is only one implementation of a bond calculation mechanism based on the UniswapV2 LP.
    /// @notice IDF has a 10^18 multiplier and priceLP has the same as well, so the result must be divided by 10^36.
    /// @param tokenAmount LP token amount.
    /// @param priceLP LP token price.
    /// @return amountOLAS Resulting amount of OLAS tokens.
    function calculatePayoutOLAS(uint256 tokenAmount, uint256 priceLP) external view
        returns (uint256 amountOLAS)
    {
        // The result is divided by additional 1e18, since it was multiplied by in the current LP price calculation
        uint256 amountDF = (ITokenomics(tokenomics).getLastIDF() * priceLP * tokenAmount) / 1e36;
        amountOLAS = amountDF;
    }

    /// @dev Gets current reserves of OLAS / totalSupply of LP tokens.
    /// @param token Token address.
    /// @return priceLP Resulting reserveX / totalSupply ratio with 18 decimals.
    function getCurrentPriceLP(address token) external view returns (uint256 priceLP)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply > 0) {
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint256 reserve0;
            uint256 reserve1;
            // requires low gas
            (reserve0, reserve1, ) = pair.getReserves();
            // token0 != olas && token1 != olas, this should never happen
            if (token0 == olas || token1 == olas) {
                // If OLAS is in token0, assign its reserve to reserve1, otherwise the reserve1 is already correct
                if (token0 == olas) {
                    reserve1 = reserve0;
                }
                // Calculate the LP price based on reserves and totalSupply ratio multiplied by 1e18
                // Inspired by: https://github.com/curvefi/curve-contract/blob/master/contracts/pool-templates/base/SwapTemplateBase.vy#L262
                priceLP = (reserve1 * 1e18) / totalSupply;
            }
        }
    }

    /// @dev Check if the token is a UniswapV2Pair.
    /// @param token Address of an LP token.
    /// @return success True if successful.
    function checkLP(address token) external returns (bool success) {
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("kLast()")));
        assembly {
            success := call(
            5000,           // 5k gas
            token,          // destination address
            0,              // no ether
            add(data, 32),  // input buffer (starts after the first 32 bytes in the `data` array)
            mload(data),    // input length (loaded from the first 32 bytes in the `data` array)
            0,              // output buffer
            0               // output length
            )
        }
    }
}    



