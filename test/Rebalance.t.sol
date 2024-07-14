// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Rebalance} from "src/Rebalance.sol";
import {IERC20} from "src/additions/erc20.sol";

contract CounterTest is Test {
    Rebalance public rebalance;

    function setUp() public {
        rebalance = new Rebalance();
        rebalance.initialize();
    }

    function test_UniswapCalculator() public view {
    (,,,int24 tickNow, bool inRange) = rebalance.slot0();
    assertNotEq(tickNow, 0);
    assertEq(inRange,false);
    }

    function test_Rebalance() public {
        deal(address(rebalance.token1()), address(this), 1 ether);
        IERC20(rebalance.token1()).transfer(address(rebalance), 1 ether);
        assertEq(IERC20(rebalance.token1()).balanceOf(address(rebalance)), 1 ether);

        (,,,int24 tickNow,) = rebalance.slot0();
        tickNow = tickNow - tickNow % 10;
        rebalance.rebalance(tickNow - 1000, tickNow + 1000);

        (,,,tickNow,) = rebalance.slot0();
        tickNow = tickNow - tickNow % 10;
        rebalance.rebalance(tickNow - 300, tickNow + 700);

        (,,,tickNow,) = rebalance.slot0();
        tickNow = tickNow - tickNow % 10;
        rebalance.withdraw(tickNow - 10, tickNow + 10);
    }


    function test_ChangePool() public {
        rebalance.setPool(0x85C31FFA3706d1cce9d525a00f1C7D4A2911754c, 1000 gwei);
        assertEq(address(rebalance.token1()),0x68f180fcCe6836688e9084f035309E29Bf0A2095);
    }
}
