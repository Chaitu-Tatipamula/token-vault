// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";
import {HyperCoreStrategy} from "../src/strategies/HyperCoreStrategy.sol";

contract DeployAdditionalStrategy is Script {
    // Existing Addresses on HyperEVM Mainnet
    address constant VAULT = 0xd2c159Ba0a32F96F2a0d60D569D47b5657582176;
    address constant USDC = 0xA4b67922E19f5c3b7e04f36A13E7eCF87FA9B374;
    address constant HC_STRATEGY = 0x31d3e58a53DcbD61B3756457b10F4C99b49d40C0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TokenMetricsVault vault = TokenMetricsVault(VAULT);

        // 1. Deploy Generic MockStrategy
        MockStrategy mockStrat = new MockStrategy(USDC);
        console.log("MockStrategy deployed at:", address(mockStrat));

        // 2. Add Strategy to Vault
        vault.addStrategy(address(mockStrat));
        console.log("MockStrategy added to Vault");

        // 3. Update Allocations (50% HyperCore, 30% Mock, 20% Idle)
        // Note: HyperCore is already at 50% (5000 bps)
        vault.setAllocation(address(mockStrat), 3000); // 30%
        console.log("Set MockStrategy allocation to 30%");

        // 4. permissions
        mockStrat.setApproved(address(vault), true);
        console.log("Approved Vault to withdraw from MockStrategy");

        vm.stopBroadcast();
    }
}
