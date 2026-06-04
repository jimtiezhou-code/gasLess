// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Bank} from "../src/Bank.sol";

contract BankTest is Test {
    Bank public bank;

    // 12 个测试用户
    // 避免使用 0x01-0x09 预编译地址
    address public u1  = address(0x100);
    address public u2  = address(0x200);
    address public u3  = address(0x300);
    address public u4  = address(0x400);
    address public u5  = address(0x500);
    address public u6  = address(0x600);
    address public u7  = address(0x700);
    address public u8  = address(0x800);
    address public u9  = address(0x900);
    address public u10 = address(0xA00);
    address public u11 = address(0xB00);
    address public u12 = address(0xC00);

    function setUp() public {
        bank = new Bank();
        // 给每个测试地址 100 ETH
        vm.deal(u1,  100 ether);
        vm.deal(u2,  100 ether);
        vm.deal(u3,  100 ether);
        vm.deal(u4,  100 ether);
        vm.deal(u5,  100 ether);
        vm.deal(u6,  100 ether);
        vm.deal(u7,  100 ether);
        vm.deal(u8,  100 ether);
        vm.deal(u9,  100 ether);
        vm.deal(u10, 100 ether);
        vm.deal(u11, 100 ether);
        vm.deal(u12, 100 ether);
    }

    // ============================
    // 辅助函数
    // ============================

    /// @dev 通过直接转账存款
    function _deposit(address user, uint256 amount) private {
        vm.prank(user);
        (bool ok, ) = address(bank).call{value: amount}("");
        require(ok, "deposit failed");
    }

    // ============================
    // 基础存款
    // ============================

    function test_Deposit_RecordsBalance() public {
        _deposit(u1, 5 ether);
        assertEq(bank.deposits(u1), 5 ether);
    }

    function test_Deposit_MultipleAccumulate() public {
        _deposit(u1, 3 ether);
        _deposit(u1, 2 ether);
        assertEq(bank.deposits(u1), 5 ether);
    }

    function test_Deposit_RevertZero() public {
        vm.prank(u1);
        vm.expectRevert("Bank: zero deposit");
        (bool ok, ) = address(bank).call{value: 0}("");
        ok; // suppress unused warning
    }

    function test_Deposit_EmitsEvent() public {
        vm.prank(u1);
        vm.expectEmit(true, false, false, true);
        emit Bank.Deposited(u1, 3 ether, 3 ether);
        (bool ok, ) = address(bank).call{value: 3 ether}("");
        require(ok);
    }

    // ============================
    // 排行榜：基础入榜
    // ============================

    function test_Top10_SingleUser() public {
        _deposit(u1, 1 ether);
        (address[] memory addrs, uint256[] memory amounts) = bank.getTop10();

        assertEq(addrs.length, 1);
        assertEq(addrs[0], u1);
        assertEq(amounts[0], 1 ether);
    }

    function test_Top10_SortedDescending() public {
        _deposit(u1, 1 ether);  // 最低
        _deposit(u2, 5 ether);  // 最高
        _deposit(u3, 3 ether);  // 中间

        (address[] memory addrs, uint256[] memory amounts) = bank.getTop10();

        assertEq(addrs.length, 3);
        // 降序：5 > 3 > 1
        assertEq(addrs[0], u2);
        assertEq(amounts[0], 5 ether);
        assertEq(addrs[1], u3);
        assertEq(amounts[1], 3 ether);
        assertEq(addrs[2], u1);
        assertEq(amounts[2], 1 ether);
    }

    function test_Top10_AccumulateChangesRank() public {
        _deposit(u1, 1 ether);
        _deposit(u2, 3 ether);
        _deposit(u1, 3 ether); // u1 总额 4 ETH > u2 的 3 ETH

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs[0], u1); // u1 升到第一
        assertEq(addrs[1], u2);
    }

    // ============================
    // 排行榜：满 10 人踢出
    // ============================

    function test_Top10_CappedAtTen() public {
        // 11 人存款，金额递增
        _deposit(u1,  1 ether);
        _deposit(u2,  2 ether);
        _deposit(u3,  3 ether);
        _deposit(u4,  4 ether);
        _deposit(u5,  5 ether);
        _deposit(u6,  6 ether);
        _deposit(u7,  7 ether);
        _deposit(u8,  8 ether);
        _deposit(u9,  9 ether);
        _deposit(u10, 10 ether);
        _deposit(u11, 11 ether); // 最高，应踢出最低的 u1

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs.length, 10);
        assertEq(addrs[0], u11);     // 最高
        assertEq(addrs[9], u2);      // 最低（u1 被踢出）
        assertFalse(bank.isInTop10(u1));
    }

    function test_Top10_MiddleGetsKnockedOut() public {
        // 先存 11 人，排行榜满 10 人，u1(1ETH) 为最低，u11(11ETH) 为最高
        address[11] memory users = [u1, u2, u3, u4, u5, u6, u7, u8, u9, u10, u11];
        for (uint256 i = 0; i < 11; i++) {
            _deposit(users[i], (i + 1) * 1 ether);
        }
        // 排行榜: u11(11) > u10(10) > ... > u2(2)   (u1 在榜外)

        // 榜外的 u1 追加存款，杀入前 10
        _deposit(u1, 5 ether); // u1 总额 = 1 + 5 = 6 ETH → 排在第 6 位

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs.length, 10);
        assertTrue(bank.isInTop10(u1));         // u1 成功入榜
        assertFalse(bank.isInTop10(u2));        // 原来的 u2(2ETH) 被踢出
    }

    // ============================
    // 排行榜：相同金额
    // ============================

    function test_Top10_SameAmount_KeepOrder() public {
        _deposit(u1, 5 ether); // 先存
        _deposit(u2, 5 ether); // 后存，金额相同 → 排在后面

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs[0], u1); // 先到者在前
        assertEq(addrs[1], u2);
    }

    // ============================
    // 提款
    // ============================

    function test_Withdraw_Partial() public {
        _deposit(u1, 5 ether);
        vm.prank(u1);
        bank.withdraw(2 ether);

        assertEq(bank.deposits(u1), 3 ether);
        assertEq(u1.balance, 100 ether - 5 ether + 2 ether);
    }

    function test_Withdraw_Full() public {
        _deposit(u1, 5 ether);
        vm.prank(u1);
        bank.withdraw(5 ether);

        assertEq(bank.deposits(u1), 0);
    }

    function test_Withdraw_RevertInsufficient() public {
        _deposit(u1, 1 ether);
        vm.prank(u1);
        vm.expectRevert("Bank: insufficient balance");
        bank.withdraw(2 ether);
    }

    function test_Withdraw_RevertZero() public {
        vm.prank(u1);
        vm.expectRevert("Bank: zero withdraw");
        bank.withdraw(0);
    }

    function test_Withdraw_EmitsEvent() public {
        _deposit(u1, 5 ether);
        vm.prank(u1);
        vm.expectEmit(true, false, false, true);
        emit Bank.Withdrawn(u1, 2 ether, 3 ether);
        bank.withdraw(2 ether);
    }

    // ============================
    // 提款后排行榜变化
    // ============================

    function test_Withdraw_DropsOutOfTop10() public {
        // 存满 10 人
        address[10] memory users = [u1, u2, u3, u4, u5, u6, u7, u8, u9, u10];
        for (uint256 i = 0; i < 10; i++) {
            _deposit(users[i], (i + 1) * 1 ether);
        }
        // u1 = 1 ETH（榜尾）

        vm.prank(u1);
        bank.withdraw(1 ether); // u1 余额清零，退出排行榜

        assertFalse(bank.isInTop10(u1));
        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs.length, 9); // 只剩 9 人
    }

    function test_Withdraw_StillInTop10() public {
        _deposit(u1, 10 ether);
        _deposit(u2, 5 ether);
        _deposit(u3, 3 ether);

        vm.prank(u1);
        bank.withdraw(3 ether); // u1 剩下 7 ETH，仍排第一

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs[0], u1);
        assertEq(bank.deposits(u1), 7 ether);
    }

    // ============================
    // isInTop10 查询
    // ============================

    function test_IsInTop10_True() public {
        _deposit(u1, 5 ether);
        assertTrue(bank.isInTop10(u1));
    }

    function test_IsInTop10_False() public {
        _deposit(u1, 1 ether);
        _deposit(u2, 2 ether);
        _deposit(u3, 3 ether);
        _deposit(u4, 4 ether);
        _deposit(u5, 5 ether);
        _deposit(u6, 6 ether);
        _deposit(u7, 7 ether);
        _deposit(u8, 8 ether);
        _deposit(u9, 9 ether);
        _deposit(u10, 10 ether);
        // 榜外用户
        assertFalse(bank.isInTop10(u11));
        // u11 存款后杀入前 10
        _deposit(u11, 11 ether);
        assertTrue(bank.isInTop10(u11));
    }

    // ============================
    // 综合场景
    // ============================

    function test_ComplexScenario() public {
        // 8 人陆续存款
        _deposit(u1, 10 ether);
        _deposit(u2, 20 ether);
        _deposit(u3, 15 ether);
        _deposit(u4, 5 ether);
        _deposit(u5, 25 ether);
        _deposit(u6, 30 ether);
        _deposit(u7, 8 ether);
        _deposit(u8, 12 ether);

        (address[] memory addrs, ) = bank.getTop10();
        assertEq(addrs.length, 8);
        // 排序验证：30 > 25 > 20 > 15 > 12 > 10 > 8 > 5
        assertEq(addrs[0], u6);
        assertEq(addrs[7], u4);

        // u4 追加到 35 ETH → 冲上第一
        _deposit(u4, 30 ether);
        (addrs, ) = bank.getTop10();
        assertEq(addrs[0], u4);

        // u6 提走 25 ETH → 剩 5 ETH 掉到榜尾
        vm.prank(u6);
        bank.withdraw(25 ether);
        (addrs, ) = bank.getTop10();
        assertEq(addrs[addrs.length - 1], u6);
        assertEq(bank.deposits(u6), 5 ether);

        // u7 全额提款 → 退出，剩 7 人
        vm.prank(u7);
        bank.withdraw(8 ether);
        (addrs, ) = bank.getTop10();
        assertEq(addrs.length, 7);
        assertFalse(bank.isInTop10(u7));
    }
}
