// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {StrataIMD} from "../src/StrataIMD.sol";

/// @dev Local factory fixture; does not broadcast or depend on chain configuration.
contract TokenFactoryFixture {
    address private immutable controller = msg.sender;

    function deploy(bytes32 salt) external returns (StrataIMD) {
        require(msg.sender == controller, "controller only");
        return new StrataIMD{salt: salt}();
    }

    function move(StrataIMD token, address to, uint256 amount) external returns (bool) {
        require(msg.sender == controller, "controller only");
        return token.transfer(to, amount);
    }
}

contract StrataIMDTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address private constant DEPLOYER = address(0xD0);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    StrataIMD private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new StrataIMD();
    }

    function test_metadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "StrataIMD");
        assertEq(token.symbol(), "STRATA");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), DEPLOYER, SUPPLY);
        vm.prank(DEPLOYER);
        new StrataIMD();
    }

    function test_create2FactoryReceivesSupplyAndLaunchTransfersAreExact() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("STRATA local deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(StrataIMD).creationCode))
                    )
                )
            )
        );
        StrataIMD launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarmShare = SUPPLY / 10;
        // The pool amount is a local test value, not a production launch parameter.
        uint256 poolShare = SUPPLY / 5;
        uint256 remainder = SUPPLY - swarmShare - poolShare;
        assertTrue(factory.move(launched, distributor, swarmShare));
        assertTrue(factory.move(launched, poolManager, poolShare));
        assertTrue(factory.move(launched, DEPLOYER, remainder));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.balanceOf(DEPLOYER), remainder);

        vm.prank(distributor);
        assertTrue(launched.transfer(ALICE, swarmShare));
        assertEq(launched.balanceOf(ALICE), swarmShare);
        assertEq(launched.balanceOf(distributor), 0);

        vm.prank(poolManager);
        assertTrue(launched.transfer(BOB, 10 ether));
        assertEq(launched.balanceOf(BOB), 10 ether);
        vm.prank(BOB);
        assertTrue(launched.transfer(poolManager, 10 ether));
        assertEq(launched.balanceOf(BOB), 0);
        assertEq(launched.balanceOf(poolManager), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 123 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 123 ether);
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        for (uint256 amount; amount < 2; ++amount) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(DEPLOYER);
            token.transfer(address(0), amount);
        }
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndCanReplaceOrRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(DEPLOYER, SPENDER, 20 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 20 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 20 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 5 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 5 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_approveDoesNotRequireBalance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
        assertEq(token.allowance(DEPLOYER, address(0)), 0);
    }

    function test_transferFromEmitsEventAndConsumesAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 20 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, 7 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 7 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 7 ether);
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 13 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 13 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 13 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromUnlimitedAllowanceDoesNotDecrease() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_zeroTransferFromWithoutAllowanceSucceeds() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromSelfStillConsumesAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, DEPLOYER, 10 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1 ether);
        assertEq(token.allowance(ALICE, SPENDER), 100 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromToZeroRollsBackAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 10 ether);
        assertEq(token.allowance(DEPLOYER, SPENDER), 10 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSenderReverts() public {
        // Spending even a zero allowance validates its owner before the transfer runs.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        string[24] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "initialize(address)",
            "setMinter(address)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "rebase(uint256)"
        ];
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            vm.prank(DEPLOYER);
            (bool deployerSucceeded,) = address(token).call(data);
            assertFalse(deployerSucceeded, signatures[i]);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            assertFalse(strangerSucceeded, signatures[i]);
        }
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_runtimeContainsNoProhibitedOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "prohibited opcode");
        }
    }

    function test_rejectsNativeCurrency() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool succeeded,) = address(token).call{value: 1 ether}("");
        assertFalse(succeeded);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_transfersConserveSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, amount)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 rawAllowance, uint256 rawSpend) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY);
        uint256 spend = bound(rawSpend, 0, allowance);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, spend));
        assertEq(token.allowance(DEPLOYER, SPENDER), allowance - spend);
        assertEq(token.balanceOf(ALICE), spend);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - spend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 rawAllowance, uint256 rawSpend) public {
        uint256 allowance = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 spend = bound(rawSpend, allowance + 1, SUPPLY);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, spend)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, spend);
        assertEq(token.allowance(DEPLOYER, SPENDER), allowance);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }
}
