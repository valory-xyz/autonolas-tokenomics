// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ComponentRegistry.sol";
import "./AgentRegistry.sol";
import "./ServiceRegistry.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IErrors.sol";
// Uniswapv2
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
contract Tokenimics is IErrors, Ownable {

    using FixedPoint for *;

    struct PointEcomonics {
        FixedPoint.uq112x112 ucf;
        FixedPoint.uq112x112 usf;
        FixedPoint.uq112x112 df; // x > 1.0       
        uint256 ts; // timestamp
        uint256 blk; // block
        bool    _exist; // ready or not
    }

    // OLA interface
    IERC20 public immutable ola;
    // Treasury interface
    ITreasury public treasury;
    bytes4  private constant FUNC_SELECTOR = bytes4(keccak256("kLast()")); // is pair or pure ERC20?
    uint256 public immutable epochLen; // epoch len in blk
    // source: https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27 
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816; // 2^(112 - log2(1e18))
    uint256 public constant E18 = 10**18;
    uint256 public max_df = 2 * E18;  // 200%
    // Total service revenue per epoch: sum(r(s))
    uint256 public totalServiceRevenue;

    // Component Registry
    address public immutable componentRegistry;
    // Agent Registry
    address public immutable agentRegistry;
    // Service Registry
    address payable public immutable serviceRegistry;
    
    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;
    // Set of protocol-owned services in current epoch
    uint256[] protocolServiceIds;
    // Set of protocol-owned services in previous epoch
//    uint256[] serviceIdsPreviousEpoch;
    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) mapServiceAmounts;
    mapping(uint256 => uint256) mapServiceIndexes;
    // Map of service Ids and their amounts in previous epoch
