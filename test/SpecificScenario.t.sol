// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockStrategy} from "../src/mocks/MockStrategy.sol";

contract SpecificScenarioTest is Test {
    TokenMetricsVault vault;
    MockUSDC usdc;
    MockStrategy stratA;
    MockStrategy stratB;

    address admin = address(0x1);
    address user = address(0x2);

    function setUp() public {
        vm.startPrank(admin);
        usdc = new MockUSDC();
        vault = new TokenMetricsVault(usdc, admin);
        
        stratA = new MockStrategy(address(usdc));
        stratB = new MockStrategy(address(usdc));
        
        vault.addStrategy(address(stratA));
        vault.addStrategy(address(stratB));
        stratA.setApproved(address(vault), true);
        stratB.setApproved(address(vault), true);
        
        usdc.mint(user, 10_000 * 10**6);
        vm.stopPrank();
    }
    
    function testSpecificAssignmentFlow() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1000 * 10**6);
        vault.deposit(1000 * 10**6, user);
        vm.stopPrank();

        vm.startPrank(admin);
        vault.setAllocation(address(stratA), 6000); // 60%
        vault.setAllocation(address(stratB), 4000); // 40%
        vault.rebalance();
        vm.stopPrank();

        // Check 600 in A, 400 in B
        assertEq(usdc.balanceOf(address(stratA)), 600 * 10**6);
        assertEq(usdc.balanceOf(address(stratB)), 400 * 10**6);

        // Protocol A increases in value by 10%
        vm.startPrank(admin);
        // 10% of 600 is 60. New total 660.
        stratA.simulateYield(60 * 10**6); 
        vm.stopPrank();

        // User's shares are now worth ~1060 USDC
        // Total Assets = 660 (A) + 400 (B) = 1060.
        uint256 assets = vault.convertToAssets(1000 * 10**6);
        assertApproxEqAbs(assets, 1060 * 10**6, 100);

        // User withdraws (handle if Protocol B has lockup)
        vm.startPrank(admin);
        stratB.setLockup(1 days); // Lock B
        vm.stopPrank();

        vm.startPrank(user);
        // User tries to withdraw all 1060.
        // Available liquidity:
        // Idle: 0
        // Strat A: 660 (Liquid)
        // Strat B: 400 (Locked)
        // Max withdrawable now = 660.
        
        // If user calls withdraw(all), it should revert due to lockup.
        uint256 userAssets = vault.convertToAssets(vault.balanceOf(user));
        vm.expectRevert("Insufficient liquidity. Use requestWithdrawal.");
        vault.withdraw(userAssets, user, user);

        // User requests withdrawal
        vault.requestWithdrawal(userAssets);
        vm.stopPrank();

        // Check Queue
        (uint256 shares, uint256 reqAssets, , , ) = vault.withdrawalQueue(user, 0);
        assertApproxEqAbs(reqAssets, 1060 * 10**6, 100);
    }
}
