# Decentralized Stock Market dApp

This is a full-stack decentralized application that simulates a stock market on the Ethereum blockchain (Sepolia Testnet). It features a Solidity smart contract backend with Chainlink oracle integration and a responsive React frontend.

![App Screenshot](./ui/public/screenshot.png) 
*(Suggestion: Take a screenshot of your running dApp, save it as `screenshot.png` inside your `project/ui/public/` folder, and it will appear here.)*

---

## ✨ Core Features

- **Smart Contracts (`/contracts`):**
  - **Factory Pattern:** A main `StockMarket.sol` contract deploys unique ERC20 `StockToken.sol` contracts for each new stock.
  - **Oracle Integration:** Uses Chainlink Any API to fetch real-time stock prices from an external source.
  - **Secure:** Leverages OpenZeppelin's `Ownable` for access control on admin functions.
- **User Interface (`/ui`):**
  - **Responsive Design:** Modern, glassy, space-themed UI that works on both desktop and mobile.
  - **Web3 Connectivity:** Connects to user's MetaMask wallet to interact with the blockchain.
  - **Full Functionality:** Supports all contract features, including owner-only admin panels and a user-facing modal for buying and selling tokens.
  - **Rich UX:** Includes loading states, transaction notifications, and proactive warnings for outdated prices.

---

## 🚀 Getting Started

### Prerequisites

* [Node.js](https://nodejs.org/) (v18+)
* [MetaMask](https://metamask.io/) browser extension configured for the Sepolia testnet.
* Sepolia ETH (for gas) and LINK tokens (for oracle fees) in your wallet.

### Running the Application

1.  **Clone the repository:**
    ```sh
    git clone [Your Repository URL Here]
    cd decentralized-stock-market
    ```

2.  **Install frontend dependencies:**
    ```sh
    cd ui
    npm install
    ```

3.  **Configure the Contract Address:**
    Open `ui/src/App.jsx` and replace the placeholder with your deployed smart contract address.

4.  **Run the frontend:**
    ```sh
    npm run dev
    ```
    Open your browser and navigate to the local URL provided.