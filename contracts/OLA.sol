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
    // TODO Maximum possible number of tokens
    // uint256 public constant maxSupply = 500000000e18; // 500 million OLA
    event TreasuryUpdated(address indexed treasury);

    address public treasury;

    constructor() ERC20("OLA Token", "OLA") ERC20Permit("OLA Token") {
        treasury = msg.sender;
    }

    // TODO Do we allow minting to something other than treasury? What about airdrop? Multiple airdrops?
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
        super._mint(account, amount);
    }

    /// @dev Burns OLA tokens.
    /// @param amount OLA token amount.
    function burn(uint256 amount) public override {
        super._burn(msg.sender, amount);
    }

    /// @dev Burns OLA tokens from a specific address.
    /// @param account Account address.
    /// @param amount OLA token amount.
    function burnFrom(address account, uint256 amount) public override {
        super.burnFrom(account, amount);
    }
}
