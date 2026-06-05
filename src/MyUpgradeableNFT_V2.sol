// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MyUpgradeableNFT} from "./MyUpgradeableNFT.sol";

/// @title MyUpgradeableNFT V2
/// @notice V1 升级版 — 新增 tokenURI 存储、最大供应量限制、销毁功能
contract MyUpgradeableNFT_V2 is MyUpgradeableNFT {
    // ============================
    // V2 新变量（追加在末尾，不破坏 V1 布局）
    // ============================

    /// @notice 每 tokenId 的元数据 URI
    mapping(uint256 => string) private _tokenURIs;

    /// @notice 最大供应量（0 = 无限制）
    uint256 public maxSupply;

    // ============================
    // V2 新功能
    // ============================

    function version() external pure returns (uint256) {
        return 2;
    }

    /// @notice 设置最大供应量（仅 owner）
    function setMaxSupply(uint256 _max) external onlyOwner {
        maxSupply = _max;
    }

    /// @notice 铸造 NFT（带 URI 和最大供应量限制）
    function safeMint(address to, string calldata uri) public onlyOwner returns (uint256) {
        require(maxSupply == 0 || totalMinted() < maxSupply, "Max supply reached");
        uint256 tokenId = super.safeMint(to); // 复用 V1 逻辑
        _tokenURIs[tokenId] = uri;
        return tokenId;
    }

    /// @notice 销毁 NFT（仅 token 持有者）
    function burn(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        _burn(tokenId);
        delete _tokenURIs[tokenId];
    }

    /// @notice 查询 tokenURI
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory uri = _tokenURIs[tokenId];
        return bytes(uri).length > 0 ? uri : super.tokenURI(tokenId);
    }

    /// @notice 批量铸造
    function batchMint(address to, uint256 quantity, string calldata uri) external onlyOwner {
        for (uint256 i = 0; i < quantity; i++) {
            safeMint(to, uri);
        }
    }

    /// @notice 查询合约版本和当前状态
    function info() external view returns (uint256 _version, uint256 _minted, uint256 _max) {
        return (2, totalMinted(), maxSupply);
    }
}
