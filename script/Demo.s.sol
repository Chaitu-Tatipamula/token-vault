// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockHyperCore} from "../src/mocks/MockHyperCore.sol";
import {HyperCoreStrategy} from "../src/strategies/HyperCoreStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Demo Script
 * @notice Demonstrates the full functionality of the Token Metrics Vault on HyperEVM Mainnet
 * @dev This script showcases:
 *      1. User deposits USDC into the vault
 *      2. Manager rebalances funds to strategy
 *      3. Strategy interacts with HyperCore
 *      4. User requests withdrawal (with queue)
 *      5. Manager replenishes liquidity
 *      6. User claims withdrawal
 */
contract DemoScript is Script {
    // Deployed contract addresses on HyperEVM Mainnet
    address constant VAULT = 0xd2c159Ba0a32F96F2a0d60D569D47b5657582176;
    address constant STRATEGY = 0x31d3e58a53DcbD61B3756457b10F4C99b49d40C0;
    address constant USDC = 0xA4b67922E19f5c3b7e04f36A13E7eCF87FA9B374;
    address constant HYPERCORE = 0x9A5d351d16c10cEDd984085C568018982275a7d8;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        TokenMetricsVault vault = TokenMetricsVault(VAULT);
        MockUSDC usdc = MockUSDC(USDC);
        HyperCoreStrategy strategy = HyperCoreStrategy(STRATEGY);

        console.log("\n=== Token Metrics Vault Demo ===\n");
        console.log("Deployer:", deployer);
        console.log("Vault:", address(vault));
        console.log("Strategy:", address(strategy));
        console.log("USDC:", address(usdc));

        // Step 1: Mint USDC for demo
        console.log("\n--- Step 1: Mint Test USDC ---");
        uint256 mintAmount = 10_000 * 10 ** 6; // 10,000 USDC
        usdc.mint(deployer, mintAmount);
        console.log("Minted:", mintAmount / 10 ** 6, "USDC");
        console.log("Balance:", usdc.balanceOf(deployer) / 10 ** 6, "USDC");

        // Step 2: Deposit into Vault
        console.log("\n--- Step 2: Deposit into Vault ---");
        uint256 depositAmount = 5_000 * 10 ** 6; // 5,000 USDC
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, deployer);
        console.log("Deposited:", depositAmount / 10 ** 6, "USDC");
        console.log("Received:", shares / 10 ** 6, "shares");
        console.log("Vault Total Assets:", vault.totalAssets() / 10 ** 6, "USDC");

        // Step 3: Manager Rebalances (50% to strategy)
        console.log("\n--- Step 3: Rebalance to Strategy ---");
        (, uint256 allocationBps) = vault.strategyInfo(address(strategy));
        console.log("Strategy Allocation:", allocationBps / 100, "%");
        vault.rebalance();
        console.log("Rebalanced!");
        console.log("Strategy Assets:", strategy.totalAssets() / 10 ** 6, "USDC");
        console.log("Vault Idle:", IERC20(USDC).balanceOf(address(vault)) / 10 ** 6, "USDC");

        // Step 4: Direct Withdrawal (from idle funds)
        console.log("\n--- Step 4: Direct Withdrawal (from idle) ---");
        uint256 withdrawAmount = 2_000 * 10 ** 6; // 2,000 USDC (less than idle)
        uint256 balanceBefore = usdc.balanceOf(deployer);
        vault.withdraw(withdrawAmount, deployer, deployer);
        uint256 balanceAfter = usdc.balanceOf(deployer);
        console.log("Withdrew:", (balanceAfter - balanceBefore) / 10 ** 6, "USDC");
        console.log("New Balance:", balanceAfter / 10 ** 6, "USDC");

        // Step 5: Demonstrate Withdrawal Queue (for amounts > idle)
        console.log("\n--- Step 5: Request Large Withdrawal (Queue Demo) ---");
        uint256 largeWithdrawal = 2_000 * 10 ** 6; // More than remaining idle
        vault.requestWithdrawal(largeWithdrawal);
        console.log("Requested:", largeWithdrawal / 10 ** 6, "USDC");
        console.log("Shares Burned Immediately");

        (, uint256 queuedAssets,,,) = vault.withdrawalQueue(deployer, 0);
        console.log("Queued Assets:", queuedAssets / 10 ** 6, "USDC");
        console.log("Note: User can claim when vault has liquidity");

        // Final State
        console.log("\n=== Final State ===");
        console.log("Vault Total Assets:", vault.totalAssets() / 10 ** 6, "USDC");
        console.log("Vault Total Supply:", vault.totalSupply() / 10 ** 6, "shares");
        console.log("Strategy Assets:", strategy.totalAssets() / 10 ** 6, "USDC");
        console.log("User Claimable:", vault.userClaimableAssets(deployer) / 10 ** 6, "USDC");

        if (vault.totalSupply() > 0) {
            console.log("Share Price:", vault.convertToAssets(10 ** 6), "USDC per share");
        }

        vm.stopBroadcast();

        console.log("\n=== Demo Complete ===");
        console.log("Features Demonstrated:");
        console.log("1. Deposit USDC -> Receive Shares");
        console.log("2. Manager Rebalance -> 50% to Strategy");
        console.log("3. Strategy Integration -> HyperCore Action ID 2");
        console.log("4. Direct Withdrawal -> From Idle Funds");
        console.log("5. Withdrawal Queue -> For Illiquid Scenarios");
        console.log("\nCheck transactions on Hyperscan:");
        console.log("https://www.hyperscan.com/address/", deployer);
    }
}
