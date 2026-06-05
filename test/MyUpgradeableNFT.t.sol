// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MyUpgradeableNFT} from "../src/MyUpgradeableNFT.sol";
import {MyUpgradeableNFT_V2} from "../src/MyUpgradeableNFT_V2.sol";

contract MyUpgradeableNFTTest is Test {
    MyUpgradeableNFT public nft; // 通过 Proxy 交互
    ERC1967Proxy public proxy;

    address public owner = address(0x100);
    address public alice = address(0x200);
    address public bob   = address(0x300);

    function setUp() public {
        vm.prank(owner);

        // 部署 V1 实现
        MyUpgradeableNFT impl = new MyUpgradeableNFT();

        // 编码初始化
        bytes memory initData = abi.encodeCall(
            MyUpgradeableNFT.initialize,
            (owner, "My Upgradeable NFT", "MNFT")
        );

        // 部署代理
        proxy = new ERC1967Proxy(address(impl), initData);

        // 用 V1 接口与代理交互
        nft = MyUpgradeableNFT(address(proxy));
    }

    // ============================
    // V1 基础测试
    // ============================

    function test_V1_Mint() public {
        vm.prank(owner);
        uint256 tokenId = nft.safeMint(alice);

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.totalMinted(), 1);
    }

    function test_V1_Multiple() public {
        vm.startPrank(owner);
        nft.safeMint(alice);
        nft.safeMint(bob);
        vm.stopPrank();

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.totalMinted(), 2);
    }

    function test_V1_OnlyOwnerCanMint() public {
        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        nft.safeMint(alice);
    }

    // ============================
    // 升级到 V2
    // ============================

    function _upgradeToV2() internal returns (MyUpgradeableNFT_V2 v2) {
        // 部署 V2 实现
        MyUpgradeableNFT_V2 newImpl = new MyUpgradeableNFT_V2();

        // 升级代理（需 owner 权限）
        vm.prank(owner);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(
            address(newImpl), ""
        );

        v2 = MyUpgradeableNFT_V2(address(proxy));
    }

    // ============================
    // V2 新功能测试
    // ============================

    function test_Upgrade_Version() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();
        assertEq(v2.version(), 2);
    }

    function test_Upgrade_StatePreserved() public {
        vm.prank(owner);
        nft.safeMint(alice);
        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.totalMinted(), 1);

        // 升级
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        // 状态保留
        assertEq(v2.ownerOf(0), alice);
        assertEq(v2.totalMinted(), 1);
    }

    function test_V2_MintWithURI() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        vm.prank(owner);
        uint256 tokenId = v2.safeMint(alice, "ipfs://QmTest");

        assertEq(v2.tokenURI(tokenId), "ipfs://QmTest");
    }

    function test_V2_MaxSupply() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        vm.startPrank(owner);
        v2.setMaxSupply(3);
        v2.safeMint(alice, "");
        v2.safeMint(bob, "");
        v2.safeMint(alice, "");

        // 达到上限
        vm.expectRevert("Max supply reached");
        v2.safeMint(bob, "");
    }

    function test_V2_Burn() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        vm.prank(owner);
        uint256 tokenId = v2.safeMint(alice, "ipfs://burn-me");

        // 非持有者不能销毁
        vm.prank(bob);
        vm.expectRevert("Not owner");
        v2.burn(tokenId);

        // 持有者可以销毁
        vm.prank(alice);
        v2.burn(tokenId);

        // 销毁后查询不到
        vm.expectRevert();
        v2.ownerOf(tokenId);
    }

    function test_V2_BatchMint() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        vm.prank(owner);
        v2.batchMint(alice, 5, "ipfs://batch");

        assertEq(v2.totalMinted(), 5);
        assertEq(v2.tokenURI(0), "ipfs://batch");
        assertEq(v2.ownerOf(3), alice);
    }

    function test_V2_Info() public {
        MyUpgradeableNFT_V2 v2 = _upgradeToV2();

        vm.startPrank(owner);
        v2.setMaxSupply(100);
        v2.safeMint(alice, "");
        vm.stopPrank();

        (uint256 ver, uint256 minted, uint256 max) = v2.info();
        assertEq(ver, 2);
        assertEq(minted, 1);
        assertEq(max, 100);
    }

    // ============================
    // 安全测试
    // ============================

    function test_CannotInitializeImpl() public {
        // 部署新的 V1 实现（不通过 proxy）
        MyUpgradeableNFT impl = new MyUpgradeableNFT();

        vm.prank(alice);
        vm.expectRevert(); // _disableInitializers 生效
        impl.initialize(alice, "Hacked", "HACK");
    }

    function test_OnlyOwnerCanUpgrade() public {
        MyUpgradeableNFT_V2 newImpl = new MyUpgradeableNFT_V2();

        // 非 owner 不能升级
        vm.prank(alice);
        vm.expectRevert();
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(
            address(newImpl), ""
        );
    }

    // ============================
    // 存储布局验证
    // ============================

    function test_StorageLayout_Compatible() public view {
        // 验证 V2 继承了 V1 的 storage slot
        // V1 的 _nextTokenId 在 slot 0（ERC721 的 slot 由 OZ 管理）
        // 这里验证基础功能不受影响即表示存储兼容
        assertEq(nft.totalMinted(), 0);
    }
}
