// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenMetricsVault} from "../src/TokenMetricsVault.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockHyperCore} from "../src/mocks/MockHyperCore.sol";
import {HyperCoreStrategy} from "../src/strategies/HyperCoreStrategy.sol";

contract HyperCoreTest is Test {
    TokenMetricsVault vault;
    MockUSDC usdc;
    MockHyperCore coreWriter;
    HyperCoreStrategy hcStrategy;

    address admin = address(0x1);
    address user = address(0x2);

    function setUp() public {
        vm.startPrank(admin);
        usdc = new MockUSDC();
        vault = new TokenMetricsVault(usdc, admin);
        vault.setMaxAllocation(10000);

        coreWriter = new MockHyperCore();
        hcStrategy = new HyperCoreStrategy(address(usdc), address(coreWriter));

        vault.addStrategy(address(hcStrategy));

        usdc.mint(user, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    function testHyperCoreDepositAction() public {
        vm.startPrank(user);
        usdc.approve(address(vault), 1000 * 10 ** 6);
        vault.deposit(1000 * 10 ** 6, user);
        vm.stopPrank();

        vm.startPrank(admin);
        // Allocate 100% to HyperCore
        vault.setAllocation(address(hcStrategy), 10000);

        // Improve expectation: Check event from MockHyperCore
        // Action ID 2 = Deposit
        vm.expectEmit(false, false, false, true, address(coreWriter));
        emit MockHyperCore.ActionExecuted(2, abi.encode(1000 * 10 ** 6, address(hcStrategy)));

        vault.rebalance();
        vm.stopPrank();

        assertEq(hcStrategy.totalAssets(), 1000 * 10 ** 6);
    }
}
