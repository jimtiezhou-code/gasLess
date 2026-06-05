// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyUpgradeableNFT} from "../src/MyUpgradeableNFT.sol";

contract DeployMyNFT is Script {
    function run() external {
        address owner = msg.sender;

        vm.startBroadcast();

        // 1. 部署 V1 实现合约
        MyUpgradeableNFT impl = new MyUpgradeableNFT();

        // 2. 编码初始化调用
        bytes memory initData = abi.encodeCall(
            MyUpgradeableNFT.initialize,
            (owner, "My Upgradeable NFT", "MNFT")
        );

        // 3. 部署代理（原子初始化）
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);

        vm.stopBroadcast();

        console.log("V1 Implementation:", address(impl));
        console.log("Proxy:", address(proxy));
    }
}
