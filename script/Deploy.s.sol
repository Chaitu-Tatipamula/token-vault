// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockHyperCore} from "../src/mocks/MockHyperCore.sol";
import {HyperCoreStrategy} from "../src/strategies/HyperCoreStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));

        // // 2. Deploy Mock HyperCore (to receive Action ID 2)
        MockHyperCore coreWriter = new MockHyperCore();
        console.log("MockHyperCore deployed at:", address(coreWriter));
        
        // 3. Deploy Vault
        TokenMetricsVault vault = new TokenMetricsVault(IERC20(address(usdc)), deployerAddr);
        vault.setMaxAllocation(10000); // Allow 100% allocation
        console.log("TokenMetricsVault deployed at:", address(vault));

        // 4. Deploy HyperCore Strategy (Adapter)
        HyperCoreStrategy hcStrat = new HyperCoreStrategy(address(usdc), address(coreWriter));
        console.log("HyperCoreStrategy deployed at:", address(hcStrat));

        // 5. Wire up the system
        // Add Strategy
        vault.addStrategy(address(hcStrat));
        
        // Set Allocation (e.g. 50% for now)
        vault.setAllocation(address(hcStrat), 5000);
        console.log("System wired up: Strategy added and allocated 50%");

        // 6. Mint test funds to deployer (so you can test on Mainnet immediately)
        // usdc.mint(deployerAddr, 10_000 * 10**6); // Mint 10,000 USDC
        // console.log("Minted 10,000 MockUSDC to deployer");

        vm.stopBroadcast();
    }
}
