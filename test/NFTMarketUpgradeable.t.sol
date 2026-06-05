// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {NFTMarketV1} from "../src/NFTMarketV1.sol";
import {NFTMarketV2} from "../src/NFTMarketV2.sol";
import {MockNFT} from "../src/mock/MockNFT.sol";

contract NFTMarketUpgradeableTest is Test {
    NFTMarketV1 public market;
    ERC1967Proxy public proxy;
    MockNFT public nft;

    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public buyer  = makeAddr("buyer");
    address public relayer = makeAddr("relayer");

    uint256 public constant PRICE = 1 ether;
    uint256 public sellerPK = 0xA11CE; // seller 的签名私钥

    function setUp() public {
        address sellerAddr = vm.addr(sellerPK);
        seller = sellerAddr; // 用有私钥的地址作为 seller

        // 部署 NFT
        nft = new MockNFT();

        // 部署市场 V1
        NFTMarketV1 impl = new NFTMarketV1();
        bytes memory initData = abi.encodeCall(NFTMarketV1.initialize, (owner, 250)); // 2.5% fee
        proxy = new ERC1967Proxy(address(impl), initData);
        market = NFTMarketV1(address(proxy));

        // 给 buyer ETH
        vm.deal(buyer, 100 ether);
    }

    // ============================
    // 辅助函数
    // ============================

    function _mintAndList() internal {
        vm.prank(seller);
        nft.mint(seller, "");

        vm.startPrank(seller);
        nft.approve(address(market), 1);
        market.list(address(nft), 1, PRICE);
        vm.stopPrank();
    }

    function _upgradeToV2() internal returns (NFTMarketV2 v2) {
        NFTMarketV2 newImpl = new NFTMarketV2();
        vm.prank(owner);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImpl), "");
        v2 = NFTMarketV2(address(proxy));
    }

    // ============================
    // V1 基础测试
    // ============================

    function test_V1_List() public {
        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.approve(address(market), 1);
        market.list(address(nft), 1, PRICE);
        vm.stopPrank();

        (address lstSeller, uint256 lstPrice, bool lstActive) = market.getListing(address(nft), 1);
        assertEq(lstSeller, seller);
        assertEq(lstPrice, PRICE);
        assertTrue(lstActive);
    }

    function test_V1_Buy() public {
        _mintAndList();

        uint256 sellerBalBefore = seller.balance;

        vm.prank(buyer);
        market.buy{value: PRICE}(address(nft), 1);

        // NFT 转移
        assertEq(nft.ownerOf(1), buyer);
        // 上架取消
        (, , bool a) = market.getListing(address(nft), 1);
        assertFalse(a);
        // seller 收到 ETH（减去 2.5% 手续费）
        uint256 fee = (PRICE * 250) / 10000;
        assertEq(seller.balance - sellerBalBefore, PRICE - fee);
    }

    function test_V1_Cancel() public {
        _mintAndList();

        vm.prank(seller);
        market.cancel(address(nft), 1);

        (, , bool a) = market.getListing(address(nft), 1);
        assertFalse(a);
    }

    function test_V1_Revert_NotOwner() public {
        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.approve(address(market), 1); // seller 授权给市场
        vm.stopPrank();

        // buyer 不是 owner，即使有授权也上架不了
        vm.prank(buyer);
        vm.expectRevert("Not owner");
        market.list(address(nft), 1, PRICE);
    }

    function test_V1_Version() public view {
        assertEq(market.version(), 1);
    }

    function test_V1_Admin_SetFee() public {
        vm.prank(owner);
        market.setFeeBps(500);
        assertEq(market.platformFeeBps(), 500);
    }

    function test_V1_Admin_Withdraw() public {
        _mintAndList();
        vm.prank(buyer);
        market.buy{value: PRICE}(address(nft), 1);

        uint256 balance = market.platformBalance();
        assertGt(balance, 0);

        vm.prank(owner);
        market.withdrawPlatformBalance(owner);
        assertEq(market.platformBalance(), 0);
    }

    // ============================
    // V2 升级测试
    // ============================

    function test_Upgrade_Version() public {
        NFTMarketV2 v2 = _upgradeToV2();
        assertEq(v2.version(), 2);
    }

    function test_Upgrade_StatePreserved() public {
        _mintAndList();

        NFTMarketV2 v2 = _upgradeToV2();

        // V1 的上架还在
        (address lstSeller, uint256 lstPrice, bool lstActive) = v2.getListing(address(nft), 1);
        assertEq(lstSeller, seller);
        assertEq(lstPrice, PRICE);
        assertTrue(lstActive);

        // V1 的手续费还在
        assertEq(v2.platformFeeBps(), 250);

        // V1 的购买功能正常
        vm.prank(buyer);
        v2.buy{value: PRICE}(address(nft), 1);
        assertEq(nft.ownerOf(1), buyer);
    }

    // ============================
    // V2 签名上架测试
    // ============================

    function _signListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 nonce,
        uint256 deadline
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        NFTMarketV2 v2 = NFTMarketV2(address(market));

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("ListNFT(address nftContract,uint256 tokenId,uint256 price,uint256 nonce,uint256 deadline)"),
                nftContract,
                tokenId,
                price,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("2")),
                block.chainid,
                address(market)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(sellerPK, digest);
    }

    function test_V2_ListWithSignature() public {
        // 升级到 V2
        NFTMarketV2 v2 = _upgradeToV2();

        // seller mint NFT + setApprovalForAll（一次性授权）
        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.setApprovalForAll(address(v2), true);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = v2.sigNonces(seller);
        (uint8 v, bytes32 r, bytes32 sigS) = _signListing(
            address(nft), 1, PRICE, nonce, deadline
        );

        vm.stopPrank();

        // 中继器代提交（seller 不需要付 gas）
        vm.prank(relayer);
        v2.listWithSignature(seller, address(nft), 1, PRICE, deadline, v, r, sigS);

        // 验证上架
        (address listSeller, uint256 listPrice, bool listActive) = v2.getListing(address(nft), 1);
        assertEq(listSeller, seller);
        assertEq(listPrice, PRICE);
        assertTrue(listActive);
    }

    function test_V2_SignatureListing_Buy() public {
        NFTMarketV2 v2 = _upgradeToV2();

        // seller 准备
        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.setApprovalForAll(address(v2), true);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = v2.sigNonces(seller);
        (uint8 v, bytes32 r, bytes32 s) = _signListing(
            address(nft), 1, PRICE, nonce, deadline
        );
        vm.stopPrank();

        // 中继器提交上架
        vm.prank(relayer);
        v2.listWithSignature(seller, address(nft), 1, PRICE, deadline, v, r, s);

        // buyer 购买
        vm.prank(buyer);
        v2.buy{value: PRICE}(address(nft), 1);

        assertEq(nft.ownerOf(1), buyer);
    }

    function test_V2_SignatureListing_MultipleNFTs() public {
        NFTMarketV2 v2 = _upgradeToV2();

        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.mint(seller, "");
        nft.mint(seller, "");
        nft.setApprovalForAll(address(v2), true);

        // 一次授权，签名上架 3 个 NFT
        for (uint256 i = 1; i <= 3; i++) {
            uint256 deadline = block.timestamp + 1 hours;
            uint256 nonce = v2.sigNonces(seller);
            (uint8 v, bytes32 r, bytes32 s) = _signListing(
                address(nft), i, PRICE * i, nonce, deadline
            );
            v2.listWithSignature(seller, address(nft), i, PRICE * i, deadline, v, r, s);
        }
        vm.stopPrank();

        for (uint256 i = 1; i <= 3; i++) {
            (, uint256 p, bool a) = v2.getListing(address(nft), i);
            assertEq(p, PRICE * i);
            assertTrue(a);
        }
    }

    function test_V2_SignatureListing_NonceReplay() public {
        NFTMarketV2 v2 = _upgradeToV2();

        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.setApprovalForAll(address(v2), true);

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = v2.sigNonces(seller);
        (uint8 v, bytes32 r, bytes32 s) = _signListing(
            address(nft), 1, PRICE, nonce, deadline
        );

        // 第一次成功
        v2.listWithSignature(seller, address(nft), 1, PRICE, deadline, v, r, s);

        // 取消上架
        v2.cancel(address(nft), 1);

        // 用同一签名重放 → nonce 已消费，签名验证失败
        vm.expectRevert("Invalid signature");
        v2.listWithSignature(seller, address(nft), 1, PRICE, deadline, v, r, s);
    }

    function test_V2_SignatureListing_ExpiredDeadline() public {
        NFTMarketV2 v2 = _upgradeToV2();

        vm.startPrank(seller);
        nft.mint(seller, "");
        nft.setApprovalForAll(address(v2), true);

        uint256 pastDeadline = block.timestamp - 1; // 已过期
        uint256 nonce = v2.sigNonces(seller);
        (uint8 v, bytes32 r, bytes32 s) = _signListing(
            address(nft), 1, PRICE, nonce, pastDeadline
        );

        vm.expectRevert("Signature expired");
        v2.listWithSignature(seller, address(nft), 1, PRICE, pastDeadline, v, r, s);
    }

    function test_V2_SignatureListing_WrongSigner() public {
        NFTMarketV2 v2 = _upgradeToV2();

        // buyer 铸造 NFT + 授权市场
        vm.startPrank(buyer);
        nft.mint(buyer, "");
        nft.setApprovalForAll(address(v2), true);

        // 用 seller 的 key 签名（但非 owner），声称 signer 是 buyer
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = v2.sigNonces(buyer);
        (uint8 v, bytes32 r, bytes32 s) = _signListing(
            address(nft), 1, PRICE, nonce, deadline
        );
        vm.stopPrank();

        // ecrecover 恢复出 seller，但 buyer != seller → 不匹配
        vm.expectRevert("Invalid signature");
        v2.listWithSignature(buyer, address(nft), 1, PRICE, deadline, v, r, s);
    }

    function test_V2_SignatureListing_NotApproved() public {
        NFTMarketV2 v2 = _upgradeToV2();

        vm.prank(seller);
        nft.mint(seller, "");
        // 故意不调用 setApprovalForAll

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = v2.sigNonces(seller);
        (uint8 v, bytes32 r, bytes32 s) = _signListing(
            address(nft), 1, PRICE, nonce, deadline
        );

        vm.expectRevert("Market not approved for all");
        v2.listWithSignature(seller, address(nft), 1, PRICE, deadline, v, r, s);
    }

    function test_V2_UpgradeOnlyOwner() public {
        NFTMarketV2 newImpl = new NFTMarketV2();
        vm.prank(buyer);
        vm.expectRevert();
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(newImpl), "");
    }
}
