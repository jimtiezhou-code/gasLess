/**
 * 默克尔树白名单生成脚本（TypeScript + viem）
 *
 * 用法：
 *   1. 编辑下方 WHITELIST 数组
 *   2. npm run generate:merkle
 *   3. 将 merkleRoot 部署到 AirdropMerkleNFTMarket 合约
 *   4. 将每个地址的 proof 分发给对应用户
 *
 * 原理：
 *   - 每个地址 → keccak256(encodePacked(address)) → 叶子哈希
 *   - 相邻叶子配对哈希 → 上层的节点
 *   - 逐层递归直到根
 *   - 每个叶子的 proof = 路径上所有兄弟节点
 */

import {
  keccak256,
  encodePacked,
  type Address,
  type Hex,
} from "viem";

// ============================
// 1. 配置白名单地址
// ============================
const WHITELIST: Address[] = [
  "0x1111111111111111111111111111111111111111",
  "0x2222222222222222222222222222222222222222",
  "0x3333333333333333333333333333333333333333",
  "0x4444444444444444444444444444444444444444",
  "0x5555555555555555555555555555555555555555",
  "0x6666666666666666666666666666666666666666",
  "0x7777777777777777777777777777777777777777",
];

// ============================
// 2. 类型定义
// ============================
interface MerkleTree {
  root: Hex;
  layers: Hex[][];
  proofs: Map<Address, Hex[]>;
  originalCount: number;
}

// ============================
// 3. 核心函数
// ============================

/**
 * 计算叶子节点哈希 — 与合约 _verifyMerkle 一致:
 * keccak256(abi.encodePacked(address))
 */
function leafHash(addr: Address): Hex {
  return keccak256(encodePacked(["address"], [addr]));
}

/**
 * 排序后配对哈希 — 与合约 _hashPair 一致:
 * a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a))
 */
function hashPair(a: Hex, b: Hex): Hex {
  // bytes32 按字典序比较（去掉 0x 前缀后比较）
  const aRaw = a.slice(2);
  const bRaw = b.slice(2);
  const [first, second] = aRaw < bRaw ? [a, b] : [b, a];
  return keccak256(encodePacked(["bytes32", "bytes32"], [first, second]));
}

/**
 * 构建默克尔树
 */
function buildMerkleTree(addresses: Address[]): MerkleTree {
  // Step 1: 计算所有叶子哈希
  let leaves: Hex[] = addresses.map(leafHash);
  const originalCount = leaves.length;
  const layers: Hex[][] = [leaves];

  // Step 2: 逐层哈希直到根
  // 如果某层节点为奇数，复制最后一个补齐
  while (leaves.length > 1) {
    const nextLayer: Hex[] = [];

    for (let i = 0; i < leaves.length; i += 2) {
      if (i + 1 < leaves.length) {
        nextLayer.push(hashPair(leaves[i], leaves[i + 1]));
      } else {
        // 奇数个节点 → 自己与自己配对
        nextLayer.push(hashPair(leaves[i], leaves[i]));
      }
    }

    layers.push(nextLayer);
    leaves = nextLayer;
  }

  const root = leaves[0];

  // Step 3: 为每个原始叶子生成 Merkle Proof
  const proofs = new Map<Address, Hex[]>();

  for (let i = 0; i < originalCount; i++) {
    const proof: Hex[] = [];
    let index = i;

    // 从叶子层向上走到倒数第二层
    for (let layer = 0; layer < layers.length - 1; layer++) {
      const currentLayer = layers[layer];
      const siblingIndex = index % 2 === 0 ? index + 1 : index - 1;
      // 超界时（奇数层尾）兄弟为自己
      const actualSiblingIndex =
        siblingIndex < currentLayer.length ? siblingIndex : index;
      proof.push(currentLayer[actualSiblingIndex]);
      // 父节点索引
      index = Math.floor(index / 2);
    }

    proofs.set(addresses[i], proof);
  }

  return { root, layers, proofs, originalCount };
}

// ============================
// 4. 运行 & 输出
// ============================

const { root, layers, proofs, originalCount } = buildMerkleTree(WHITELIST);

console.log("══════════════════════════════════════════════");
console.log("  Merkle Tree 白名单生成结果");
console.log("══════════════════════════════════════════════\n");

