// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Data Futures Token (DFT)
 * @dev ERC-1155 implementation for selling rights to system telemetry data
 * Each token represents a claim to 10KB of raw system telemetry during >99.5% RAM utilization
 * Data delivered via IPFS hash
 */
contract DataFuturesToken is ERC1155, Ownable, ReentrancyGuard {
    using Strings for uint256;
    
    // Constants
    uint256 public constant MAX_TOKENS = 100;
    uint256 public constant TOKEN_PRICE = 0.0001 ether; // ~$0.10 at testnet ETH rates
    uint256 public constant DATA_ALLOCATION_PER_TOKEN = 10 * 1024; // 10KB in bytes
    
    // State variables
    uint256 public totalSold;
    uint256 public totalRevenue;
    bool public saleActive = false;
    string public ipfsHash;
    bool public dataDelivered = false;
    address payable public treasury;
    
    // Events
    event TokenPurchased(address indexed buyer, uint256 amount, uint256 totalCost);
    event DataDelivered(string ipfsHash, uint256 timestamp);
    event SaleStateChanged(bool active);
    event RevenueWithdrawn(uint256 amount, address indexed recipient);
    
    // Mapping to track purchases per address
    mapping(address => uint256) public purchases;
    
    // Time lock for data delivery (minimum 1 hour after final sale)
    uint256 public deliveryUnlockTime;
    
    constructor(address payable _treasury) 
        ERC1155("https://api.datafutures.eth/metadata/{id}.json") 
    {
        require(_treasury != address(0), "Treasury cannot be zero address");
        treasury = _treasury;
        
        // Mint initial supply to contract
        _mint(address(this), 0, MAX_TOKENS, "");
    }
    
    /**
     * @dev Purchase DFT tokens
     * @param amount Number of tokens to purchase (max 5 per transaction)
     */
    function purchaseTokens(uint256 amount) external payable nonReentrant {
        require(saleActive, "Sale is not active");
        require(amount > 0 && amount <= 5, "Amount must be 1-5");
        require(totalSold + amount <= MAX_TOKENS, "Exceeds available supply");
        require(msg.value == amount * TOKEN_PRICE, "Incorrect payment amount");
        
        // Transfer tokens from contract to buyer
        _safeTransferFrom(address(this), msg.sender, 0, amount, "");
        
        // Update state
        totalSold += amount;
        totalRevenue += msg.value;
        purchases[msg.sender] += amount;
        
        // If all tokens sold, set delivery unlock time
        if (totalSold == MAX_TOKENS) {
            deliveryUnlockTime = block.timestamp + 1 hours;
        }