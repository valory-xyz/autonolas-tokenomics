// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./interfaces/IService.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IErrors.sol";
import "./interfaces/IStructs.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";



/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
contract Tokenomics is IErrors, IStructs, Ownable {
    using FixedPoint for *;

    event TreasuryUpdated(address treasury);
    event DepositoryUpdated(address depository);

    // OLA token address
    address public immutable ola;
    // Treasury contract address
    address public treasury;
    // Depository contract address
    address public depository;

    bytes4  private constant FUNC_SELECTOR = bytes4(keccak256("kLast()")); // is pair or pure ERC20?
    uint256 public immutable epochLen; // epoch len in blk
    // source: https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27 
    // 2^(112 - log2(1e18))
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816;
    uint256 public constant INITIAL_DF = (110 * 10**18) / 100; // 10% with 18 decimals
    uint256 public maxBond = 2000000 * 10**18; // 2M OLA with 18 decimals
    // Epsilon subject to rounding error
    uint256 public constant E13 = 10**13;
    // Maximum precision number to be considered
    uint256 public constant E18 = 10**18;
    // Default max DF of 200% rounded with epsilon of E13
    uint256 public maxDF = 2 * E18 + E13;

    // 1.0 by default
    FixedPoint.uq112x112 public alpha = FixedPoint.fraction(1, 1);
    // 1 by default, a == a^1
    uint256 public beta = 1;
    FixedPoint.uq112x112 public gamma = FixedPoint.fraction(1, 1);

    // Total service revenue per epoch: sum(r(s))
    uint256 public totalServiceRevenueETH;

    // Staking parameters with multiplying by 100
    // treasuryFraction + componentFraction + agentFraction + stakerFraction = 100%
    uint256 public treasuryFraction = 0;
    uint256 public stakerFraction = 50;
    uint256 public componentFraction = 33;
    uint256 public agentFraction = 17;

    //Discount Factor v2
    //Bond(t)
    uint256 private _bondPerEpoch;
    // MaxBond(e) - sum(BondingProgram)
    uint256 private _bondLeft = maxBond;

    // Component Registry
    address public immutable componentRegistry;
    // Agent Registry
    address public immutable agentRegistry;
    // Service Registry
    address payable public immutable serviceRegistry;
    
    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;
    // Set of UCFc(epoch)
    uint256[] private _ucfcs;
    // Set of UCFa(epoch)
    uint256[] private _ucfas;
    // Set of profitable components in current epoch
    address[] private _profitableComponents;
    // Set of profitable agents in current epoch
    address[] private _profitableAgents;
    // Set of protocol-owned services in current epoch
    uint256[] private _protocolServiceIds;
    // Map of service Ids and their amounts in current epoch
    mapping(uint256 => uint256) private _mapServiceAmounts;
    mapping(uint256 => uint256) private _mapServiceIndexes;

    // TODO sync address constants with other contracts
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // TODO later fix government / manager
    constructor(address _ola, address _treasury, address _depository, uint256 _epochLen, address _componentRegistry, address _agentRegistry,
        address payable _serviceRegistry)
    {
        ola = _ola;
        treasury = _treasury;
        depository = _depository;
        epochLen = _epochLen;
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        serviceRegistry = _serviceRegistry;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyTreasury() {
        if (treasury != msg.sender) {
            revert ManagerOnly(msg.sender, treasury);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyDepository() {
        if (depository != msg.sender) {
            revert ManagerOnly(msg.sender, depository);
        }
        _;
    }

    /// @dev Changes treasury address.
    function changeTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    /// @dev Changes treasury address.
    function changeDepository(address newDepository) external onlyOwner {
        depository = newDepository;
        emit DepositoryUpdated(newDepository);
    }

    /// @dev Gets curretn epoch number.
    function getEpoch() public view returns (uint256 epoch) {
        epoch = block.number / epochLen;
    }

    /// @dev Changes tokenomics parameters.
    /// @param _alphaNumerator Numerator for alpha value.
    /// @param _alphaDenominator Denominator for alpha value.
    /// @param _beta Beta value.
    /// @param _gammaNumerator Numerator for gamma value.
    /// @param _gammaDenominator Denominator for gamma value.
    /// @param _maxDF Maximum interest rate in %, 18 decimals.
    /// @param _maxBond MaxBond OLA, 18 decimals
    function changeTokenomicsParameters(
        uint256 _alphaNumerator,
        uint256 _alphaDenominator,
        uint256 _beta,
        uint256 _gammaNumerator,
        uint256 _gammaDenominator,
        uint256 _maxDF,
        uint256 _maxBond
    ) external onlyOwner {
        alpha = FixedPoint.fraction(_alphaNumerator, _alphaDenominator);
        beta = _beta;
        gamma = FixedPoint.fraction(_gammaNumerator, _gammaDenominator);
        maxDF = _maxDF + E13;
        // take into account the change during the epoch
        if(_maxBond > maxBond) {
            uint256 delta = _maxBond - maxBond;
            _bondLeft += delta; 
        }
        if(_maxBond < maxBond) {
            uint256 delta = maxBond - _maxBond;
            if(delta < _bondLeft) {
                _bondLeft -= delta;
            } else {
                _bondLeft = 0;
            }
        }
        maxBond = _maxBond;
    }

    /// @dev Sets staking parameters in fractions of distributed rewards.
    /// @param _stakerFraction Fraction for stakers.
    /// @param _componentFraction Fraction for component owners.
    function changeRewardFraction(
        uint256 _treasuryFraction,
        uint256 _stakerFraction,
        uint256 _componentFraction,
        uint256 _agentFraction
    ) external onlyOwner {
        // Check that the sum of fractions is 100%
        if (_treasuryFraction + _stakerFraction + _componentFraction + _agentFraction != 100) {
            revert WrongAmount(_treasuryFraction + _stakerFraction + _componentFraction + _agentFraction, 100);
        }

        treasuryFraction = _treasuryFraction;
        stakerFraction = _stakerFraction;
        componentFraction = _componentFraction;
        agentFraction = _agentFraction;
    }

    /// @dev take into account the bonding program in this epoch. 
    /// @dev programs exceeding the limit in the epoch are not allowed
    function allowedNewBond(uint256 amount) external onlyDepository returns (bool)  {
        if(_bondLeft >= amount) {
            _bondLeft -= amount;
            return true;
        }
        return false;
    }

    /// @dev take into account materialization OLA per Depository.deposit() for currents program
    function usedBond(uint256 payout) external onlyDepository {
        _bondPerEpoch += payout;
    }

    /// @dev Tracks the deposit token amount during the epoch.
    function trackServicesETHRevenue(uint256[] memory serviceIds, uint256[] memory amounts)
        public onlyTreasury {
        // Loop over service Ids and track their amounts
        uint256 numServices = serviceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            // Check for the service Id existance
            if (!IService(serviceRegistry).exists(serviceIds[i])) {
                revert ServiceDoesNotExist(serviceIds[i]);
            }

            // Add a new service Id to the set of Ids if one was not currently in it
            if (_mapServiceAmounts[serviceIds[i]] == 0) {
                _mapServiceIndexes[serviceIds[i]] = _protocolServiceIds.length;
                _protocolServiceIds.push(serviceIds[i]);
            }
            _mapServiceAmounts[serviceIds[i]] += amounts[i];

            // Increase also the total service revenue
            totalServiceRevenueETH += amounts[i];
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

    function _calculateUCFc() private returns (FixedPoint.uq112x112 memory ucfc) {
        uint256 numComponents = IERC721Enumerable(componentRegistry).totalSupply();
        uint256 numProfitableComponents;
        uint256 numServices = _protocolServiceIds.length;

        // Clear the previous epoch profitable set of components
        delete _profitableComponents;
        delete _ucfcs;

        // Allocate set of UCFc for the current epoch number of services
        _ucfcs = new uint256[](numServices);
        // Array of cardinality of components in a specific profitable service: |Cs(epoch)|
        uint256[] memory ucfcsNum = new uint256[](numServices);

        // Loop over components
        for (uint256 i = 0; i < numComponents; ++i) {
            uint256 componentId = IERC721Enumerable(componentRegistry).tokenByIndex(i);
            (, uint256[] memory serviceIds) = IService(serviceRegistry).getServiceIdsCreatedWithComponentId(componentId);
            bool profitable = false;
            // Loop over services that include the component i
            for (uint256 j = 0; j < serviceIds.length; ++j) {
                uint256 revenue = _mapServiceAmounts[serviceIds[j]];
                if (revenue > 0) {
                    // Add cit(c, s) * r(s) for component j to add to UCFc(epoch)
                    _ucfcs[_mapServiceIndexes[serviceIds[j]]] += _mapServiceAmounts[serviceIds[j]];
                    // Increase |Cs(epoch)|
                    ucfcsNum[_mapServiceIndexes[serviceIds[j]]]++;
                    profitable = true;
                }
            }
            // If at least one service has profitable component, increase the component cardinality: Cref(epoch-1)
            if (profitable) {
                // Add address of a profitable component owner
                address owner = IERC721Enumerable(componentRegistry).ownerOf(componentId);
                _profitableComponents.push(owner);
                // Increase the profitable component number
                ++numProfitableComponents;
            }
        }

        uint256 denominator;
        // Calculate total UCFc
        for (uint256 i = 0; i < numServices; ++i) {
            denominator = ucfcsNum[_mapServiceIndexes[_protocolServiceIds[i]]];
            if(denominator > 0) {
                // avoid exception div by zero
                ucfc = _add(ucfc, FixedPoint.fraction(_ucfcs[_mapServiceIndexes[_protocolServiceIds[i]]], denominator));
            }
        }
        ucfc = ucfc.muluq(FixedPoint.fraction(1, totalServiceRevenueETH));
        denominator = numServices * numComponents;
        if(denominator > 0) {
            // avoid exception div by zero
            ucfc = ucfc.muluq(FixedPoint.fraction(numProfitableComponents, denominator));
        } else {
            ucfc = FixedPoint.fraction(0, 1);
        }
    }

    function _calculateUCFa() private returns (FixedPoint.uq112x112 memory ucfa) {
        uint256 numAgents = IERC721Enumerable(agentRegistry).totalSupply();
        uint256 numProfitableAgents;
        uint256 numServices = _protocolServiceIds.length;

        // Clear the previous epoch profitable set of agents
        delete _profitableAgents;
        delete _ucfas;

        // Allocate set of UCFa for the current epoch number of services
        _ucfas = new uint256[](numServices);
        // Array of cardinality of components in a specific profitable service: |As(epoch)|
        uint256[] memory ucfasNum = new uint256[](numServices);
        
        // Loop over agents
        for (uint256 i = 0; i < numAgents; ++i) {
            uint256 agentId = IERC721Enumerable(agentRegistry).tokenByIndex(i);
            (, uint256[] memory serviceIds) = IService(serviceRegistry).getServiceIdsCreatedWithAgentId(agentId);
            bool profitable = false;
            // Loop over services that include the agent i
            for (uint256 j = 0; j < serviceIds.length; ++j) {
                uint256 revenue = _mapServiceAmounts[serviceIds[j]];
                if (revenue > 0) {
                    // Add cit(c, s) * r(s) for component j to add to UCFa(epoch)
                    _ucfas[_mapServiceIndexes[serviceIds[j]]] += _mapServiceAmounts[serviceIds[j]];
                    // Increase |As(epoch)|
                    ucfasNum[_mapServiceIndexes[serviceIds[j]]]++;
                    profitable = true;
                }
            }
            // If at least one service has profitable component, increase the component cardinality: Cref(epoch-1)
            if (profitable) {
                // Add address of a profitable component owner
                address owner = IERC721Enumerable(agentRegistry).ownerOf(agentId);
                _profitableAgents.push(owner);
                // Increase a profitable agent number
                ++numProfitableAgents;
            }
        }

        uint256 denominator;
        // Calculate total UCFa
        for (uint256 i = 0; i < numServices; ++i) {
            denominator = ucfasNum[_mapServiceIndexes[_protocolServiceIds[i]]];
            if(denominator > 0) {
                // avoid div by zero
                ucfa = _add(ucfa, FixedPoint.fraction(_ucfas[_mapServiceIndexes[_protocolServiceIds[i]]], denominator));
            }
        }
        ucfa = ucfa.muluq(FixedPoint.fraction(1, totalServiceRevenueETH));
        denominator = numServices * numAgents;
        if(denominator > 0) {
            // avoid div by zero
            ucfa = ucfa.muluq(FixedPoint.fraction(numProfitableAgents, denominator));
        } else {
            ucfa = FixedPoint.fraction(0, 1);
        }
    }

    /// @dev calc df by WD Math formula UCF, USF, DF v1 
    /// @param dcm direct contribution measure DCM(t) by first version 
    function _calculateDFv1(FixedPoint.uq112x112 memory dcm) internal view returns (FixedPoint.uq112x112 memory df) {
        // alpha * DCM(t)^beta + gamma
        FixedPoint.uq112x112 memory _one = FixedPoint.fraction(1, 1);
        df = _pow(dcm, beta);
        df = _add(_one, df.muluq(alpha));
        df = _add(df, gamma);
    }

    /// @dev Sums two fixed points.
    function _add(FixedPoint.uq112x112 memory x, FixedPoint.uq112x112 memory y) private pure
        returns (FixedPoint.uq112x112 memory r)
    {
        uint224 z = x._x + y._x;
        if(x._x > 0 && y._x > 0) assert(z > x._x && z > y._x);
        return FixedPoint.uq112x112(uint224(z));
    }

    /// @dev Pow of a fixed point.
    function _pow(FixedPoint.uq112x112 memory a, uint b) internal pure returns (FixedPoint.uq112x112 memory c) {
        if(b == 0) {
            return FixedPoint.fraction(1, 1);
        }

        if(b == 1) {
            return a;
        }

        c = FixedPoint.fraction(1, 1);
        while(b > 0) {
            // b % 2
            if((b & 1) == 1) {
                c = c.muluq(a);
            }
            a = a.muluq(a);
            // b = b / 2;
            b >>= 1;
        }
        return c;
    }

    /// @dev Clears necessary data structures for the next epoch.
    function _clearEpochData() internal {
        uint256 numServices = _protocolServiceIds.length;
        for (uint256 i = 0; i < numServices; ++i) {
            delete _mapServiceAmounts[_protocolServiceIds[i]];
            delete _mapServiceIndexes[_protocolServiceIds[i]];
        }
        delete _protocolServiceIds;
        totalServiceRevenueETH = 0;
        // clean bonding data
        _bondLeft = maxBond;
        _bondPerEpoch = 0;
    }

    /// @notice Record global data to checkpoint, any can do it
    /// @dev Checked point exist or not 
    function checkpoint() external onlyTreasury {
        uint256 epoch = getEpoch();
        PointEcomonics memory lastPoint = mapEpochEconomics[epoch];
        // if not exist
        if(!lastPoint.exists) {
            _checkpoint(epoch);
        }
    }

    /// @dev Record global data to new checkpoint
    /// @param epoch number of epoch
    function _checkpoint(uint256 epoch) internal {
        FixedPoint.uq112x112 memory _ucf;
        FixedPoint.uq112x112 memory _usf;
        FixedPoint.uq112x112 memory _dcm;
        // df = 1/(1 + iterest_rate) by documantation, reverse_df = 1/df >= 1.0.
        FixedPoint.uq112x112 memory _df;

        // Calculate UCF, USF
        // TODO Look for optimization possibilities
        if (totalServiceRevenueETH > 0) {
            // Calculate total UCFc
            FixedPoint.uq112x112 memory _ucfc = _calculateUCFc();

            // Calculate total UCFa
            FixedPoint.uq112x112 memory _ucfa = _calculateUCFa();

            // Overall UCF calculation
            //_ucf = (_ucfc + _ucfa) / 2;
            FixedPoint.uq112x112 memory _two = FixedPoint.fraction(2, 1);
            _ucf = _add(_ucfc, _ucfa);
            if (_ucf._x > 0) {
                _ucf = _ucf.divuq(_two);
            }
            // Calculating USF
            uint256 numServices = _protocolServiceIds.length;
            uint256 usf;
            for (uint256 i = 0; i < numServices; ++i) {
                usf += _mapServiceAmounts[_protocolServiceIds[i]];
            }
            uint256 denominator = totalServiceRevenueETH * IERC721Enumerable(serviceRegistry).totalSupply();
            if(denominator > 0) {
                // _usf = usf / IERC721Enumerable(serviceRegistry).totalSupply();
                _usf =  FixedPoint.fraction(usf, denominator);
            }
            //_dcm = (_ucf + _usf) / 2;
            _dcm = _add(_ucf,_usf);
            if (_dcm._x > 0) {
                _dcm = _ucf.divuq(_two);
            }
        }

        uint256 totalRewardOLA = _getExchangeAmountOLA(ETH_TOKEN_ADDRESS, totalServiceRevenueETH);
        _df = _calculateDFv1(_dcm);
        PointEcomonics memory newPoint = PointEcomonics(_ucf, _usf, _df, treasuryFraction, stakerFraction,
            componentFraction, agentFraction, totalRewardOLA, block.timestamp, block.number, true);
        mapEpochEconomics[epoch] = newPoint;

        _clearEpochData();
    }

    // @dev Calculates the amount of OLA tokens based on LP (see the doc for explanation of price computation). Any can do it
    /// @param token Token address.
    /// @param tokenAmount Token amount.
    /// @param _epoch epoch number
    /// @return resAmount Resulting amount of OLA tokens.
    function calculatePayoutFromLP(address token, uint256 tokenAmount, uint _epoch) external view
        returns (uint256 resAmount)
    {
        uint256 df;
        PointEcomonics memory _PE;
        // avoid start checkpoint from calculatePayoutFromLP
        uint256 _epochC = _epoch + 1; 
        for (uint256 i = _epochC; i > 0; i--) {
            _PE = mapEpochEconomics[i-1];
            // if current point undefined, so calculatePayoutFromLP called before mined tx(checkpoint)
            if(_PE.exists) {
                df = uint256(_PE.df._x / MAGIC_DENOMINATOR);
                break;
            }
        }
        if(df > 0) {
            resAmount = _calculatePayoutFromLP(token, tokenAmount, df);
        } else {
            // if df undefined in points
            resAmount = _calculatePayoutFromLP(token, tokenAmount, INITIAL_DF);
        }
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
        uint256 amountOLA = (token0 == ola) ? amount0 : amount1;
        uint256 amountPairForOLA = (token0 == ola) ? amount1 : amount0;

        // Calculate swap tokens from the LP back to the OLA token
        balance0 -= amount0;
        balance1 -= amount1;
        uint256 reserveIn = (token0 == ola) ? balance1 : balance0;
        uint256 reserveOut = (token0 == ola) ? balance0 : balance1;
        
        amountOLA = amountOLA + getAmountOut(amountPairForOLA, reserveIn, reserveOut);

        // The resulting DF amount cannot be bigger than the maximum possible one
        if (df > maxDF) {
            revert AmountLowerThan(maxDF, df);
        }

        // Get the resulting amount in OLA tokens
        resAmount = (amountOLA * df) / E18; // df with decimals 18

        // The discounted amount cannot be smaller than the actual one
        if (resAmount < amountOLA) {
            revert AmountLowerThan(resAmount, amountOLA);
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

    /// @dev Get last epoch Point.
    function getLastPoint() external view returns (PointEcomonics memory _PE) {
        uint256 epoch = getEpoch();
        _PE = mapEpochEconomics[epoch];
    }

    // decode a uq112x112 into a uint with 18 decimals of precision (cycle into the past), INITIAL_DF if not exist
    function getDF(uint256 _epoch) public view returns (uint256 df) {
        PointEcomonics memory _PE;
        uint256 _epochC = _epoch + 1; 
        for (uint256 i = _epochC; i > 0; i--) {
            _PE = mapEpochEconomics[i-1];
            // if current point undefined, so getDF called before mined tx(checkpoint)
            if(_PE.exists) {
                // https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27
                // a/b is encoded as (a << 112) / b or (a * 2^112) / b
                df = uint256(_PE.df._x / MAGIC_DENOMINATOR);
                break;
            }
        }
        if (df == 0) {
            df = INITIAL_DF;
        }
    }

    /// @dev Gets exchange rate for OLA.
    /// @param token Token address to be exchanged for OLA.
    /// @param tokenAmount Token amount.
    /// @return amountOLA Amount of OLA tokens.
    function _getExchangeAmountOLA(address token, uint256 tokenAmount) private pure returns (uint256 amountOLA) {
        // TODO Exchange rate is a stub for now
        amountOLA = tokenAmount;
    }

    function getProfitableComponents() external view
        returns (address[] memory profitableComponents, uint256[] memory ucfcs)
    {
        profitableComponents = _profitableComponents;
        ucfcs = _ucfcs;
    }

    function getProfitableAgents() external view
        returns (address[] memory profitableAgents, uint256[] memory ucfas)
    {
        profitableAgents = _profitableAgents;
        ucfas = _ucfas;
    }

    function getBondLeft() external view returns (uint256 bondLeft) {
        bondLeft = _bondLeft;
    }

    function getBondCurrentEpoch() external view returns (uint256 bondPerEpoch) {
        bondPerEpoch = _bondPerEpoch;
    }
}    