console.log(`白名单人数 : ${originalCount}`);
console.log(`树深度     : ${layers.length - 1} 层`);
console.log(`Proof 大小 : ${proofs.get(WHITELIST[0])!.length} 个元素\n`);

console.log("────────────────────────────────────────");
console.log("  Merkle Root（部署到合约）");
console.log("────────────────────────────────────────");
console.log(`  ${root}\n`);

console.log("────────────────────────────────────────");
console.log("  各层节点");
console.log("────────────────────────────────────────");
layers.forEach((layer, i) => {
  const label =
    i === 0
      ? "叶子层"
      : i === layers.length - 1
        ? "根层"
        : `第 ${i} 层`;
  console.log(`  ${label} (${layer.length} 个节点):`);
  layer.forEach((node, j) => {
    console.log(`    [${j}] ${node}`);
  });
});

console.log("\n────────────────────────────────────────");
console.log("  Merkle Proof（每个地址的证明）");
console.log("────────────────────────────────────────");
WHITELIST.forEach((addr, i) => {
  const proof = proofs.get(addr)!;
  console.log(`\n  ${addr}`);
  console.log(`  Leaf: ${leafHash(addr)}`);
  console.log(`  Proof:`);
  proof.forEach((p, j) => console.log(`    [${j}] ${p}`));
});

console.log("\n────────────────────────────────────────");
console.log("  Solidity Multicall 调用示例（ethers/viem）");
console.log("────────────────────────────────────────");

// 以第一个地址为例展示
const exampleAddr = WHITELIST[0];
const exampleProof = proofs.get(exampleAddr)!;
console.log(`
// 第 1 步：离线签名 permit
const { v, r, s } = await wallet.signTypedData(
  {
    name: "MockToken",
    version: "1",
    chainId: 31337,
    verifyingContract: tokenAddress,
  },
  {
    Permit: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  },
  {
    owner: "${exampleAddr}",
    spender: marketAddress,
    value: 100n * 10n**18n,
    nonce: await token.nonces("${exampleAddr}"),
    deadline: Math.floor(Date.now()/1000) + 3600,
  }
);

// 第 2 步：multicall 一次性执行
const iface = new ethers.Interface(ABI);
const multicallData = [
  iface.encodeFunctionData("permitPrePay", [
    "${exampleAddr}",
    deadline,
    v,
    r,
    s,
  ]),
  iface.encodeFunctionData("claimNFT", [
    [
${exampleProof.map((p) => `      "${p}"`).join(",\n")}
    ],
  ]),
];

const tx = await market.multicall(multicallData);
await tx.wait();
console.log("NFT claimed!");
`);

// ============================
// 5. 自检：在内存中验证所有 proof
// ============================
console.log("────────────────────────────────────────");
console.log("  自检：验证所有证明");
console.log("────────────────────────────────────────");

let allPassed = true;
for (const addr of WHITELIST) {
  const proof = proofs.get(addr)!;
  let current = leafHash(addr);
  for (const sibling of proof) {
    current = hashPair(current, sibling);
  }
  const passed = current === root;
  if (!passed) allPassed = false;
  console.log(`  ${addr}: ${passed ? "✓ PASS" : "✗ FAIL"}`);
}

// 验证不在白名单的地址
const fakeAddr: Address = "0x9999999999999999999999999999999999999999";
const fakeLeaf = leafHash(fakeAddr);
let fakeCurrent = fakeLeaf;
const exampleProof2 = proofs.get(WHITELIST[0])!;
for (const sibling of exampleProof2) {
  fakeCurrent = hashPair(fakeCurrent, sibling);
}
console.log(
  `  ${fakeAddr} (非白名单): ${fakeCurrent !== root ? "✓ REJECTED" : "✗ FALSE POSITIVE"}`,
);

if (allPassed) {
  console.log("\n✓ 所有证明验证通过！\n");
  console.log("部署步骤：");
  console.log("  1. 部署 MockERC20Permit（或使用现有 ERC20）");
  console.log("  2. 部署 MockNFT");
  console.log("  3. 部署 AirdropMerkleNFTMarket，传入 merkleRoot");
  console.log("  4. npm run generate:merkle 生成白名单和 proof");
  console.log("  5. 前端组装 multicall([permitPrePay, claimNFT]) 调用\n");
}

// ============================
// 6. 导出供外部引用
// ============================
export { buildMerkleTree, leafHash, hashPair };
export type { MerkleTree };
