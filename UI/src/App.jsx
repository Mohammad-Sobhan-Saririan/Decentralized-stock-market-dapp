import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import StockMarketABI from './StockMarketABI.json';
import { ToastContainer, toast } from 'react-toastify';
import 'react-toastify/dist/ReactToastify.css';
import './App.css';

// const contractAddress = "0xd5d5fc8e1aa2d103a13CFbc13834c241bF70c69e";
const contractAddress = "0x27c8C94374C8B64D25AC1F1369e5b472F4fD6981"; // second contract : SoSa

const ERC20_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

function App() {
  const [account, setAccount] = useState(null);
  const [contract, setContract] = useState(null);
  const [signer, setSigner] = useState(null);
  const [stocks, setStocks] = useState([]);
  const [isOwner, setIsOwner] = useState(false);

  const [isListLoading, setIsListLoading] = useState(false);
  const [isAddStockLoading, setIsAddStockLoading] = useState(false);
  const [priceUpdateLoading, setPriceUpdateLoading] = useState({});
  const [priceTimeout, setPriceTimeout] = useState(null);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [tradeDetails, setTradeDetails] = useState({ symbol: '', action: '', tokenAddress: '' });
  const [tradeAmount, setTradeAmount] = useState('');
  const [isTradingLoading, setIsTradingLoading] = useState(false);

  const connectWallet = async () => {
    if (window.ethereum) {
      try {
        const provider = new ethers.BrowserProvider(window.ethereum);
        const accounts = await provider.send("eth_requestAccounts", []);
        const signer = await provider.getSigner();
        const address = accounts[0];

        const stockMarketContract = new ethers.Contract(contractAddress, StockMarketABI, signer);
        const ownerAddress = await stockMarketContract.owner();

        const timeout = await stockMarketContract.priceTimeout();
        setPriceTimeout(Number(timeout));

        setSigner(signer);
        setContract(stockMarketContract);
        setAccount(address);
        setIsOwner(ownerAddress.toLowerCase() === address.toLowerCase());

      } catch (error) { console.error("Error connecting wallet:", error); }
    } else { alert("Please install MetaMask!"); }
  };

  const fetchStocks = async () => {
    if (!contract || !account || priceTimeout === null) return;
    setIsListLoading(true);
    try {
      const symbols = [];
      let i = 0;
      while (true) {
        try {
          const symbol = await contract.listedStockSymbols(i);
          symbols.push(symbol);
          i++;
        } catch (error) { break; }
      }

      const stocksData = await Promise.all(
        symbols.map(async (symbol) => {
          const stock = await contract.stocks(symbol);
          if (stock.isListed) {
            const tokenContract = new ethers.Contract(stock.tokenAddress, ERC20_ABI, contract.runner);
            const balance = await tokenContract.balanceOf(account);
            const decimals = await tokenContract.decimals();

            const isOutdated = (Date.now() / 1000 - Number(stock.lastUpdated)) > priceTimeout;

            return {
              name: stock.name,
              symbol: stock.symbol,
              tokenAddress: stock.tokenAddress,
              price: stock.price,
              formattedPrice: ethers.formatUnits(stock.price, 8),
              lastUpdated: Number(stock.lastUpdated) === 0 ? 'Never' : new Date(Number(stock.lastUpdated) * 1000).toLocaleString(),
              balance: ethers.formatUnits(balance, decimals),
              isOutdated: Number(stock.lastUpdated) === 0 ? true : isOutdated,
            };
          }
          return null;
        })
      );
      setStocks(stocksData.filter(s => s !== null));
    } catch (error) {
      console.error("Error fetching stocks:", error);
      toast.error("Could not fetch stock list.");
    }
    setIsListLoading(false);
  };

  useEffect(() => {
    if (contract && account) {
      fetchStocks();
    }
  }, [contract, account, priceTimeout]);

  const handleAddStock = async (e) => {
    e.preventDefault();
    const name = e.target.name.value;
    const symbol = e.target.symbol.value;
    if (!contract || !name || !symbol) return;
    setIsAddStockLoading(true);
    const promise = contract.addStock(name, symbol);
    toast.promise(promise.then(tx => tx.wait()), {
      pending: 'Sending transaction to add stock...',
      success: 'Stock added successfully! List will refresh.',
      error: 'Failed to add stock.'
    });
    try {
      await promise;
      await fetchStocks();
    } catch (error) {
      console.error("Error adding stock:", error);
    } finally {
      setIsAddStockLoading(false);
      e.target.reset();
    }
  };

  const handleRequestPrice = async (symbol) => {
    if (!contract) return;
    setPriceUpdateLoading(prev => ({ ...prev, [symbol]: true }));
    const promise = contract.requestPriceUpdate(symbol);
    toast.promise(promise.then(tx => tx.wait()), {
      pending: `Requesting price for ${symbol}...`,
      success: `Price request for ${symbol} sent! The oracle will respond shortly.`,
      error: `Failed to request price for ${symbol}.`
    });
    try {
      await promise;
    } catch (error) {
      console.error("Error requesting price:", error);
    } finally {
      setPriceUpdateLoading(prev => ({ ...prev, [symbol]: false }));
    }
  };

  const openModal = (symbol, action, tokenAddress) => {
    setTradeDetails({ symbol, action, tokenAddress });
    setIsModalOpen(true);
  };

  const closeModal = () => {
    setIsModalOpen(false);
    setTradeAmount('');
  };

  const handleTrade = async () => {
    if (!tradeAmount || parseFloat(tradeAmount) <= 0) {
      toast.error("Please enter a valid amount.");
      return;
    }

    setIsTradingLoading(true);

    try {
      const stock = stocks.find(s => s.symbol === tradeDetails.symbol);
      // Assuming stock tokens have 18 decimals, as is standard
      const amountToTradeInWei = ethers.parseUnits(tradeAmount, 18);

      if (tradeDetails.action === 'buy') {
        const totalCostInWei = (amountToTradeInWei * stock.price) / BigInt(10 ** 8);

        const paymentTokenAddress = await contract.paymentToken();
        const paymentToken = new ethers.Contract(paymentTokenAddress, ERC20_ABI, signer);

        const approveTx = await paymentToken.approve(contractAddress, totalCostInWei);
        await toast.promise(approveTx.wait(), {
          pending: '1/2: Approving payment...',
          success: 'Approved! Now confirming purchase...',
          error: 'Approval failed.'
        });

        const buyTx = await contract.buyStock(tradeDetails.symbol, amountToTradeInWei);
        await toast.promise(buyTx.wait(), {
          pending: '2/2: Processing purchase...',
          success: 'Purchase successful!',
          error: 'Purchase failed.'
        });

      } else if (tradeDetails.action === 'sell') {
        const stockToken = new ethers.Contract(tradeDetails.tokenAddress, ERC20_ABI, signer);

        const approveTx = await stockToken.approve(contractAddress, amountToTradeInWei);
        await toast.promise(approveTx.wait(), {
          pending: '1/2: Approving stock for sale...',
          success: 'Approved! Now confirming sale...',
          error: 'Approval failed.'
        });

        const sellTx = await contract.sellStock(tradeDetails.symbol, amountToTradeInWei);
        await toast.promise(sellTx.wait(), {
          pending: '2/2: Processing sale...',
          success: 'Sale successful!',
          error: 'Sale failed.'
        });
      }

      await fetchStocks();
      closeModal();

    } catch (error) {
      console.error(`Error during ${tradeDetails.action}:`, error);
      const reason = error.reason || `The ${tradeDetails.action} transaction failed.`;
      toast.error(reason);
    } finally {
      setIsTradingLoading(false);
    }
  };

  return (
    <div className="container">
      <ToastContainer position="bottom-right" theme="dark" />
      <header>
        <h1>Stellar Stocks</h1>
        {account ? (
          <div className="wallet-info">
            <p className="address-cell">
              Connected:
              <span title={account}>
                {` ${account.substring(0, 6)}...${account.substring(account.length - 4)}`}
              </span>
              <button onClick={() => { navigator.clipboard.writeText(account); toast.success("Copied!"); }} className="copy-button">📋</button>
            </p>
            {isOwner && <p><strong>Admin Wallet Connected</strong></p>}
          </div>
        ) : (
          <button onClick={connectWallet}>Connect Wallet</button>
        )}
      </header>

      <main>
        {isOwner && (
          <div className="glass-card">
            <h2>Admin Panel</h2>
            <form onSubmit={handleAddStock}>
              <input type="text" name="name" placeholder="Stock Name (e.g., Apple)" required disabled={isAddStockLoading} />
              <input type="text" name="symbol" placeholder="Symbol (e.g., AAPL)" required disabled={isAddStockLoading} />
              <button type="submit" disabled={isAddStockLoading}>
                {isAddStockLoading ? 'Adding...' : 'Add New Stock'}
              </button>
            </form>
          </div>
        )}

        <div className="glass-card">
          <h2>Market Listings</h2>
          <button onClick={fetchStocks} disabled={isListLoading}>
            {isListLoading ? 'Refreshing...' : 'Refresh List'}
          </button>
          <table>
            <thead>
              <tr>
                <th>Symbol</th>
                <th>Price (USD)</th>
                <th>Your Balance</th>
                <th>Token Address</th>
                <th>Last Updated</th>
                <th>Buy</th>
                <th>Sell</th>
                <th>Admin Actions</th>
              </tr>
            </thead>
            <tbody>
              {stocks.map((stock) => (
                <tr key={stock.symbol}>
                  <td><strong>{stock.symbol}</strong><br /><small>{stock.name}</small></td>
                  <td className={stock.isOutdated ? 'outdated-price' : ''} title={stock.isOutdated ? 'This price is stale. The owner must update it before trading is possible.' : ''}>
                    ${stock.formattedPrice}
                  </td>
                  <td>{stock.balance}</td>
                  <td className="address-cell">
                    <span title={stock.tokenAddress}>
                      {`${stock.tokenAddress.substring(0, 6)}...${stock.tokenAddress.substring(stock.tokenAddress.length - 4)}`}
                    </span>
                    <button onClick={() => { navigator.clipboard.writeText(stock.tokenAddress); toast.success("Copied!"); }} className="copy-button">📋</button>
                  </td>
                  <td>{stock.lastUpdated}</td>
                  <td>
                    <button
                      onClick={() => openModal(stock.symbol, 'buy', stock.tokenAddress)}
                      disabled={stock.isOutdated}
                      title={stock.isOutdated ? "Cannot buy: price is outdated." : `Buy ${stock.symbol}`}
                    >
                      Buy
                    </button>
                  </td>
                  <td>
                    <button
                      onClick={() => openModal(stock.symbol, 'sell', stock.tokenAddress)}
                      disabled={stock.isOutdated}
                      title={stock.isOutdated ? "Cannot sell: price is outdated." : `Sell ${stock.symbol}`}
                    >
                      Sell
                    </button>
                  </td>
                  <td>
                    {isOwner && (
                      <button onClick={() => handleRequestPrice(stock.symbol)} disabled={priceUpdateLoading[stock.symbol]}>
                        {priceUpdateLoading[stock.symbol] ? 'Updating...' : 'Update Price'}
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {stocks.length === 0 && !isListLoading && <p>No stocks listed yet. The owner can add one using the admin panel.</p>}
        </div>

        {isModalOpen && (
          <div className="modal-overlay">
            <div className="modal-content">
              <button onClick={closeModal} className="modal-close-button">×</button>
              <h3>{tradeDetails.action === 'buy' ? `Buy ${tradeDetails.symbol}` : `Sell ${tradeDetails.symbol}`}</h3>
              <input
                type="number"
                className="trade-input"
                placeholder="Enter amount of shares"
                value={tradeAmount}
                onChange={(e) => setTradeAmount(e.target.value)}
                disabled={isTradingLoading}
              />
              <button onClick={handleTrade} disabled={isTradingLoading}>
                {isTradingLoading ? 'Processing...' : `Confirm ${tradeDetails.action}`}
              </button>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default App;