# AirdropMerkleNFTMarket 测试流程

## 一、环境准备

```bash
# 进入项目目录
cd /Users/jim123/Desktop/hello_foundry/gasLess

# 安装 Node 依赖（默克尔树生成脚本用）
npm install

# 编译合约
forge build
```

## 二、生成白名单默克尔树

```bash
# 1. 编辑白名单地址
vim script/generateMerkleTree.ts
# 修改 WHITELIST 数组为你自己的地址

# 2. 生成默克尔树
npm run generate:merkle
```

输出示例：

```
Merkle Root（部署到合约）
  0xd81ff130b652815b3567e6e8db822cb918a6c0aee2796a570a1e6a7a32b71c82

各地址的 Merkle Proof:
  [0] 0x1111...1111
      Proof:
        [0] 0x2ab0...0751
        [1] 0x0aaf...f346
        [2] 0xd753...516a
  ...
```

记录下 **Merkle Root** 和你的地址对应的 **Proof**。

## 三、部署合约（本地 Anvil 链）

```bash
# 终端 1：启动本地节点
anvil
```

创建部署脚本 `script/Deploy.s.sol`：

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

        bytes32 root = 0xd81ff130b652815b3567e6e8db822cb918a6c0aee2796a570a1e6a7a32b71c82;
        AirdropMerkleNFTMarket market = new AirdropMerkleNFTMarket(
            root, address(token), address(nft)
        );

        vm.stopBroadcast();

        console.log("Token:", address(token));
        console.log("NFT:", address(nft));
        console.log("Market:", address(market));
    }
}
```

```bash
# 终端 2：部署（使用 anvil 的默认私钥 0）
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## 四、手动交互测试

### 4.1 给测试地址发 Token

```bash
cast send <TOKEN_ADDRESS> \
  "mint(address,uint256)" \
  0x1111111111111111111111111111111111111111 \
  10000000000000000000000 \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 4.2 签名 Permit（链下）

```bash
# 获取 nonce
cast call <TOKEN_ADDRESS> "nonces(address)" 0x1111...1111 --rpc-url http://localhost:8545

# 获取 DOMAIN_SEPARATOR
cast call <TOKEN_ADDRESS> "DOMAIN_SEPARATOR()" --rpc-url http://localhost:8545

# 用 cast wallet sign 签名
# 或用 Node.js 脚本签名（推荐，参考 generateMerkleTree.ts 中的 signTypedData 示例）
```

### 4.3 调用 multicall

```bash
# 编码 permitPrePay
cast calldata "permitPrePay(address,uint256,uint8,bytes32,bytes32)" \
  0x1111...1111 \
  9999999999 \
  27 \
  0x...r \
  0x...s

# 编码 claimNFT
cast calldata "claimNFT(bytes32[])" \
  "[0x2ab0...0751, 0x0aaf...f346, 0xd753...516a]"

# 调用 multicall（发送交易）
cast send <MARKET_ADDRESS> \
  "multicall(bytes[])" \
  "[<permitPrePay_calldata>, <claimNFT_calldata>]" \
  --rpc-url http://localhost:8545 \
  --private-key <白名单用户的私钥>
```

## 五、运行 Foundry 单元测试

```bash
# 只跑 AirdropMerkleNFTMarket 测试
forge test --match-path test/AirdropMerkleNFTMarket.t.sol -vvv

# 查看 gas 报告
forge test --match-path test/AirdropMerkleNFTMarket.t.sol --gas-report
```

## 六、验证结果

```bash
# 检查用户是否已领取
cast call <MARKET_ADDRESS> "hasClaimed(address)" 0x1111...1111 --rpc-url http://localhost:8545
# → true

# 检查 NFT 归属
cast call <NFT_ADDRESS> "ownerOf(uint256)" 1 --rpc-url http://localhost:8545
# → 0x1111...1111

# 检查 Token 余额（合约收到 100 Token）
cast call <TOKEN_ADDRESS> "balanceOf(address)" <MARKET_ADDRESS> --rpc-url http://localhost:8545
# → 100000000000000000000
```

## 七、测试用例清单

| # | 测试项 | 预期结果 |
|---|--------|----------|
| 1 | 白名单地址 + 正确 proof | ✅ 铸造 NFT，扣 100 Token |
| 2 | 非白名单地址 + 任意 proof | ❌ revert "not in whitelist" |
| 3 | 白名单地址 + 错误 proof | ❌ Merkle 验证失败 |
| 4 | 同一地址重复领取 | ❌ revert "already claimed" |
| 5 | 不签名 permit 直接 claimNFT | ❌ transferFrom 失败 |
| 6 | permit 签名过期后调用 | ❌ revert "PERMIT: expired" |
| 7 | multicall 附带 ETH | ❌ EVM 直接拒绝 |
| 8 | 非 owner 更新 merkleRoot | ❌ revert "not owner" |

## 八、一键运行所有测试

```bash
# 编译 + 全部测试
forge build && forge test --match-path test/AirdropMerkleNFTMarket.t.sol -vvv

# 预期输出：10 passed; 0 failed
```
