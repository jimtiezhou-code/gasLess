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
    // APPROVE (ERC-721 standard)
    // ============================

    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function approve(address to, uint256 tokenId) external {
        require(_ownerOf[tokenId] == msg.sender, "Not owner");
        _tokenApprovals[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    // ============================
    // TRANSFER (ERC-721 standard)
    // ============================

    function transferFrom(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        _transfer(from, to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(_ownerOf[tokenId] == from, "Not owner");
        require(
            msg.sender == from || msg.sender == _tokenApprovals[tokenId] || _operatorApprovals[from][msg.sender],
            "Not approved"
        );
        _ownerOf[tokenId] = to;
        _balanceOf[from]--;
        _balanceOf[to]++;
        delete _tokenApprovals[tokenId];
        emit Transfer(from, to, tokenId);
    }

    // ============================
    // QUERY
    // ============================

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }
}
