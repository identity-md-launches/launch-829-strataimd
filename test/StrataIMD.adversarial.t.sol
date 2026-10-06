// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {StrataIMD} from "../src/StrataIMD.sol";

contract StrataSpenderFixture {
    function spend(StrataIMD token, address owner, address recipient, uint256 amount) external returns (bool) {
        return token.transferFrom(owner, recipient, amount);
    }
}

/// @dev Complements the deployment/basic ERC-20 suite with authorization and recovery sequences.
/// forge-config: default.fuzz.runs = 1000
contract StrataIMDAdversarialTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant DEPLOYER = address(0xD0);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);
    StrataIMD private token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new StrataIMD();
    }

    function test_oneWeiRoundTripHasNoDustOrFee() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferAndSelfTransferRejectInsufficientBalance() public {
        address[2] memory recipients = [ALICE, DEPLOYER];
        for (uint256 i; i < recipients.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max
                )
            );
            vm.prank(DEPLOYER);
            token.transfer(recipients[i], type(uint256).max);
        }
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceDoesNotBypassBalanceChecks() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, type(uint256).max);
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_largestFiniteAllowanceIsNotTreatedAsUnlimited() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, SUPPLY - 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_refundingOwnerDoesNotRestoreSpentAllowance() public {
        _approve(DEPLOYER, SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        _expectAllowanceFailure(DEPLOYER, SPENDER, ALICE, 0, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_unlimitedApprovalCanBeRevokedAfterSpendingAndRefill() public {
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        _approve(DEPLOYER, SPENDER, 0);
        _expectAllowanceFailure(DEPLOYER, SPENDER, ALICE, 0, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_allowancesAreScopedToBothOwnerAndSpender() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 10));
        _approve(DEPLOYER, SPENDER, 20);
        _approve(ALICE, BOB, 10);
        _expectAllowanceFailure(ALICE, SPENDER, SPENDER, 0, 1);
        _expectAllowanceFailure(DEPLOYER, BOB, BOB, 0, 1);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 7));
        assertEq(token.allowance(DEPLOYER, SPENDER), 13);
        assertEq(token.allowance(ALICE, BOB), 10);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.allowance(DEPLOYER, BOB), 0);
        assertEq(token.balanceOf(ALICE), 10);
        assertEq(token.balanceOf(BOB), 7);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 17);
    }

    function test_ownerNeedsAllowanceForTransferFromButCanTransferDirectly() public {
        _expectAllowanceFailure(DEPLOYER, DEPLOYER, ALICE, 0, 1);
        _approve(DEPLOYER, DEPLOYER, 1);
        vm.prank(DEPLOYER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, DEPLOYER), 0);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 2);
    }

    function test_contractSpenderCannotBorrowTransactionOriginAllowance() public {
        StrataSpenderFixture forwarder = new StrataSpenderFixture();
        _approve(DEPLOYER, ALICE, 10);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(forwarder), 0, 1)
        );
        vm.prank(ALICE, ALICE);
        forwarder.spend(token, DEPLOYER, BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(DEPLOYER, ALICE), 10);

        _approve(DEPLOYER, address(forwarder), 1);
        vm.prank(ALICE, ALICE);
        assertTrue(forwarder.spend(token, DEPLOYER, BOB, 1));
        assertEq(token.allowance(DEPLOYER, address(forwarder)), 0);
        assertEq(token.allowance(DEPLOYER, ALICE), 10);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
    }

    function test_zeroAmountDoesNotMakeInvalidAddressesValid() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, address(0), 0);
        assertEq(token.allowance(ALICE, address(0)), 0);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedSpendCanBeRetriedAfterFunding(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, balance + 1, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, balance));
        _approve(ALICE, SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount - balance));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingUnlimitedApprovalEnforcesFiniteLimit(uint256 rawLimit) public {
        uint256 limit = bound(rawLimit, 0, SUPPLY - 1);
        _approve(DEPLOYER, SPENDER, type(uint256).max);
        _approve(DEPLOYER, SPENDER, limit);
        _expectAllowanceFailure(DEPLOYER, SPENDER, ALICE, limit, limit + 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), limit);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, limit));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), limit);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - limit);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splittingSpendMatchesSingleSpend(uint256 rawFirst, uint256 rawSecond, uint256 rawAllowance)
        public
    {
        uint256 first = bound(rawFirst, 0, SUPPLY);
        uint256 second = bound(rawSecond, 0, SUPPLY - first);
        uint256 allowance = bound(rawAllowance, first + second, type(uint256).max);
        vm.prank(DEPLOYER);
        StrataIMD single = new StrataIMD();
        _approve(DEPLOYER, SPENDER, allowance);
        vm.prank(DEPLOYER);
        assertTrue(single.approve(SPENDER, allowance));

        vm.startPrank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, first));
        assertTrue(token.transferFrom(DEPLOYER, ALICE, second));
        assertTrue(single.transferFrom(DEPLOYER, ALICE, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), first + second);
        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE));
        assertEq(token.balanceOf(DEPLOYER), single.balanceOf(DEPLOYER));
        assertEq(token.allowance(DEPLOYER, SPENDER), single.allowance(DEPLOYER, SPENDER));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    function _expectAllowanceFailure(
        address owner,
        address spender,
        address recipient,
        uint256 allowance,
        uint256 amount
    ) private {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }
}
