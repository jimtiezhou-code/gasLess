// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @notice 简化 ERC-721 NFT（仅用于测试）。
contract MockNFT {
    string public name = "MockNFT";
    string public symbol = "MNFT";

    uint256 private _nextTokenId = 1;

    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(uint256 => string) private _tokenURI;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    // ============================
    // ERC-721 READ
    // ============================

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "ERC721: invalid token");
        return owner;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ERC721: zero address");
        return _balanceOf[owner];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return _tokenURI[tokenId];
    }

    // ============================
    // MINT
    // ============================

    /// @notice 铸造 NFT（仅市场合约调用）。
    function mint(address to, string calldata uri) external returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _ownerOf[tokenId] = to;
        _balanceOf[to]++;
        _tokenURI[tokenId] = uri;
        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    // ============================
    // QUERY
    // ============================

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }
}
