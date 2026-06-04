# AirdropMerkleNFTMarket 逻辑流程分析

## 一、合约概述

组合 **Multicall + Merkle Tree + ERC-20 Permit** 三种技术，实现一笔交易完成「白名单验证 + 代币支付 + NFT 铸造」。

**核心价值**：用户只需一次链上交互（且仅需签名一次），即可用 100 Token 优惠价购买 NFT。

## 二、三种技术分工

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  ERC-20 Permit    Multicall (delegateCall)   Merkle Tree│
│  ─────────────    ────────────────────────   ───────────│
│  离线签名授权      一笔交易执行多步操作         链上只存   │
│  代替 approve      保持 msg.sender 不变       32 字节根  │
│       │                  │                      │       │
│       ▼                  ▼                      ▼       │
│  ┌────────┐      ┌──────────────┐      ┌──────────────┐ │
│  │无需    │      │ permitPrePay │      │ 白名单验证   │ │
│  │approve │      │      +       │      │ O(log n)    │ │
│  │交易    │      │  claimNFT    │      │ 无需 mapping │ │
│  └────────┘      └──────────────┘      └──────────────┘ │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## 三、完整用户流程

```
═══════════════════════════════════════════════════════
  链下（免费）
═══════════════════════════════════════════════════════
  │
  ├─ 1. 项目方执行脚本生成默克尔树
  │      npm run generate:merkle
  │      → root 部署到合约
  │      → 每个白名单地址得到 proof[]
  │
  ├─ 2. 用户在前端签名 EIP-712 permit
  │      signTypedData({
  │        owner: 用户地址,
  │        spender: Market 合约地址,
  │        value: 100 * 10^18,
  │        deadline: 过期时间
  │      })
  │      → 得到 (v, r, s)   ← 免费，不消耗 gas
  │

═══════════════════════════════════════════════════════
  链上（一笔交易）
═══════════════════════════════════════════════════════
  │
  └─ 3. 用户调用 multicall([data0, data1])
         │
         ├── data0 = encode(permitPrePay(user, deadline, v, r, s))
         │
         └── data1 = encode(claimNFT(proof[]))
```

## 四、multicall 内部执行流程

```
用户 EOA
  │
  │  multicall([data0, data1])
  ▼
┌────────────────────────────────────────────────────────┐
│  AirdropMerkleNFTMarket                                │
│                                                        │
│  multicall(bytes[] calldata data)                      │
│    │                                                   │
│    │  for i = 0 → 1:                                   │
│    │    delegatecall(data[i])                          │
│    │                                                   │
│    ├─ [i=0] ──────────────────────────────────────    │
│    │  permitPrePay(user, deadline, v, r, s)            │
│    │    │                                              │
│    │    │  外部调用 token.permit(                       │
│    │    │    owner  = user,                            │
│    │    │    spender = address(this),  ← Market 合约    │
│    │    │    value  = 100 Token                        │
│    │    │  )                                           │
│    │    │                                              │
│    │    ▼                                              │
│    │  ┌──────────────────────┐                         │
│    │  │ MockERC20Permit      │                         │
│    │  │                      │                         │
│    │  │  1. 验证 deadline    │                         │
│    │  │  2. ecrecover(签名)  │ → signer == user ?     │
│    │  │  3. nonces[user]++   │                         │
│    │  │  4. allowance[user]  │                         │
│    │  │     [Market] = 100   │ ← 授权合约划转 100 Token │
│    │  └──────────────────────┘                         │
│    │                                                   │
│    ├─ [i=1] ──────────────────────────────────────    │
│    │  claimNFT(proof[])                                │
│    │    │                                              │
│    │    ├─ require(!hasClaimed[msg.sender])  ← 防双花   │
│    │    │                                              │
│    │    ├─ _verifyMerkle(proof, msg.sender)            │
│    │    │    │                                         │
│    │    │    │  leaf = keccak256(encodePacked(user))   │
│    │    │    │  current = leaf                         │
│    │    │    │  for each sibling in proof:             │
│    │    │    │    current = hashPair(current, sibling) │
│    │    │    │  return current == merkleRoot           │
│    │    │    ▼                                         │
│    │    │  ✓ 白名单验证通过                              │
│    │    │                                              │
│    │    ├─ hasClaimed[msg.sender] = true  ← 标记已领取  │
│    │    │                                              │
│    │    ├─ token.transferFrom(                         │
│    │    │     from: msg.sender,    ← 用户 EOA          │
│    │    │     to:   address(this), ← Market 合约        │
│    │    │     amount: 100 Token                        │
│    │    │  )                                           │
│    │    │  ✓ 使用步骤 0 的授权，划转成功                 │
│    │    │                                              │
│    │    └─ nft.mint(msg.sender, "")                    │
│    │       ✓ 用户收到 NFT                               │
│    │                                                   │
│    └─ return [result0, result1]                        │
│                                                        │
└────────────────────────────────────────────────────────┘
```