//    mapping(uint256 => uint256) mapServiceAmountsPreviousEpoch;

    // TODO later fix government / manager
    constructor(address _manager, IERC20 iOLA, ITreasury iTreasury, uint256 _epochLen, address _componentRegistry,
        address _agentRegistry, address payable _serviceRegistry) {
        ola = iOLA;
        treasury = iTreasury;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyTreasury() {
        if (address(treasury) != msg.sender) {
            revert ManagerOnly(msg.sender, address(treasury));
        }
        _;
    }

    /// @dev Gets curretn epoch number.
    function getEpoch() public view returns (uint256 epoch) {
        epoch = block.number / epochLen;
    }

    /// @dev Tracks the deposit token amount during the epoch.
    function trackServicesRevenue(address token, uint256[] memory serviceIds, uint256[] memory amounts)
        public onlyTreasury {
        uint256 epoch = getEpoch();

        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Add a new service Id to the set of Ids if one was not currently in it
            if (mapServiceAmounts[serviceIds[i]] == 0) {
                mapServiceIndexes[serviceIds[i]] = serviceIds.length;
                protocolServiceIds.push(serviceIds[i]);
            }
            mapServiceAmounts[serviceIds[i]] += amounts[i];

            // Increase also the total service revenue
            totalServiceRevenue += amounts[i];
        }
    }

    /// @dev Detect UniswapV2Pair
    /// @param _token Address of a _token. Possible LP or ERC20
    function callDetectPair(address _token) public returns (bool) {
        bool success;
        bytes memory data = abi.encodeWithSelector(FUNC_SELECTOR);
        assembly {
            success := call(
                5000,           // 5k gas
                _token,         // destination address
                0,              // no ether
                add(data, 32),  // input buffer (starts after the first 32 bytes in the `data` array)
                mload(data),    // input length (loaded from the first 32 bytes in the `data` array)
                0,              // output buffer
                0               // output length
            )
        }
        return success;
    }

    /// @dev setup max df. guard dog
    /// @param _max_df maximum interest rate in %, 18 decimals
    function setMaxDf(uint _max_df) external onlyOwner {
        max_df = _max_df;
    }   

    /// @notice Record global data to checkpoint, any can do it
    /// @dev Checked point exist or not 
    function checkpoint() external {
        uint256 epoch = getEpoch();
        PointEcomonics memory lastPoint = mapEpochEconomics[epoch];
        // if not exist
        if(!lastPoint._exist) {
            _checkpoint(epoch);
        }
    }

    /// @dev Record global data to new checkpoint
    /// @param epoch number of epoch
    function _checkpoint(uint256 epoch) internal {
        uint numerator = 110; // stub for tests
        uint denominator = 100; // stub for tests
        FixedPoint.uq112x112 memory _ucf = FixedPoint.fraction(numerator, denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        FixedPoint.uq112x112 memory _usf = FixedPoint.fraction(numerator,denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        FixedPoint.uq112x112 memory _df = FixedPoint.fraction(numerator,denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        PointEcomonics memory newPoint = PointEcomonics({ucf: _ucf, usf: _usf, df: _df, ts: block.timestamp, blk: block.number, _exist: false });
        // here we calculate the real UCF,USF from Treasury/Component-Agent-Services ..

        // Calculate UCF, USF
        uint256 ucf;
        uint256 usf;
        {
            // TODO Look for optimization possibilities
            // Calculating UCFc
            ComponentRegistry cRegistry = ComponentRegistry(componentRegistry);
            uint256 numComponents = cRegistry.totalSupply();
            uint256 numProfitableComponents;
            uint256 numServices = protocolServiceIds.length;
            // Array of sum(UCFc(epoch))
            uint256[] memory ucfcs = new uint256[](numServices);
            // Array of cardinality of components in a specific profitable service: |Cs(epoch)|
            uint256[] memory ucfcsNum = new uint256[](numServices);
            // Loop over components
            for (uint256 i = 0; i < numComponents; ++i) {
                (, uint256[] memory serviceIds) = ServiceRegistry(serviceRegistry).getServiceIdsCreatedWithComponentId(cRegistry.tokenByIndex(i));
                bool profitable = false;
                // Loop over services that include the component i
                for (uint256 j = 0; j < serviceIds.length; ++j) {
                    uint256 revenue = mapServiceAmounts[serviceIds[j]];
                    if (revenue > 0) {
                        // Add cit(c, s) * r(s) for component j to add to UCFc(epoch)
                        ucfcs[mapServiceIndexes[j]] += mapServiceAmounts[serviceIds[j]];
                        // Increase |Cs(epoch)|
                        ucfcsNum[mapServiceIndexes[j]]++;
                        profitable = true;
                    }
                }
                // If at least one service has profitable component, increase the component cardinality: Cref(epoch-1)
                if (profitable) {
                    ++numProfitableComponents;
                }
            }
            // Calculate total UCFc
            uint256 ucfc;
            for (uint256 i = 0; i < numServices; ++i) {
                ucfc += ucfcs[mapServiceIndexes[i]] / ucfcsNum[mapServiceIndexes[i]];
            }
            ucfc = ucfc * numProfitableComponents / (numServices * numComponents);

            // Calculating UCFa
            AgentRegistry aRegistry = AgentRegistry(agentRegistry);
            uint256 numAgents = aRegistry.totalSupply();
            uint256 numProfitableAgents;
            // Array of sum(UCFa(epoch))
            uint256[] memory ucfas = new uint256[](numServices);
            // Array of cardinality of components in a specific profitable service: |As(epoch)|
            uint256[] memory ucfasNum = new uint256[](numServices);
            // Loop over agents
            for (uint256 i = 0; i < numAgents; ++i) {
                (, uint256[] memory serviceIds) = ServiceRegistry(serviceRegistry).getServiceIdsCreatedWithAgentId(aRegistry.tokenByIndex(i));
                bool profitable = false;
                // Loop over services that include the agent i
                for (uint256 j = 0; j < serviceIds.length; ++j) {
                    uint256 revenue = mapServiceAmounts[serviceIds[j]];
                    if (revenue > 0) {
                        // Add cit(c, s) * r(s) for component j to add to UCFc(epoch)
                        ucfas[mapServiceIndexes[j]] += mapServiceAmounts[serviceIds[j]];
                        // Increase |Cs(epoch)|
                        ucfasNum[mapServiceIndexes[j]]++;
                        profitable = true;
                    }
                }
                // If at least one service has profitable component, increase the component cardinality: Cref(epoch-1)
                if (profitable) {
                    ++numProfitableAgents;
                }
            }
            // Calculate total UCFa
            uint256 ucfa;
            for (uint256 i = 0; i < numServices; ++i) {
                ucfa += ucfas[mapServiceIndexes[i]] / ucfasNum[mapServiceIndexes[i]];
            }
            ucfa = ucfa * numProfitableAgents / (numServices * numAgents);

            uint256 ucf = (ucfc + ucfa) / 2;

            // Calculating USF
            for (uint256 i = 0; i < numServices; ++i) {
                usf += mapServiceAmounts[protocolServiceIds[i]];
            }
            usf = usf / ServiceRegistry(serviceRegistry).totalSupply();
        }

        // *************** stub for interactions with Registry*
        // Treasury part, I will improve it later
        newPoint._exist = true;
        mapEpochEconomics[epoch] = newPoint;
    }

    // @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation). Any can do it
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @param _epoch epoch number
    /// @return resAmount Resulting amount of OLA tokens.
    function calculatePayoutFromLP(address token, uint256 tokenAmount, uint _epoch) external
        returns (uint256 resAmount)
    {
        PointEcomonics memory _PE = mapEpochEconomics[_epoch];
        if (!_PE._exist) {
            _checkpoint(_epoch);
            _PE = mapEpochEconomics[_epoch];
        }
        uint256 df = uint256(_PE.df._x / MAGIC_DENOMINATOR);
        resAmount = _calculatePayoutFromLP(token, tokenAmount, df);
    }

    /// @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation).
    /// @param token Token address.
    /// @param amount Token amount.
    /// @param df Discount
    /// @return resAmount Resulting amount of OLA tokens.
    function _calculatePayoutFromLP(address token, uint256 amount, uint256 df) internal view
        returns (uint256 resAmount)
    {
        // Calculation of removeLiquidity
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        address token0 = pair.token0();
        address token1 = pair.token1();
        uint256 balance0 = IERC20(token0).balanceOf(address(pair));
        uint256 balance1 = IERC20(token1).balanceOf(address(pair));
        uint256 totalSupply = pair.totalSupply();

        // Using balances ensures pro-rate distribution
        uint256 amount0 = (amount * balance0) / totalSupply;
        uint256 amount1 = (amount * balance1) / totalSupply;

        require(balance0 > amount0, "UniswapV2: INSUFFICIENT_LIQUIDITY token0");
        require(balance1 > amount1, "UniswapV2: INSUFFICIENT_LIQUIDITY token1");

        // Get the initial OLA token amounts
        uint256 amountOLA = (token0 == address(ola)) ? amount0 : amount1;
        uint256 amountPairForOLA = (token0 == address(ola)) ? amount1 : amount0;

        // Calculate swap tokens from the LP back to the OLA token
        balance0 -= amount0;
        balance1 -= amount1;
        uint256 reserveIn = (token0 == address(ola)) ? balance1 : balance0;
        uint256 reserveOut = (token0 == address(ola)) ? balance0 : balance1;
        amountOLA = amountOLA + getAmountOut(amountPairForOLA, reserveIn, reserveOut);

        // Get the resulting amount in OLA tokens
        resAmount = _calculateDF(amountOLA, df);
    }

    // TODO This is the mocking function for the moment
    /// @dev Calculates discount factor.
    /// @param amount Initial OLA token amount.
    /// @param df Discount
    /// @return amountDF OLA amount corrected by the DF.
    function _calculateDF(uint256 amount, uint256 df) internal view returns (uint256 amountDF) {
        require(df < max_df,"df watch dog"); // rewrite later to normal description in english
        amountDF = (amount * df) / E18; // df with decimals 18
        // The discounted amount cannot be smaller than the actual one
        if (amountDF < amount) {
            revert AmountLowerThan(amountDF, amount);
        } 
    }

    // UniswapV2 https://github.com/Uniswap/v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol
    // No license in file
    // forked for Solidity 8.x
    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset

    /// @dev Gets the additional OLA amount from the LP pair token by swapping.
    /// @param amountIn Initial OLA token amount.
    /// @param reserveIn Token amount that is not OLA.
    /// @param reserveOut Token amount in OLA wit fees.
    /// @return amountOut Resulting OLA amount.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee / reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @dev get Point by epoch
    /// @param _epoch number of a epoch
    /// @return _PE raw point
    function getPoint(uint256 _epoch) public view returns (PointEcomonics memory _PE) {
        _PE = mapEpochEconomics[_epoch];
    }

    // decode a uq112x112 into a uint with 18 decimals of precision, 0 if not exist
    function getDF(uint256 _epoch) public view returns (uint256 df) {
        PointEcomonics memory _PE = mapEpochEconomics[_epoch];
        if (_PE._exist) {
            // https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27
            // a/b is encoded as (a << 112) / b or (a * 2^112) / b
            df = uint256(_PE.df._x / MAGIC_DENOMINATOR); // 2^(112 - log2(1e18))
        } else {
            df = 0;
        }
    }

    // decode a uq112x112 into a uint with 18 decimals of precision, re-calc if not exist
    function getDFForEpoch(uint256 _epoch) external returns (uint256 df) {
        PointEcomonics memory _PE = mapEpochEconomics[_epoch];
        if (!_PE._exist) {
            _checkpoint(_epoch);
            _PE = mapEpochEconomics[_epoch];
        }
        // https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27
        // a/b is encoded as (a << 112) / b or (a * 2^112) / b
        df = uint256(_PE.df._x / MAGIC_DENOMINATOR); // 2^(112 - log2(1e18))
    }

}    
