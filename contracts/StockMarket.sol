// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// OpenZeppelin imports
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Chainlink imports
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
// import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

// Local import
import "./StockToken.sol";

/**
 * @title StockMarket
 * @dev Manages stocks and fetches their real-world prices using Chainlink oracles.
 */
contract SadraSobhanStockMarket is Ownable, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    // --- Data Structures ---
    struct Stock {
        string name;
        string symbol;
        address tokenAddress;
        bool isListed;
        uint256 price; // Current price with 8 decimals
        uint256 lastUpdated; // Timestamp of the last price update
    }

    // --- Events ---
    event StockAdded(
        string indexed symbol,
        string name,
        address indexed tokenAddress
    );
    event StockRemoved(string indexed symbol);
    // Event for when a price is successfully updated by the oracle
    event PriceUpdated(string indexed symbol, uint256 price, uint256 timestamp);
    // Event to track oracle requests
    event PriceRequestSent(bytes32 indexed requestId, string indexed symbol);

    event DebugLog(string message);
    event DebugString(string label, string value);
    event DebugUint(string label, uint256 value);

    // --- State Variables ---
    mapping(string => Stock) public stocks;
    string[] public listedStockSymbols;
    IERC20 public paymentToken;

    // Mapping from a request ID to the symbol it's for
    mapping(bytes32 => string) private pendingRequests;

    // Configurable period after which a price is considered stale
    uint256 public priceTimeout;

    // Chainlink Job ID for fetching data from an API
    bytes32 private jobId;
    // Fee in LINK tokens to pay the oracle
    uint256 private fee;

    // --- Constructor ---
    // Sets the owner, Chainlink token, and oracle addresses for Sepolia testnet.
    constructor() Ownable(msg.sender) {
        _setChainlinkToken(0x779877A7B0D9E8603169DdbD7836e478b4624789);
        _setChainlinkOracle(0x6090149792dAAeE9D1D568c9f9a6F6B46AA29eFD);
        priceTimeout = 3600;
        fee = 0.1 * 10 ** 18;
    }

    // --- Owner Functions ---

    function setPaymentToken(address _tokenAddress) public onlyOwner {
        paymentToken = IERC20(_tokenAddress);
    }

    /**
     * @dev Sets the Chainlink Job ID and fee.
     */
    function setChainlinkDetails(
        bytes32 _jobId,
        uint256 _fee
    ) public onlyOwner {
        jobId = _jobId;
        fee = _fee;
    }

    /**
     * @dev Sets how long a price is considered valid, in seconds.
     */
    function setPriceTimeout(uint256 _timeoutInSeconds) public onlyOwner {
        priceTimeout = _timeoutInSeconds;
    }

    function addStock(
        string memory _name,
        string memory _symbol
    ) public onlyOwner {
        require(
            !stocks[_symbol].isListed,
            "Stock with this symbol already exists."
        );
        StockToken newStockToken = new StockToken(
            _name,
            _symbol,
            address(this)
        );
        stocks[_symbol] = Stock({
            name: _name,
            symbol: _symbol,
            tokenAddress: address(newStockToken),
            isListed: true,
            price: 0,
            lastUpdated: 0
        });
        listedStockSymbols.push(_symbol);
        emit StockAdded(_symbol, _name, address(newStockToken));
    }

    // --- Oracle Functions ---

    /**
     * @dev Creates a Chainlink request to fetch a stock's price.
     * This function is where you will use your Alphavantage API key.
     */
    function requestPriceUpdate(string memory _symbol) public onlyOwner {
        require(stocks[_symbol].isListed, "Stock is not listed.");

        uint256 linkBalance = LinkTokenInterface(_chainlinkTokenAddress())
            .balanceOf(address(this));
        emit DebugUint("LINK Balance", linkBalance);
        emit DebugUint("Fee Required", fee);

        require(linkBalance >= fee, "Not enough LINK to pay fee.");

        string memory url = string(
            abi.encodePacked(
                "https://www.alphavantage.co/query?function=GLOBAL_QUOTE&symbol=",
                _symbol,
                "&apikey=MM9LNL8023N1N97E"
            )
        );

        emit DebugString("Constructed URL", url);

        Chainlink.Request memory req = _buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        emit DebugLog("Request object created");

        req._add("get", url);
        emit DebugLog("GET param added");

        // req._add("path", "Global Quote.05. price");
        req._add("path", "Global Quote,05. price");
        emit DebugLog("Path param added");

        req._addInt("times", 10 ** 8);
        emit DebugLog("Times param added");

        bytes32 requestId = _sendChainlinkRequest(req, fee);
        emit DebugString("Request ID sent", bytes32ToString(requestId));

        pendingRequests[requestId] = _symbol;
        emit PriceRequestSent(requestId, _symbol);
    }

    function bytes32ToString(
        bytes32 _bytes32
    ) public pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    /**
     * @dev The callback function that the Chainlink oracle calls with the price data.
     */
    function fulfill(
        bytes32 _requestId,
        uint256 _price
    ) public recordChainlinkFulfillment(_requestId) {
        emit DebugLog("FULFILL STARTED");
        string memory symbol = pendingRequests[_requestId];
        emit DebugString("FULFILL CALLED", Strings.toString(_price));

        // Update the stock's price and timestamp
        stocks[symbol].price = _price;
        stocks[symbol].lastUpdated = block.timestamp;

        // Clean up
        delete pendingRequests[_requestId];

        emit PriceUpdated(symbol, _price, block.timestamp); //
    }

    // --- Public Trading Functions ---

    function buyStock(string memory _symbol, uint256 _amount) public {
        require(stocks[_symbol].isListed, "Stock is not listed.");
        require(_amount > 0, "Amount must be greater than zero.");

        Stock memory stock = stocks[_symbol];

        // Check if the price is recent enough
        require(
            block.timestamp - stock.lastUpdated <= priceTimeout,
            "Price is outdated."
        );
        require(stock.price > 0, "Price is not available.");

        // Calculate the total cost
        uint256 totalCost = (_amount * stock.price) / (10 ** 8); // Divide by 10^8 to adjust for decimals

        // Transfer payment from user to this contract
        require(
            paymentToken.transferFrom(msg.sender, address(this), totalCost),
            "Payment transfer failed."
        );

        // Mint stock tokens for the user
        StockToken(stock.tokenAddress).mint(msg.sender, _amount);
    }

    function sellStock(string memory _symbol, uint256 _amount) public {
        require(stocks[_symbol].isListed, "Stock is not listed.");
        require(_amount > 0, "Amount must be greater than zero.");

        Stock storage stock = stocks[_symbol];

        require(
            block.timestamp - stock.lastUpdated <= priceTimeout,
            "Price is outdated."
        );
        require(stock.price > 0, "Price is not available.");

        uint256 totalValue = (_amount * stock.price) / (10 ** 8);

        // SECURE PATTERN:
        // 1. Pull tokens from the user. This requires the user to have called
        //    `approve()` on the token contract beforehand, giving this contract permission.
        IERC20(stock.tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // 2. Now that this contract securely holds the tokens, burn them.
        StockToken(stock.tokenAddress).burn(address(this), _amount);

        // 3. Finally, pay the user.
        require(
            paymentToken.transfer(msg.sender, totalValue),
            "Payment transfer failed."
        );
    }

    /**
     * @dev FOR TESTING ONLY. Manually sets a stock's price to simulate an oracle update.
     * MUST be 'public' to be visible to the test contract.
     */
    function _test_updatePrice(string memory _symbol, uint256 _price) public {
        require(stocks[_symbol].isListed, "Stock is not listed.");
        stocks[_symbol].price = _price;
        stocks[_symbol].lastUpdated = block.timestamp;
    }
}