## 五、delegateCall 为什么关键

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│  如果使用普通 call:                                    │
│                                                      │
│  multicall → this.call(claimNFT)                     │
│    └─ claimNFT 中 msg.sender = Market 合约地址        │
│       └─ transferFrom(Market, ...)                   │
│          ✗ Market 合约没有 Token！                     │
│                                                      │
│  使用 delegateCall:                                   │
│                                                      │
│  multicall → this.delegatecall(claimNFT)             │
│    └─ claimNFT 中 msg.sender = 用户 EOA（不变！）      │
│       └─ transferFrom(用户, ...)                     │
│          ✓ 从用户划转 Token                           │
│                                                      │
│  delegateCall 透传了:                                 │
│    • msg.sender  → 保持不变                           │
│    • msg.value   → 保持不变（但本合约禁用了 ETH）      │
│    • storage     → 使用本合约的存储                    │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## 六、Merkle Proof 验证明细

以 3 人白名单为例（Alice, Bob, Carol）：

```
树结构：
              ROOT = H(H01 + H22)
             /                    \
      H01 = H(H0 + H1)      H22 = H(H2 + H2)
        /        \            /        \
  H0=H(Alice) H1=H(Bob)  H2=H(Carol) H2=H(Carol)

验证 Alice 的 proof [H1, H22]：

  第 1 步: current = H0 = keccak256(Alice)
  第 2 步: current = hashPair(H0, H1)   ← 使用 proof[0]
            = H01
  第 3 步: current = hashPair(H01, H22) ← 使用 proof[1]
            = ROOT ✓ 匹配！
```

## 七、安全机制

| 防护点 | 机制 | 位置 |
|--------|------|------|
| **双花** | `hasClaimed` mapping，先标记后操作 | `claimNFT` L106 |
| **非白名单** | Merkle proof 验证失败则 revert | `claimNFT` L107 |
| **授权超支** | permit 固定授权 100 Token，不可变 | `permitPrePay` L100 |
| **重入攻击** | `hasClaimed = true` 先于 `transferFrom` 外部调用 | `claimNFT` L109 |
| **签名过期** | permit 内 `deadline` 检查 | `MockERC20Permit` L87 |
| **ETH 误附** | `multicall` 非 payable，EVM 直接拒绝 | `multicall` L144 |
| **proof 篡改** | 排序后哈希 `hashPair` 防 second-preimage | `_hashPair` L163 |
| **根被篡改** | `setMerkleRoot` 仅 owner | L72 |

## 八、Gas 分析

```
单次 multicall([permitPrePay, claimNFT])：

┌──────────────────────────┬────────┐
│ 操作                      │  Gas   │
├──────────────────────────┼────────┤
│ multicall 基础开销         │ ~2,000 │
│ delegateCall ×2           │ ~2,000 │
│ token.permit (SSTORE×3)  │ ~45,000│
│ Merkle 验证 (2 proof)     │ ~3,000 │
│ hasClaimed SSTORE         │ ~20,000│
│ transferFrom (SSTORE×2)  │ ~20,000│
│ nft.mint (SSTORE×3)      │ ~60,000│
│ 其他 (events, calldata)   │ ~55,000│
├──────────────────────────┼────────┤
│ 总计                      │~207,000│
└──────────────────────────┴────────┘

对比传统方式（分开调用）：
  approve:  ~45,000 gas  (单独交易)
  claimNFT: ~160,000 gas  (第二笔交易)
  合计:     ~205,000 gas  + 21,000 × 2 基础费 = ~247,000

multicall 省掉第二笔交易的基础 gas (~21,000)。
```

## 九、与前两个合约的对比

| 特性 | Bank | Whitelist | AirdropMerkleNFTMarket |
|------|:--:|:--:|:--:|
| **链表** | ✅ 排序 Top10 | — | — |
| **默克尔树** | — | ✅ 基础验证 | ✅ 组合 Multicall |
| **permit** | — | — | ✅ EIP-2612 |
| **Multicall** | — | — | ✅ delegateCall |
| **核心场景** | 排行榜存款 | 白名单验证 | 优惠价 NFT 购买 |

## 十、文件清单

```
src/
├── AirdropMerkleNFTMarket.sol   ← 主合约
├── mock/
│   ├── MockERC20Permit.sol      ← 测试用 ERC-20 + Permit
│   └── MockNFT.sol              ← 测试用 ERC-721
│
test/
└── AirdropMerkleNFTMarket.t.sol ← 10 项集成测试

script/
└── generateMerkleTree.ts        ← TypeScript 默克尔树生成
```
