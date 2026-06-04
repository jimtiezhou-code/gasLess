// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {AirdropMerkleNFTMarket} from "../src/AirdropMerkleNFTMarket.sol";
import {MockERC20Permit} from "../src/mock/MockERC20Permit.sol";
import {MockNFT} from "../src/mock/MockNFT.sol";

/// @notice 完整集成测试：Multicall + Merkle + Permit。
///
/// 测试用的默克尔树（3 个地址，手动构建，与合约哈希一致）：
///
///   H0  = keccak256(abi.encodePacked(alice))
///   H1  = keccak256(abi.encodePacked(bob))
///   H2  = keccak256(abi.encodePacked(carol))
///
///   H01 = keccak256(abi.encodePacked(sorted(H0, H1)))
///   H22 = keccak256(abi.encodePacked(sorted(H2, H2)))  ← 奇数复制
///
///   ROOT = keccak256(abi.encodePacked(sorted(H01, H22)))
contract AirdropMerkleNFTMarketTest is Test {
    AirdropMerkleNFTMarket public market;
    MockERC20Permit public token;
    MockNFT public nft;

    // 用 vm.addr() 从私钥派生地址（保证 vm.sign 签名一致）
    uint256 internal alicePK = 0xA11CE;
    uint256 internal bobPK   = 0xB0B00;
    uint256 internal carolPK = 0xC0C000;
    uint256 internal evePK   = 0xE0E0E;

    address public alice;
    address public bob;
    address public carol; // 奇数
    address public eve;   // 不在白名单

    bytes32 public h0;
    bytes32 public h1;
    bytes32 public h2;
    bytes32 public h01;
    bytes32 public h22;
    bytes32 public root;

    uint256 internal deadline;

    function setUp() public {
        alice = vm.addr(alicePK);
        bob   = vm.addr(bobPK);
        carol = vm.addr(carolPK);
        eve   = vm.addr(evePK);

        // 构建默克尔树
        h0 = keccak256(abi.encodePacked(alice));
        h1 = keccak256(abi.encodePacked(bob));
        h2 = keccak256(abi.encodePacked(carol));

        h01 = _hashPair(h0, h1);
        h22 = _hashPair(h2, h2);
        root = _hashPair(h01, h22);

        // 部署 token + nft + market
        token = new MockERC20Permit(1_000_000 * 10 ** 18); // 1M supply
        vm.label(address(token), "MockToken");

        nft = new MockNFT();
        vm.label(address(nft), "MockNFT");

        market = new AirdropMerkleNFTMarket(root, address(token), address(nft));
        vm.label(address(market), "Market");

        deadline = block.timestamp + 1 hours;

        // 给测试地址发 token
        token.mint(alice, 10_000 * 10 ** 18);
        token.mint(bob, 10_000 * 10 ** 18);
        token.mint(carol, 10_000 * 10 ** 18);
    }

    // ============================
    // 辅助
    // ============================

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        if (a < b) return keccak256(abi.encodePacked(a, b));
        else return keccak256(abi.encodePacked(b, a));
    }

    /// @dev 离线签名 ERC-20 permit（模拟用户前端签名）
    function _signPermit(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 _deadline,
        uint256 signerPK
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                _deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        (v, r, s) = vm.sign(signerPK, digest);
    }

    // ============================
    // 单独调用：permitPrePay + claimNFT
    // ============================

    function test_SeparateCalls_AliceClaims() public {
        uint256 nonce = token.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            alicePK
        );

        // Step 1: permitPrePay
        vm.prank(alice);
        market.permitPrePay(alice, deadline, v, r, s);

        assertEq(
            token.allowance(alice, address(market)),
            market.DISCOUNT_PRICE()
        );

        // Step 2: claimNFT
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;

        vm.prank(alice);
        uint256 tokenId = market.claimNFT(proof);

        assertEq(nft.ownerOf(tokenId), alice);
        assertTrue(market.hasClaimed(alice));
    }

    // ============================
    // Multicall 一次调用
    // ============================

    function test_Multicall_AliceClaimsInOneTx() public {
        uint256 nonce = token.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            alicePK
        );

        // 构造 multicall data
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            alice,
            deadline,
            v,
            r,
            s
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        vm.prank(alice);
        bytes[] memory results = market.multicall(data);

        assertEq(results.length, 2);
        // 第 2 个返回值是 tokenId
        uint256 tokenId = abi.decode(results[1], (uint256));
        assertEq(nft.ownerOf(tokenId), alice);
    }

    // ============================
    // Multicall：Bob（右叶子）
    // ============================

    function test_Multicall_BobClaims() public {
        uint256 nonce = token.nonces(bob);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            bob,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            bobPK
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h0;   // Bob 的兄弟是 H0（在左边）
        proof[1] = h22;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            bob, deadline, v, r, s
        );
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        vm.prank(bob);
        market.multicall(data);

        assertTrue(market.hasClaimed(bob));
    }

    // ============================
    // Multicall：Carol（奇数叶子）
    // ============================

    function test_Multicall_CarolClaims() public {
        uint256 nonce = token.nonces(carol);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            carol,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            carolPK
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h2;   // 奇数时与自身配对
        proof[1] = h01;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            carol, deadline, v, r, s
        );
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        vm.prank(carol);
        market.multicall(data);

        assertTrue(market.hasClaimed(carol));
    }

    // ============================
    // Revert 场景
    // ============================

    function test_Revert_NotInWhitelist() public {
        uint256 nonce = token.nonces(eve);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            eve,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            evePK
        );

        // Eve 不在白名单，用任意 proof 都验证不通过
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            eve, deadline, v, r, s
        );
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        vm.prank(eve);
        vm.expectRevert(); // Merkle proof 验证失败
        market.multicall(data);
    }

    function test_Revert_DoubleClaim() public {
        uint256 nonce = token.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            alicePK
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            alice, deadline, v, r, s
        );
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        // 第一次成功
        vm.prank(alice);
        market.multicall(data);

        // 第二次需要重新签名（nonce 变了）
        uint256 nonce2 = token.nonces(alice);
        (v, r, s) = _signPermit(alice, address(market), market.DISCOUNT_PRICE(), nonce2, deadline, alicePK);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            alice, deadline, v, r, s
        );

        // claimNFT 会因 hasClaimed 而 revert
        vm.prank(alice);
        vm.expectRevert("Market: already claimed");
        market.multicall(data);
    }

    // ============================
    // 价格验证
    // ============================

    function test_ClaimNFT_TransfersCorrectPrice() public {
        uint256 nonce = token.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            alicePK
        );

        uint256 balanceBefore = token.balanceOf(alice);
        uint256 contractBalanceBefore = token.balanceOf(address(market));

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            alice, deadline, v, r, s
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        vm.prank(alice);
        market.multicall(data);

        assertEq(
            token.balanceOf(alice),
            balanceBefore - market.DISCOUNT_PRICE()
        );
        assertEq(
            token.balanceOf(address(market)),
            contractBalanceBefore + market.DISCOUNT_PRICE()
        );
    }

    // ============================
    // MULTICALL SAFETY: ETH 防护
    // ============================

    function test_Multicall_RevertIfValueSent() public {
        vm.deal(alice, 1 ether);

        uint256 nonce = token.nonces(alice);
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            alice,
            address(market),
            market.DISCOUNT_PRICE(),
            nonce,
            deadline,
            alicePK
        );

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = h1;
        proof[1] = h22;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "permitPrePay(address,uint256,uint8,bytes32,bytes32)",
            alice, deadline, v, r, s
        );
        data[1] = abi.encodeWithSignature("claimNFT(bytes32[])", proof);

        bytes memory encoded = abi.encodeWithSignature("multicall(bytes[])", data);

        vm.prank(alice);
        // 去掉 payable 后，EVM 自动拒绝附带 ETH 的调用
        (bool ok, ) = address(market).call{value: 0.1 ether}(encoded);
        assertFalse(ok); // 必须失败
    }

    // ============================
    // Owner
    // ============================

    function test_SetMerkleRoot() public {
        bytes32 newRoot = bytes32(uint256(0xBEEF));
        market.setMerkleRoot(newRoot);
        assertEq(market.merkleRoot(), newRoot);
    }

    function test_SetMerkleRoot_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Market: not owner");
        market.setMerkleRoot(bytes32(uint256(0xDEAD)));
    }
}
