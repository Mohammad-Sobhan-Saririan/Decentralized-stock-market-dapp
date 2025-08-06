// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StockToken
 * @dev An ERC20 token representing a single stock.
 * Only the owner of this contract (the StockMarket contract) can mint or burn tokens.
 */
contract StockToken is ERC20, Ownable {
    /**
     * @dev Sets the initial values for the token and ownership.
     * The initial supply is zero[cite: 37].
     */
    constructor(
        string memory name,
        string memory symbol,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {
        // The ERC20 name and symbol are set (e.g., "Google", "GOOGL").
        // The owner is set to the address of the StockMarket contract.
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`.
     * Can only be called by the owner.
     */
    function mint(address account, uint256 amount) public onlyOwner {
        _mint(account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`.
     * Can only be called by the owner.
     */
    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }
}
