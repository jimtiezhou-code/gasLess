/**
 * EIP-712 Permit 离线签名脚本
 * 用法: npx tsx script/signPermit.ts
 */

import { createPublicClient, http, parseAbi } from "viem";
import { privateKeyToAccount, privateKeyToAddress, signTypedData } from "viem/accounts";

const RPC = "http://localhost:8545";
const TOKEN = "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9";
const MARKET = "0x0165878A594ca255338adfa4d48449f69242Eb8F";

const KEYS: [string, `0x${string}`][] = [
  ["Account0", "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"],
  ["Account1", "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"],
  ["Account2", "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"],
];

const PRICE = 100n * 10n ** 18n;

async function main() {
  const pc = createPublicClient({ transport: http(RPC) });
  const chainId = await pc.getChainId();
  const tokenAbi = parseAbi(["function nonces(address) view returns (uint256)"]);

  for (const [name, pk] of KEYS) {
    const user = privateKeyToAddress(pk);
    const nonce = await pc.readContract({
      address: TOKEN as `0x${string}`, abi: tokenAbi,
      functionName: "nonces", args: [user],
    });
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const sig = await signTypedData({
      privateKey: pk,
      domain: { name: "MockToken", version: "1", chainId, verifyingContract: TOKEN as `0x${string}` },
      types: {
        Permit: [
          { name: "owner", type: "address" }, { name: "spender", type: "address" },
          { name: "value", type: "uint256" }, { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      },
      primaryType: "Permit",
      message: { owner: user, spender: MARKET as `0x${string}`, value: PRICE, nonce, deadline },
    });

    const r = sig.slice(0, 66);
    const s = "0x" + sig.slice(66, 130);
    const v = parseInt(sig.slice(130, 132), 16);

    console.log(`=== ${name} | ${user} ===`);
    console.log(`deadline=${deadline}  v=${v}`);
    console.log(`r=${r}`);
    console.log(`s=${s}\n`);
  }
}

main().catch(console.error);
