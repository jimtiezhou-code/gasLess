# AirdropMerkleNFTMarket 测试流程

## ⚠️ 重要：本地测试必须用测试地址

> Anvil 本地链是隔离环境，**必须使用 Anvil 生成的测试账户**（你有私钥才能签名交易）。
> **不要填你的主网真实钱包地址**——那会泄露隐私，而且在本地链上你也无法用那些地址签名。

## 一、环境准备

```bash
cd /Users/jim123/Desktop/hello_foundry/gasLess
npm install
forge build
```

## 二、获取 Anvil 测试账户

```bash
# 终端 1：启动本地节点
anvil
```

启动后会输出 10 个测试账户，例如：

```
Available Accounts
==================

(0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000 ETH)
(1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000 ETH)
(2) 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000 ETH)
...

Private Keys
==================

(0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
(1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
(2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
...
```

**这些就是你的测试地址**。选 2-3 个作为白名单，记下地址和私钥。

## 三、生成白名单默克尔树

### 3.1 编辑脚本，填入 Anvil 测试地址

打开 `script/generateMerkleTree.ts`，把 `WHITELIST` 数组改成你选的 Anvil 地址：

```typescript
// ✅ 正确：Anvil 测试地址
const WHITELIST: Address[] = [
  "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",  // Account #0
  "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",  // Account #1
  "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",  // Account #2
];

// ❌ 错误：真实钱包地址——本地 Anvil 没有对应私钥，无法签名
// "0x6f10D4d51084C2946098E53556Fd2Bb8b81Af445"   ← 别这样
```

### 3.2 运行生成

```bash
npm run generate:merkle
```

输出：

```
══════════════════════════════════════════════
  Merkle Tree 白名单生成结果
══════════════════════════════════════════════

白名单人数 : 3
树深度     : 2 层
Proof 大小 : 2 个元素

────────────────────────────────────────
  Merkle Root（部署到合约）
────────────────────────────────────────
  0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

────────────────────────────────────────
  Merkle Proof（每个地址的证明）
────────────────────────────────────────

  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  Leaf: 0x...
  Proof:
    [0] 0x...
    [1] 0x...

  0x70997970C51812dc3A010C7d01b50e0d17dc79C8
  ...

  0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
  ...
```

记录下 **Merkle Root** 和每个地址的 **Proof**。

## 四、部署合约

创建 `script/Deploy.s.sol`：

```solidity
pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import "../src/mock/MockERC20Permit.sol";
import "../src/mock/MockNFT.sol";
import "../src/AirdropMerkleNFTMarket.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        MockERC20Permit token = new MockERC20Permit(1_000_000 * 10**18);
        MockNFT nft = new MockNFT();

        // 替换为上一步生成的 Merkle Root
        bytes32 root = 0x...你的root...;
        AirdropMerkleNFTMarket market = new AirdropMerkleNFTMarket(
            root, address(token), address(nft)
        );

        vm.stopBroadcast();

        console.log("Token: ", address(token));
        console.log("NFT:   ", address(nft));
        console.log("Market:", address(market));
    }
}
```

```bash
# 终端 2：部署（必须指定 --private-key，否则报 "default sender" 错误）
forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

记录输出的三个合约地址。

## 五、手动交互测试（以 Account #0 为例）

> 以下用 Anvil 的 Account #0 演示
>
> - 地址: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`
> - 私钥: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`

### 5.1 给白名单地址发 Token

```bash
# Account #0 已有 10000 ETH（Anvil 自带），但需要 Token
cast send <TOKEN_ADDRESS> \
  "mint(address,uint256)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  10000000000000000000000 \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 5.2 链下签名 EIP-712 Permit

创建 `script/signPermit.ts`：

```typescript
import { createWalletClient, http, keccak256, encodePacked } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { anvil } from "viem/chains";

const PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const TOKEN = "<TOKEN_ADDRESS>";
const MARKET = "<MARKET_ADDRESS>";
const PRICE = 100n * 10n ** 18n;

async function main() {
  const account = privateKeyToAccount(PK);

  // 获取 nonce 和 DOMAIN_SEPARATOR（需要从链上读，这里简化为手动输入）
  // const nonce = await publicClient.readContract({ ... });
  // const domainSeparator = await publicClient.readContract({ ... });

  // 用 cast 获取：
  // cast call <TOKEN> "nonces(address)" 0xf39F...2266 --rpc-url http://localhost:8545
  // cast call <TOKEN> "DOMAIN_SEPARATOR()" --rpc-url http://localhost:8545

  // 然后用 account.signTypedData({ ... }) 签名
}

main();
```

> **更简单的方式**：直接用 Foundry 测试中的 `vm.sign()` 逻辑，把签名结果硬编码到 cast 命令中。

### 5.3 调用 multicall

```bash
# Step 1: 编码 permitPrePay
PERMIT_DATA=$(cast calldata "permitPrePay(address,uint256,uint8,bytes32,bytes32)" \
  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  9999999999 \
  27 \
  0x...r \
  0x...s)

# Step 2: 编码 claimNFT（用你生成的 proof 替换）
CLAIM_DATA=$(cast calldata "claimNFT(bytes32[])" \
  "[0x...proof0, 0x...proof1]")

# Step 3: 一次交易完成
cast send <MARKET_ADDRESS> \
  "multicall(bytes[])" \
  "[$PERMIT_DATA, $CLAIM_DATA]" \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## 六、验证结果

```bash
# 检查是否已领取 → true
cast call <MARKET_ADDRESS> \
  "hasClaimed(address)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --rpc-url http://localhost:8545

# 检查 NFT 归属 → 0xf39F...2266
cast call <NFT_ADDRESS> \
  "ownerOf(uint256)" 1 \
  --rpc-url http://localhost:8545

# 合约收到 100 Token
cast call <TOKEN_ADDRESS> \
  "balanceOf(address)" <MARKET_ADDRESS> \
  --rpc-url http://localhost:8545
# → 100000000000000000000
```

## 七、Foundry 单元测试

```bash
# 全部 10 项测试
forge test --match-path test/AirdropMerkleNFTMarket.t.sol -vvv

# 预期：10 passed; 0 failed
```

## 八、测试用例清单

| # | 测试项 | 预期结果 |
|---|--------|----------|
| 1 | Anvil 白名单地址 + 正确 proof | ✅ 铸造 NFT，扣 100 Token |
| 2 | 非白名单地址 + 任意 proof | ❌ revert "not in whitelist" |
| 3 | 白名单地址 + 错误 proof | ❌ Merkle 验证失败 |
| 4 | 同一地址重复领取 | ❌ revert "already claimed" |
| 5 | 不签名 permit 直接 claimNFT | ❌ transferFrom 失败 |
| 6 | permit 签名过期后调用 | ❌ revert "PERMIT: expired" |
| 7 | multicall 附带 ETH | ❌ EVM 直接拒绝 |
| 8 | 非 owner 更新 merkleRoot | ❌ revert "not owner" |

## 九、本地 vs 主网对照

| | 本地 Anvil 测试 | 主网部署 |
|:--|:--|:--|
| **白名单地址** | Anvil 生成的测试地址（你有私钥） | 真实用户钱包地址 |
| **签名** | 用 Anvil 私钥签名 | 用户用 MetaMask 签名 |
| **Token** | MockERC20Permit | USDC / 自己的 Token |
| **NFT** | MockNFT | 你自己的 NFT 合约 |
| **Merkle Root** | 从测试地址生成 | 从真实地址生成 |
