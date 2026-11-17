// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDG} from "../src/MockUSDG.sol";
import {BRLPay} from "../src/BRLPay.sol";

/// @notice Deploy BRLPay + MockUSDG to Arbitrum Sepolia (chain 421614).
/// Usage:
///   PRIVATE_KEY=<muse-evm-key> forge script script/Deploy.s.sol \
///     --rpc-url arbitrum_sepolia --broadcast
/// The deployer receives $10,000 mUSDG for the demo. Addresses are written
/// to deployments.json at the project root.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        MockUSDG usdg = new MockUSDG();
        BRLPay pay = new BRLPay(address(usdg));
        usdg.mint(deployer, 10_000_000_000); // $10,000 mUSDG (6 decimals)
        vm.stopBroadcast();

        console.log("MockUSDG:", address(usdg));
        console.log("BRLPay:", address(pay));
        console.log("deployer:", deployer);
        console.log("chainId:", block.chainid);
        // NOTE: deployments.json is written by the deploy wrapper script
        // (deploy-brlpay.py) by parsing the logs above — forge scripts
        // cannot write files outside the allowed paths.
    }
}
