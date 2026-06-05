// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NFTMarketV1} from "./NFTMarketV1.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title NFTMarket V2
/// @notice V1 升级版 — 加入离线签名上架功能。
///         用户只需一次 setApprovalForAll，之后每个 NFT 通过签名即可上架，无需链上 approve。
///
/// 签名内容（EIP-712）：ListNFT(address nftContract,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)
///
/// 流程：
///   1. 用户调用 nft.setApprovalForAll(market, true) —— 一次性授权
///   2. 用户离线签名 (nftContract, tokenId, price, nonce, deadline)
///   3. 任何人提交 listWithSignature(...) → 验证签名 → 创建上架
contract NFTMarketV2 is NFTMarketV1 {
    // ============================
    // V2 新变量（追加在末尾，不破坏 V1 布局）
    // ============================

    /// @notice 每地址签名 nonce（防重放）
    mapping(address => uint256) public sigNonces;

    // ============================
    // EIP-712 常量
    // ============================

    bytes32 private constant LISTING_TYPEHASH =
        keccak256("ListNFT(address nftContract,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)");

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // ============================
    // EVENTS
    // ============================

    event ListedWithSignature(
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );

    // ============================
    // VERSION
    // ============================

    function version() external pure override returns (uint256) {
        return 2;
    }

    // ============================
    // SIGNATURE-BASED LIST
    // ============================

    /// @notice 通过离线签名上架 NFT。
    /// @dev seller 不必是 msg.sender —— 中继器 / 任何人都可代提交。
    function listWithSignature(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // 1. 基本检查
        require(price > 0, "Price must be > 0");
        require(block.timestamp <= deadline, "Signature expired");
        require(
            IERC721(nftContract).isApprovedForAll(seller, address(this)),
            "Market not approved for all"
        );
        require(IERC721(nftContract).ownerOf(tokenId) == seller, "Not owner");
        require(!_listings[nftContract][tokenId].active, "Already listed");

        // 2. 验证 EIP-712 签名
        bytes32 structHash = keccak256(
            abi.encode(LISTING_TYPEHASH, nftContract, tokenId, price, sigNonces[seller], deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);

        address signer = ecrecover(digest, v, r, s);
        require(signer == seller, "Invalid signature");

        // 3. 消费 nonce
        sigNonces[seller]++;

        // 4. 创建上架
        _listings[nftContract][tokenId] = Listing(seller, price, true);

        emit ListedWithSignature(nftContract, tokenId, seller, price);
    }

    // ============================
    // HELPER
    // ============================

    /// @notice 计算签名摘要（供链下生成签名时验证）。
    function listingDigest(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    ) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(LISTING_TYPEHASH, nftContract, tokenId, price, sigNonces[seller], deadline))
        );
    }

    // ============================
    // EIP-712 INTERNAL
    // ============================

    function _domainSeparatorV4() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("2")),
                block.chainid,
                address(this)
            )
        );
    }

    function _hashTypedDataV4(bytes32 structHash) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
    }
}
