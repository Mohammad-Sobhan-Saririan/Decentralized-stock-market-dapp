// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Import the contract we want to test
import "./StockMarket.sol"; // This is the FILENAME, it's correct.
// Import Remix's testing library
import "remix_tests.sol";
import "remix_accounts.sol";

contract TestStockMarket {
    // UPDATED: Use your new contract name here
    SadraSobhanStockMarket stockMarket;

    // This function runs before each test
    function beforeEach() public {
        // UPDATED: Deploy a new instance of your contract
        stockMarket = new SadraSobhanStockMarket();
    }

    /// #sender: account-0
    function testInitialOwner() public {
        Assert.equal(
            stockMarket.owner(),
            TestsAccounts.getAccount(0),
            "Owner should be account-0"
        );
    }

    /// #sender: account-0
    function testOwnerCanAddStock() public {
        stockMarket.addStock("Google", "GOOGL");
        (string memory name, , , bool isListed, , ) = stockMarket.stocks(
            "GOOGL"
        );
        Assert.equal(name, "Google", "Stock name should be Google");
        Assert.ok(isListed, "Stock should be listed");
    }

    /// #sender: account-1
    function testNonOwnerCannotAddStock() public {
        try stockMarket.addStock("Apple", "AAPL") {
            Assert.ok(false, "Non-owner should not be able to add a stock.");
        } catch Error(string memory reason) {
            Assert.equal(
                reason,
                "Ownable: caller is not the owner",
                "Revert reason is incorrect."
            );
        }
    }

    /// #sender: account-0
    function testAddStockCreatesToken() public {
        stockMarket.addStock("Tesla", "TSLA");
        (, , address tokenAddr, bool isListed, , ) = stockMarket.stocks("TSLA");
        Assert.notEqual(
            tokenAddr,
            address(0),
            "Token address should not be zero."
        );
        Assert.ok(isListed, "Stock should be listed");

        StockToken token = StockToken(tokenAddr);
        Assert.equal(token.name(), "Tesla", "Token name should be 'Tesla'");
        Assert.equal(token.symbol(), "TSLA", "Token symbol should be 'TSLA'");
    }

    /// #sender: account-0
    function testSimulatedPriceUpdate() public {
        stockMarket.addStock("Microsoft", "MSFT");
        uint256 simulatedPrice = 450 * 10 ** 8;
        stockMarket._test_updatePrice("MSFT", simulatedPrice); // Calling the test-only function
        (, , , , uint256 price, uint256 lastUpdated) = stockMarket.stocks(
            "MSFT"
        );
        Assert.equal(
            price,
            simulatedPrice,
            "The price was not updated correctly."
        );
        Assert.notEqual(
            lastUpdated,
            0,
            "The lastUpdated timestamp should not be zero."
        );
    }
}
