// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IErrors.sol";
// Uniswapv2
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

/// @title Tokenomics - Smart contract for store/interface for key tokenomics params
/// @author AL
contract Tokenimics is IErrors, Ownable {

    event TokenomicsManagerUpdated(address manager);

    struct PointEcomonics {
        FixedPoint.uq112x112 ucf;
        FixedPoint.uq112x112 usf;
        FixedPoint.uq112x112 df; // x > 1.0
        FixedPoint.uq112x112 price;
        uint256 priceCumulative;        
        uint256 ts; // timestamp
        uint256 blk; // block
        bool    _exist; // ready or not
    }

    // OLA interface
    IERC20 public immutable ola;
    // Treasury interface
    ITreasury public treasury;
    // Tokenomics manager
    address public managerDAO; // the usual way
    address public managerDepository; // backup way
    bytes4  private constant FUNC_SELECTOR = bytes4(keccak256("kLast()")); // is pair or pure ERC20?
    uint256 public immutable epoch_len; // epoch len in blk
    uint256 public constant MAGIC_DENOMINATOR =  5192296858534816; // 2^(112 - log2(1e18))  

    // Mapping of epoch => point
    mapping(uint256 => PointEcomonics) public mapEpochEconomics;

    // TODO later fix government / manager
    constructor(address initManager, IERC20 iOLA, ITreasury iTreasury, uint256 _epoch_len) {
        managerDAO = initManager;
        managerDepository = initManager;
        ola = iOLA;
        treasury = iTreasury;
        epoch_len = _epoch_len;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyManager() {
        if (managerDAO != msg.sender) {
            revert ManagerOnly(msg.sender, managerDAO);
        }
        _;
    }

    // Only the manager has a privilege to manipulate a tokenomics
    modifier onlyManagerCheckpoint() {
        if (!(managerDepository == msg.sender || managerDAO == msg.sender)) {
            revert ManagerOnly(msg.sender, managerDepository);
        }
        _;
    }

    /// @dev Changes the tokenomics manager.
    /// @param newManager Address of a new tokenomics manager.
    function changeManagerDAO(address newManager) external onlyOwner {
        managerDAO = newManager;
        emit TokenomicsManagerUpdated(newManager);
    }

    /// @dev Changes the tokenomics manager.
    /// @param newManager Address of a new tokenomics manager.
    function changeManagerDepository(address newManager) external onlyOwner {
        managerDepository = newManager;
        emit TokenomicsManagerUpdated(newManager);
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

    /// @notice Record global data to checkpoint
    /// @dev Checked point exist or not 
    function checkpoint() external onlyManagerCheckpoint {
        uint256 _epoch = block.number / epoch_len;
        PointEcomonics memory lastPoint = mapEpochEconomics[_epoch];
        // if not exist
        if(!lastPoint._exist) {
            _checkpoint(_epoch);
        }
    }

    /// @dev Record global data to new checkpoint
    /// @param _epoch number of epoch
    function _checkpoint(uint256 _epoch) internal {
        uint numerator = 110; // stub for tests
        uint denominator = 100; // stub for tests
        FixedPoint.uq112x112 memory _ucf = FixedPoint.fraction(numerator, denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        FixedPoint.uq112x112 memory _usf = FixedPoint.fraction(numerator,denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        FixedPoint.uq112x112 memory _df = FixedPoint.fraction(numerator,denominator); // uq112x112((uint224(110) << 112) / 100) i.e. 1.1
        PointEcomonics memory newPoint = PointEcomonics({ucf: _ucf, usf: _usf, df: _df, price: FixedPoint.fraction(1, 1), priceCumulative: 0, ts: block.timestamp, blk: block.number, _exist: false });
        // here we calculate the real UCF,USF from Treasury/Component-Agent-Services ..
        // *************** stub for interactions with Registry*
        // Treasury part, I will improve it later
        (newPoint.price, newPoint.priceCumulative) = _CumulativePricesFromHistoryPoint(_epoch); 
        newPoint._exist = true;
        mapEpochEconomics[_epoch] = newPoint;
    }

    /// @dev produces the price for point
    /// @param _epoch number of epoch
    /// @return price0Average average price in form of fixed point 112.112
    /// @return price0Cumulative cumulative price as uint
    function _CumulativePricesFromHistoryPoint(uint256 _epoch) internal returns (FixedPoint.uq112x112 memory price0Average, uint256 price0Cumulative) {
        uint timeElapsed;
        uint256 price0CumulativeLast;
        address[] memory tokensInTreasury = treasury.getTokenRegistry(); // list of trusted pairs
        PointEcomonics memory prePoint = mapEpochEconomics[_epoch-1];

        if(_epoch > 0) {    
            if(!prePoint._exist) {
                price0CumulativeLast = prePoint.priceCumulative;
                timeElapsed = block.timestamp - prePoint.ts;
            } else {
                price0CumulativeLast = 0;
                timeElapsed = 1;        
            }
        } else {
            price0CumulativeLast = 0;
            timeElapsed = 1;
        }
        
        for (uint256 i = 0; i < tokensInTreasury.length; i++) {
            if(treasury.isEnabled(tokensInTreasury[i]) && callDetectPair(tokensInTreasury[i])) {
                // part for LP tokens 
                // OLA in trusted pair can be token0 or token1
                address addrTmp = IUniswapV2Pair(tokensInTreasury[i]).token0();
                if (addrTmp == address(ola)) { // re-check order price vs token!
                    (price0Cumulative,,) = _currentCumulativePrices(tokensInTreasury[i]);
                    if(price0Cumulative > price0CumulativeLast) {
                        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
                    } else {
                        price0Average = FixedPoint.uq112x112(uint224((price0CumulativeLast - price0Cumulative) / timeElapsed));
                    }
                } else {

                    if(price0Cumulative > price0CumulativeLast) {
                        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
                    } else {
                        price0Average = FixedPoint.uq112x112(uint224((price0CumulativeLast - price0Cumulative) / timeElapsed));
                    }
                }
                break; // multi-LP (i.e. OLA-DAI, OLA-ETH, OLA-USDC, .. in single Treasury/Bonding) not supported yet, or neeed nested map
            }
        }
    } 


    /// @dev produces the cumulative price
    /// @param pair LPToken/Pool address.
    /// @return price0Cumulative cumulative price token0
    /// @return price1Cumulative cumulative price token1
    /// @return blockTimestamp current block.timestamp
    function _currentCumulativePrices(address pair) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp =  uint32(block.timestamp);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
        if (blockTimestamp > blockTimestampLast) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }

    /// @dev get Point by epoch
    /// @param _epoch number of a epoch
    /// @return _PE raw point
    function getPoint(uint256 _epoch) public view returns (PointEcomonics memory _PE) {
        _PE = mapEpochEconomics[_epoch];
    }

    // decode a uq112x112 into a uint with 18 decimals of precision
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

    // decode a uq112x112 into a uint with 18 decimals of precision
    function getDFForEpoch(uint256 _epoch) external onlyManagerCheckpoint returns (uint256 df) {
        PointEcomonics memory _PE = mapEpochEconomics[_epoch];
        if (_PE._exist) {
            // https://github.com/compound-finance/open-oracle/blob/d0a0d0301bff08457d9dfc5861080d3124d079cd/contracts/Uniswap/UniswapLib.sol#L27
            // a/b is encoded as (a << 112) / b or (a * 2^112) / b
            df = uint256(_PE.df._x / MAGIC_DENOMINATOR); // 2^(112 - log2(1e18))
        } else {
            _checkpoint(_epoch);
            _PE = mapEpochEconomics[_epoch];
            df = uint256(_PE.df._x / MAGIC_DENOMINATOR); 
        }
    }

    function getEpochLen() external view returns (uint256) {
        return epoch_len;
    }

}    
