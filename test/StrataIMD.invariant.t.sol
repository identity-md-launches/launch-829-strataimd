// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StrataIMD} from "../src/StrataIMD.sol";

/// @dev Exercises arbitrary sequences of valid ERC-20 operations against an independent ledger.
contract StrataHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    StrataIMD public immutable token;
    address[4] public actors = [address(0x101), address(0x102), address(0x103), address(0x104)];
    uint256[4] public expectedBalances;
    uint256[4][4] public expectedAllowances;

    constructor() {
        token = new StrataIMD();
        require(token.transfer(actors[0], SUPPLY));
        expectedBalances[0] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = bound(rawAmount, 0, expectedBalances[from]);
        vm.prank(actors[from]);
        assertTrue(token.transfer(actors[to], amount));
        expectedBalances[from] -= amount;
        expectedBalances[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = unlimited ? type(uint256).max : bound(rawAmount, 0, SUPPLY);
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 to = toSeed % 4;
        uint256 allowance = expectedAllowances[owner][spender];
        uint256 limit = expectedBalances[owner] < allowance ? expectedBalances[owner] : allowance;
        uint256 amount = bound(rawAmount, 0, limit);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[owner], actors[to], amount));
        expectedBalances[owner] -= amount;
        expectedBalances[to] += amount;
        if (allowance != type(uint256).max) expectedAllowances[owner][spender] -= amount;
    }
}

contract StrataIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    StrataHandler private handler;
    StrataIMD private token;

    function setUp() public {
        handler = new StrataHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_balancesAndAllowancesMatchLedgerAndSupplyIsFixed() public view {
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalances(i));
            accounted += balance;
            for (uint256 j; j < 4; ++j) {
                assertEq(token.allowance(actor, handler.actors(j)), handler.expectedAllowances(i, j));
            }
        }
        assertEq(accounted, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
