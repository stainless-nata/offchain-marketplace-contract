// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract MarketplaceHarness is Marketplace {
    constructor(address _owner) Marketplace(_owner) {}

    function _transferAsset(Asset memory _asset, address _from) internal override {
        // The contents of this function are to be tested on the corresponding Ethereum or Polygon marketplace contracts.
    }
}

contract MarketplaceTest is Test {
    address owner;
    address other;

    MarketplaceHarness marketplace;

    function setUp() public {
        owner = vm.addr(0x1);
        other = vm.addr(0x2);
        marketplace = new MarketplaceHarness(owner);
    }

    function test_SetUpState() public view {
        assertEq(marketplace.owner(), owner);
    }

    // Ownable

    event OwnershipTransferred(address indexed, address indexed);

    error OwnableUnauthorizedAccount(address);
    error OwnableInvalidOwner(address);

    // transferOwnership

    function test_transferOwnership_OwnershipTransferred() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit OwnershipTransferred(owner, other);
        marketplace.transferOwnership(other);
        assertEq(marketplace.owner(), other);
    }

    function test_transferOwnership_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.transferOwnership(other);
    }

    function test_transferOwnership_RevertsIfAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(OwnableInvalidOwner.selector, address(0)));
        marketplace.transferOwnership(address(0));
    }

    // renounceOwnership

    function test_renounceOwnership_OwnershipTransferred() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit OwnershipTransferred(owner, address(0));
        marketplace.renounceOwnership();
    }

    function test_renounceOwnership_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.renounceOwnership();
    }

    // Pausable
    event Paused(address);
    event Unpaused(address);

    error EnforcedPause();
    error ExpectedPause();

    // pause

    function test_pause_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.pause();
    }

    function test_pause_RevertIfPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        vm.expectRevert(EnforcedPause.selector);
        marketplace.pause();
    }

    function test_pause_Paused() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit Paused(owner);
        marketplace.pause();
        assertEq(marketplace.paused(), true);
    }

    // unpause

    function test_unpause_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.unpause();
    }

    function test_unpause_RevertIfNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(ExpectedPause.selector);
        marketplace.unpause();
    }

    function test_unpause_Unpaused() public {
        vm.prank(owner);
        marketplace.pause();
        assertEq(marketplace.paused(), true);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit Unpaused(owner);
        marketplace.unpause();
        assertEq(marketplace.paused(), false);
    }

    // Marketplace

    event ContractSignatureIndexIncreased(uint256, address);
    event SignerSignatureIndexIncreased(uint256, address);

    // increaseContractSignatureIndex

    function test_increaseContractSignatureIndex_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.increaseContractSignatureIndex();
    }

    function test_increaseContractSignatureIndex_Increased() public {
        assertEq(marketplace.contractSignatureIndex(), 0);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit ContractSignatureIndexIncreased(1, owner);
        marketplace.increaseContractSignatureIndex();
        assertEq(marketplace.contractSignatureIndex(), 1);
    }

    // increaseSignerSignatureIndex

    function test_increaseSignerSignatureIndex_Increased() public {
        assertEq(marketplace.signerSignatureIndex(owner), 0);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit SignerSignatureIndexIncreased(1, owner);
        marketplace.increaseSignerSignatureIndex();
        assertEq(marketplace.signerSignatureIndex(owner), 1);

        assertEq(marketplace.signerSignatureIndex(other), 0);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit SignerSignatureIndexIncreased(1, other);
        marketplace.increaseSignerSignatureIndex();
        assertEq(marketplace.signerSignatureIndex(other), 1);
    }
}
