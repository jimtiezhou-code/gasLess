// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MyUpgradeableNFT_V2} from "../src/MyUpgradeableNFT_V2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract UpgradeMyNFT is Script {
    function run() external {
        address proxy = vm.envAddress("PROXY_ADDRESS");

        vm.startBroadcast();

        // 1. 部署 V2 实现合约
        MyUpgradeableNFT_V2 newImpl = new MyUpgradeableNFT_V2();

        // 2. 升级 Proxy 指向新实现
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImpl), "");

        vm.stopBroadcast();

        console.log("V2 Implementation:", address(newImpl));
        console.log("Proxy:", proxy);
        console.log("Version:", MyUpgradeableNFT_V2(proxy).version());
    }
}
