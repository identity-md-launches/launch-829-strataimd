// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {StrataIMD} from "../src/StrataIMD.sol";

/// @dev Mixes successful and rejected operations. Rejections must leave the ghost ledger unchanged.
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
        // Approvals are not limited by the owner's balance or the token's supply.
        uint256 amount = unlimited ? type(uint256).max : rawAmount;
        _approve(owner, spender, amount);
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

    /// @dev Guarantees nonzero delegated spending even when random approval pairs do not line up.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount, bool unlimited)
        external
    {
        uint256 owner = _fundedOwner(ownerSeed);
        uint256 spender = spenderSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = bound(rawAmount, 1, expectedBalances[owner]);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        vm.prank(actors[spender]);
        assertTrue(token.transferFrom(actors[owner], actors[to], amount));
        expectedBalances[owner] -= amount;
        expectedBalances[to] += amount;
        if (!unlimited) expectedAllowances[owner][spender] = 0;
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        uint256 owner = _fundedOwner(ownerSeed);
        uint256 spender = spenderSeed % 4;
        _approve(owner, spender, 0);
        _expectFailure(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[spender], 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], 0, 1)
        );
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        uint256 from = fromSeed % 4;
        uint256 amount = bound(rawAmount, expectedBalances[from] + 1, type(uint256).max);
        _expectFailure(
            actors[from],
            abi.encodeCall(token.transfer, (actors[toSeed % 4], amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[from], expectedBalances[from], amount
            )
        );
    }

    function rejectTransferFromAboveBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 rawAmount,
        bool unlimited
    ) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = bound(rawAmount, expectedBalances[owner] + 1, type(uint256).max);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        // A finite allowance is spent before the balance check; the revert must restore it.
        _expectFailure(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[toSeed % 4], amount)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actors[owner], expectedBalances[owner], amount
            )
        );
    }

    function rejectTransferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAllowance) external {
        uint256 owner = _fundedOwner(ownerSeed);
        uint256 spender = spenderSeed % 4;
        uint256 allowance = bound(rawAllowance, 0, expectedBalances[owner] - 1);
        _approve(owner, spender, allowance);
        // Sufficient balance isolates the permission failure, including self-spending.
        _expectFailure(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[spender], allowance + 1)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actors[spender], allowance, allowance + 1
            )
        );
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 amount = bound(rawAmount, 0, expectedBalances[owner]);
        if (mode % 3 == 0) {
            _expectFailure(
                actors[owner],
                abi.encodeCall(token.approve, (address(0), rawAmount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        } else if (mode % 3 == 1) {
            _expectFailure(
                actors[owner],
                abi.encodeCall(token.transfer, (address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else {
            _approve(owner, spender, amount);
            _expectFailure(
                actors[spender],
                abi.encodeCall(token.transferFrom, (actors[owner], address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        }
    }

    function _fundedOwner(uint256 seed) private view returns (uint256) {
        for (uint256 i; i < 4; ++i) {
            uint256 owner = (seed % 4 + i) % 4;
            if (expectedBalances[owner] > 0) return owner;
        }
        revert("fixed supply must have a holder");
    }

    function _approve(uint256 owner, uint256 spender, uint256 amount) private {
        vm.prank(actors[owner]);
        assertTrue(token.approve(actors[spender], amount));
        expectedAllowances[owner][spender] = amount;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected failure reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract StrataIMDInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    StrataHandler private handler;
    StrataIMD private token;

    function setUp() public {
        handler = new StrataHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveAndSpend.selector;
        selectors[4] = handler.revokeAndAttemptSpend.selector;
        selectors[5] = handler.rejectTransferAboveBalance.selector;
        selectors[6] = handler.rejectTransferFromAboveBalance.selector;
        selectors[7] = handler.rejectTransferFromAboveAllowance.selector;
        selectors[8] = handler.rejectZeroAddress.selector;
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
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
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

    function test_rejectionsThenSpendingAndRevocationPreserveLedger() public {
        handler.transfer(0, 1, SUPPLY / 2);
        handler.approve(1, 2, type(uint256).max - 1, false);
        handler.transferFrom(1, 2, 3, 1);
        invariant_balancesAndAllowancesMatchLedgerAndSupplyIsFixed();

        handler.rejectTransferAboveBalance(3, 3, type(uint256).max);
        handler.rejectTransferFromAboveBalance(1, 2, 3, SUPPLY, false);
        handler.rejectTransferFromAboveBalance(1, 2, 3, type(uint256).max, true);
        handler.rejectTransferFromAboveAllowance(1, 2, 1);
        for (uint8 mode; mode < 3; ++mode) {
            handler.rejectZeroAddress(1, 2, 1, mode);
            invariant_balancesAndAllowancesMatchLedgerAndSupplyIsFixed();
        }

        handler.approveAndSpend(1, 2, 3, SUPPLY / 2 - 1, true);
        handler.revokeAndAttemptSpend(3, 2);
        handler.approveAndSpend(3, 2, 0, SUPPLY / 2, false);
        invariant_balancesAndAllowancesMatchLedgerAndSupplyIsFixed();
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
    }
}
