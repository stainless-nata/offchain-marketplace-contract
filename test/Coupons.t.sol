// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {Coupons} from "../src/Coupons.sol";
import {Types} from "../src/common/Types.sol";

contract CouponsHarness is Coupons {
    constructor(address _marketplace, address _owner, address[] memory _allowedCouponImplementations)
        Coupons(_marketplace, _owner, _allowedCouponImplementations)
    {}

    function eip712CouponHash(Coupon memory _coupon) external view returns (bytes32) {
        return _hashTypedDataV4(_hashCoupon(_coupon));
    }
}

abstract contract CouponsTests is Test {
    address marketplace;
    address owner;
    address allowedCouponImplementation;
    address other;
    VmSafe.Wallet signer;
    CouponsHarness coupons;

    error OwnableUnauthorizedAccount(address account);

    function setUp() public {
        marketplace = address(1);
        owner = address(2);
        allowedCouponImplementation = address(3);
        other = address(4);
        signer = vm.createWallet("signer");

        address[] memory allowedCouponImplementations = new address[](1);
        allowedCouponImplementations[0] = allowedCouponImplementation;

        coupons = new CouponsHarness(marketplace, owner, allowedCouponImplementations);
    }

    function signCoupon(Types.Coupon memory _coupon) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, coupons.eip712CouponHash(_coupon));
        return abi.encodePacked(r, s, v);
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

contract ApplyCouponTests is CouponsTests {
    error UnauthorizedCaller(address _caller);
    error CouponImplementationNotAllowed(address _couponImplementation);
    error Expired();
    error InvalidSignature();

    function test_RevertsIfCallerIsNotTheMarketplace() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, other));
        coupons.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCouponImplementationIsNotAllowed() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;
        coupon.couponImplementation = other;

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(CouponImplementationNotAllowed.selector, other));
        coupons.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCheckFails() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;
        coupon.couponImplementation = allowedCouponImplementation;

        vm.prank(marketplace);
        vm.expectRevert(Expired.selector);
        coupons.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSignatureIsInvalid() public {
        Types.Trade memory trade;
        trade.signer = other;
        Types.Coupon memory coupon;
        coupon.couponImplementation = allowedCouponImplementation;
        coupon.checks.expiration = block.timestamp;
        coupon.signature = signCoupon(coupon);

        vm.prank(marketplace);
        vm.expectRevert(InvalidSignature.selector);
        coupons.applyCoupon(trade, coupon);
    }
}
