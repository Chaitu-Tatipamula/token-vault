// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";

contract VaultTest is Test {
    TokenMetricsVault vault;
    MockUSDC usdc;
    MockStrategy stratA;
    MockStrategy stratB;

    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);

    function setUp() public {
        vm.startPrank(admin);
        usdc = new MockUSDC();
        vault = new TokenMetricsVault(usdc, admin);
        vault.setMaxAllocation(10000); // Allow 100% for general tests
        
        stratA = new MockStrategy(address(usdc));
        stratB = new MockStrategy(address(usdc));
        
        vault.addStrategy(address(stratA));
        vault.addStrategy(address(stratB));

        stratA.setApproved(address(vault), true);
        stratB.setApproved(address(vault), true);
        
        usdc.mint(user1, 10_000 * 10**6);
        usdc.mint(user2, 10_000 * 10**6);
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user1);
        usdc.approve(address(vault), 1000 * 10**6);
        
        uint256 shares = vault.deposit(1000 * 10**6, user1);
        
        assertEq(shares, 1000 * 10**6); // 1:1 initially
        assertEq(vault.totalAssets(), 1000 * 10**6);
        vm.stopPrank();
    }

    function testAllocationAndRebalance() public {
        // User deposits
        testDeposit(); 

        vm.startPrank(admin);
        // Set 50% allocation to Strat A
        vault.setAllocation(address(stratA), 5000); // 50%
        vault.rebalance();
        
        // Check balances
        assertEq(usdc.balanceOf(address(stratA)), 500 * 10**6, "Strat A should have 500 USDC");
        assertEq(usdc.balanceOf(address(vault)), 500 * 10**6, "Vault should have 500 USDC idle");
        
        // Set 100% to Strat A
        vault.setAllocation(address(stratA), 10000);
        vault.rebalance();
        assertEq(usdc.balanceOf(address(stratA)), 1000 * 10**6, "Strat A should have 1000 USDC");
        assertEq(usdc.balanceOf(address(vault)), 0, "Vault should be empty");
        vm.stopPrank();
    }

    function testValueAccrual() public {
        testAllocationAndRebalance(); // Vault has 1000 in Strat A

        vm.startPrank(admin);
        // Simulate 10% yield in Strat A
        stratA.simulateYield(100 * 10**6); 
        vm.stopPrank();

        // Total Assets should be 1100
        assertEq(vault.totalAssets(), 1100 * 10**6);
        
        // Share price check
        // User1 has 1000 shares.
        // Price = 1100 / 1000 = 1.1
        // One share worth 1.1 USDC
        uint256 assets = vault.convertToAssets(1000 * 10**6);
        assertApproxEqAbs(assets, 1100 * 10**6, 10);
    }

    function testWithdrawalQueue() public {
        testAllocationAndRebalance(); // 1000 in Strat A (Active)

        vm.startPrank(admin);
        // Lock Strat A for 1 day
        stratA.setLockup(1 days);
        vm.stopPrank();

        // User tries standard withdraw -> Should fail
        // Vault has 0 idle. Strat A is locked.
        vm.startPrank(user1);
        vm.expectRevert(); // Standard withdraw should fail
        vault.withdraw(500 * 10**6, user1, user1);

        // User requests withdrawal
        vault.requestWithdrawal(500 * 10**6);
        
        // Check state
        (uint256 shares, uint256 assets, uint256 claimable, , ) = vault.withdrawalQueue(user1, 0);
        // Shares were burnt immediately in implementation
        assertEq(vault.balanceOf(user1), 500 * 10**6); // 1000 - 500
        assertEq(vault.userClaimableAssets(user1), 500 * 10**6);
        
        // Try to claim -> Should fail (no liquidity)
        vm.expectRevert("Vault still illiquid");
        vault.claimWithdrawal();
        vm.stopPrank();

        // Admin unlocks/time passes
        vm.warp(block.timestamp + 1 days + 1);
        
        // Admin or someone triggers rebalance/withdraw from strat to fill buffer
        vm.stopPrank();
        
        // Vault withdraws from strategy to replenish liquid buffers
        vm.prank(address(vault));
        stratA.withdraw(500 * 10**6); 
        // Now vault has 500 USDC.

        vm.startPrank(user1);
        vault.claimWithdrawal();
        
        assertEq(usdc.balanceOf(user1), 500 * 10**6 + (9000 * 10**6)); // 9000 left from initial + 500 recovered
        assertEq(vault.userClaimableAssets(user1), 0);
        vm.stopPrank();
    }

    function testFuzz_Withdraw(uint256 amount) public {
        amount = bound(amount, 1 * 10**6, 10_000 * 10**6);
        
        vm.startPrank(user1);
        usdc.approve(address(vault), amount);
        vault.deposit(amount, user1);
        
        uint256 shares = vault.balanceOf(user1);
        vault.redeem(shares, user1, user1);
        
        assertApproxEqAbs(usdc.balanceOf(user1), 10_000 * 10**6, 1);
        vm.stopPrank();
    }
}
