// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title NFTMarket V1
/// @notice 可升级 NFT 市场合约 — 基础版（上架/购买/取消）
contract NFTMarketV1 is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    // ============================
    // STRUCTS
    // ============================

    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }

    // ============================
    // STATE
    // ============================

    /// @notice 平台手续费（基点，100 = 1%）
    uint256 public platformFeeBps;

    /// @notice 平台收益累计
    uint256 public platformBalance;

    /// @notice 上架映射：nftContract -> tokenId -> Listing
    mapping(address => mapping(uint256 => Listing)) internal _listings;

    uint256[50] private __gap;

    // ============================
    // EVENTS
    // ============================

    event Listed(address indexed nftContract, uint256 indexed tokenId, address seller, uint256 price);
    event Bought(address indexed nftContract, uint256 indexed tokenId, address buyer, uint256 price);
    event Cancelled(address indexed nftContract, uint256 indexed tokenId, address seller);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event PlatformWithdrawn(address to, uint256 amount);

    // ============================
    // CONSTRUCTOR
    // ============================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============================
    // INITIALIZER
    // ============================

    function initialize(address _owner, uint256 _feeBps) external initializer {
        __Ownable_init(_owner);
        platformFeeBps = _feeBps;
    }

    // ============================
    // LIST
    // ============================

    /// @notice 上架 NFT（需先 approve 市场合约）
    function list(address nftContract, uint256 tokenId, uint256 price) external {
        require(price > 0, "Price must be > 0");
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this) ||
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)),
            "Market not approved"
        );
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");
        require(!_listings[nftContract][tokenId].active, "Already listed");

        _listings[nftContract][tokenId] = Listing(msg.sender, price, true);
        emit Listed(nftContract, tokenId, msg.sender, price);
    }

    // ============================
    // BUY
    // ============================

    function buy(address nftContract, uint256 tokenId) external payable nonReentrant {
        Listing storage listing = _listings[nftContract][tokenId];
        require(listing.active, "Not listed");
        require(msg.value == listing.price, "Wrong price");

        address seller = listing.seller;
        uint256 price = listing.price;
        listing.active = false;

        // 计算手续费
        uint256 fee = (price * platformFeeBps) / 10000;
        uint256 sellerAmount = price - fee;
        platformBalance += fee;

        // 转账 NFT 和 ETH
        IERC721(nftContract).safeTransferFrom(seller, msg.sender, tokenId);
        (bool ok, ) = payable(seller).call{value: sellerAmount}("");
        require(ok, "Pay seller failed");

        emit Bought(nftContract, tokenId, msg.sender, price);
    }

    // ============================
    // CANCEL
    // ============================

    function cancel(address nftContract, uint256 tokenId) external {
        Listing storage listing = _listings[nftContract][tokenId];
        require(listing.active, "Not listed");
        require(listing.seller == msg.sender, "Not seller");

        listing.active = false;
        emit Cancelled(nftContract, tokenId, msg.sender);
    }

    // ============================
    // VIEW
    // ============================

    function getListing(address nftContract, uint256 tokenId)
        external view returns (address seller, uint256 price, bool active)
    {
        Listing storage listing = _listings[nftContract][tokenId];
        return (listing.seller, listing.price, listing.active);
    }

    function version() external pure virtual returns (uint256) {
        return 1;
    }

    // ============================
    // ADMIN
    // ============================

    function setFeeBps(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Max 10%");
        emit FeeUpdated(platformFeeBps, _newFee);
        platformFeeBps = _newFee;
    }

    function withdrawPlatformBalance(address to) external onlyOwner {
        uint256 amount = platformBalance;
        platformBalance = 0;
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "Withdraw failed");
        emit PlatformWithdrawn(to, amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
