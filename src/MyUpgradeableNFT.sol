// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title MyUpgradeableNFT V1
/// @notice 可升级的 ERC721 合约 — 基础版（铸造 + 转移）
contract MyUpgradeableNFT is UUPSUpgradeable, OwnableUpgradeable, ERC721Upgradeable {
    uint256 private _nextTokenId;

    /// 存储间隙：预留给未来版本的新变量
    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice 初始化（替代构造函数）
    /// @param _owner 合约所有者
    /// @param _name  NFT 名称
    /// @param _symbol NFT 符号
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __Ownable_init(_owner);
        __ERC721_init(_name, _symbol);
    }

    /// @notice 铸造 NFT（仅 owner）
    function safeMint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /// @notice 当前已铸造数量
    function totalMinted() public view returns (uint256) {
        return _nextTokenId;
    }

    /// @dev UUPS 升级权限（仅 owner）
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
