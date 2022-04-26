// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/IErrors.sol";

/// @title OLA - Smart contract for the main OLA token
/// @author AL
contract OLA is IErrors, Context, Ownable, ERC20, ERC20Burnable, ERC20Permit {
    event TreasuryUpdated(address treasury);

    // One year interval
    uint256 public constant oneYear = 1 days * 365;
    // Ten years interval
    uint256 public constant tenYears = 10 * oneYear;
    // Total supply cap for the first ten years (one billion OLA tokens)
    uint256 public constant supplyCap = 1_000_000_000e18;
    // Total supply after ten years (changed only once)
    uint256 public totalSupplyAfterTenYears;
    // Maximum mint amount after first ten years
    uint256 public constant maxMintCapFraction = 2;
    // Initial timestamp of the token deployment
    uint256 public timeLaunch;

    // Treasury address
    address public treasury;

    constructor(uint256 _supply, address _treasury) ERC20("OLA Token", "OLA") ERC20Permit("OLA Token") {
        treasury = _treasury;
        timeLaunch = block.timestamp;
        if (_supply > 0) {
            mint(msg.sender, _supply);
        }
    }

    modifier onlyManager() {
        if (msg.sender != treasury && msg.sender != owner()) {
            revert ManagerOnly(msg.sender, treasury);
        }
        _;
    }

    /// @dev Changes the treasury address.
    /// @param newTreasury Address of a new treasury.
    function changeTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
        emit TreasuryUpdated(treasury);
    }

    /// @dev Mints OLA tokens.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function mint(address account, uint256 amount) public onlyManager {
        _inflationControl(amount);
        super._mint(account, amount);
    }

    /// @dev Burns OLA tokens.
    /// @param amount OLA token amount.
    function burn(uint256 amount) public override {
        super._burn(msg.sender, amount);
        _adjustTotalSupply();
    }

    /// @dev Burns OLA tokens from a specific address.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
        _adjustTotalSupply();
    }

    /// @dev Provides various checks for the inflation control.
    /// @param amount Amount of OLA to mint.
    function _inflationControl(uint256 amount) internal {
        // Scenario for the first ten years
        uint256 totalSupply = super.totalSupply();
        if (block.timestamp - timeLaunch < tenYears) {
            if (totalSupply + amount > supplyCap) {
                // Check for the requested mint overflow
                revert WrongAmount(totalSupply + amount, supplyCap);
            }
        } else {
            // Set the "initial" total supply after ten years if it was not yet set
            if (totalSupplyAfterTenYears == 0) {
                totalSupplyAfterTenYears = totalSupply;
            }
            // Number of years after ten years have passed
            uint256 numYears = (block.timestamp - tenYears - timeLaunch) / oneYear + 1;
            // Calculate maximum mint amount to date
            uint256 maxSupplyCap = totalSupplyAfterTenYears;
            for (uint256 i = 0; i < numYears; ++i) {
                maxSupplyCap += maxSupplyCap * maxMintCapFraction / 100;
            }
            if (totalSupply + amount > maxSupplyCap) {
                // Check for the requested mint overflow
                revert WrongAmount(totalSupply + amount, maxSupplyCap);
            }
        }
    }

    /// @dev Adjusts total supply after burn, if needed.
    function _adjustTotalSupply() internal {
        // If we passed ten years and the total supply dropped below, we need to adjust the end-of-ten-year supply
        uint256 totalSupply = super.totalSupply();
        if (totalSupplyAfterTenYears > 0 && totalSupplyAfterTenYears > totalSupply) {
            totalSupplyAfterTenYears = totalSupply;
        }
    }
}
