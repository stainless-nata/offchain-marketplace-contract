// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {Coupons} from "../src/Coupons.sol";

contract CouponsHarness is Coupons {
    constructor(address _marketplace, address _owner, address[] memory _allowedCouponImplementations)
        Coupons(_marketplace, _owner, _allowedCouponImplementations)
    {}
}

abstract contract CouponsTests is Test {
    address marketplace = address(1);
    address owner = address(2);
    address allowedCouponImplementation = address(3);
    address other = address(4);

    CouponsHarness coupons;

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        address[] memory allowedCouponImplementations = new address[](1);
        allowedCouponImplementations[0] = allowedCouponImplementation;

        coupons = new CouponsHarness(marketplace, owner, allowedCouponImplementations);
    }
}

contract SetupTests is CouponsTests {
    function test_SetUpState() public view {
        assertEq(coupons.marketplace(), marketplace);
        assertEq(coupons.owner(), owner);
        assertEq(coupons.allowedCouponImplementations(allowedCouponImplementation), true);
        assertEq(coupons.allowedCouponImplementations(address(4)), false);
    }
}

contract UpdateMarketplaceTests is CouponsTests {
    event MarketplaceUpdated(address indexed _caller, address indexed _marketplace);

    function test_RevertsIfCallerIsNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        coupons.updateMarketplace(marketplace);
    }

    function test_UpdatesTheMarketplace() public {
        vm.prank(owner);
        vm.expectEmit(address(coupons));
        emit MarketplaceUpdated(owner, other);
        coupons.updateMarketplace(other);
        assertEq(coupons.marketplace(), other);
    }
}

contract UpdateAllowedCouponImplementationsTests is CouponsTests {
    event AllowedCouponImplementationsUpdated(address indexed _caller, address indexed _couponImplementation, bool _value);

    error LengthMissmatch();

    function test_RevertsIfCallerIsNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        coupons.updateAllowedCouponImplementations(new address[](0), new bool[](0));
    }

    function test_RevertsIfLengthsMismatch() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        coupons.updateAllowedCouponImplementations(new address[](1), new bool[](0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        coupons.updateAllowedCouponImplementations(new address[](0), new bool[](1));
    }

    function test_UpdatesAllowedCouponImplementations() public {
        assertEq(coupons.allowedCouponImplementations(allowedCouponImplementation), true);
        assertEq(coupons.allowedCouponImplementations(other), false);

        address[] memory couponImplementations = new address[](2);
        couponImplementations[0] = allowedCouponImplementation;
        couponImplementations[1] = other;

        bool[] memory values = new bool[](2);
        values[0] = false;
        values[1] = true;

        vm.prank(owner);
        vm.expectEmit(address(coupons));
        emit AllowedCouponImplementationsUpdated(owner, allowedCouponImplementation, false);
        vm.expectEmit(address(coupons));
        emit AllowedCouponImplementationsUpdated(owner, other, true);
        coupons.updateAllowedCouponImplementations(couponImplementations, values);

        assertEq(coupons.allowedCouponImplementations(allowedCouponImplementation), false);
        assertEq(coupons.allowedCouponImplementations(other), true);
    }
}
