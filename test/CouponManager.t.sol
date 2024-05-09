// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CouponManager} from "../src/CouponManager.sol";
import {Types} from "../src/common/Types.sol";
import {ICoupon} from "../src/interfaces/ICoupon.sol";
import {MockCoupon} from "../src/mocks/MockCoupon.sol";

contract CouponsHarness is CouponManager {
    constructor(address _marketplace, address _owner, address[] memory _allowedCoupons)
        CouponManager(_marketplace, _owner, _allowedCoupons)
    {}

    function eip712CouponHash(Coupon memory _coupon) external view returns (bytes32) {
        return _hashTypedDataV4(_hashCoupon(_coupon));
    }
}

abstract contract CouponsTests is Test {
    address marketplace;
    address owner;
    address allowedCoupon;
    address other;
    VmSafe.Wallet signer;
    CouponsHarness coupons;
    ICoupon testCoupon;

    error OwnableUnauthorizedAccount(address account);
    error InvalidSignature();

    function setUp() public {
        marketplace = address(1);
        owner = address(2);
        testCoupon = new MockCoupon();
        allowedCoupon = address(testCoupon);
        other = address(4);
        signer = vm.createWallet("signer");

        address[] memory allowedCoupons = new address[](1);
        allowedCoupons[0] = allowedCoupon;

        coupons = new CouponsHarness(marketplace, owner, allowedCoupons);
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
        assertEq(coupons.allowedCoupons(allowedCoupon), true);
        assertEq(coupons.allowedCoupons(address(4)), false);
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
    event AllowedCouponsUpdated(address indexed _caller, address indexed _coupon, bool _value);

    error LengthMissmatch();

    function test_RevertsIfCallerIsNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        coupons.updateAllowedCoupons(new address[](0), new bool[](0));
    }

    function test_RevertsIfLengthsMismatch() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        coupons.updateAllowedCoupons(new address[](1), new bool[](0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        coupons.updateAllowedCoupons(new address[](0), new bool[](1));
    }

    function test_UpdatesAllowedCouponImplementations() public {
        assertEq(coupons.allowedCoupons(allowedCoupon), true);
        assertEq(coupons.allowedCoupons(other), false);

        address[] memory couponImplementations = new address[](2);
        couponImplementations[0] = allowedCoupon;
        couponImplementations[1] = other;

        bool[] memory values = new bool[](2);
        values[0] = false;
        values[1] = true;

        vm.prank(owner);
        vm.expectEmit(address(coupons));
        emit AllowedCouponsUpdated(owner, allowedCoupon, false);
        vm.expectEmit(address(coupons));
        emit AllowedCouponsUpdated(owner, other, true);
        coupons.updateAllowedCoupons(couponImplementations, values);

        assertEq(coupons.allowedCoupons(allowedCoupon), false);
        assertEq(coupons.allowedCoupons(other), true);
    }
}

contract ApplyCouponTests is CouponsTests {
    event CouponApplied(address indexed _caller, bytes32 indexed _tradeSignature, bytes32 indexed _couponSignature);

    error UnauthorizedCaller(address _caller);
    error CouponNotAllowed(address _coupon);
    error Expired();

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
        coupon.couponAddress = other;

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(CouponNotAllowed.selector, other));
        coupons.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCheckFails() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;
        coupon.couponAddress = allowedCoupon;

        vm.prank(marketplace);
        vm.expectRevert(Expired.selector);
        coupons.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSignatureIsInvalid() public {
        Types.Trade memory trade;
        trade.signer = other;
        Types.Coupon memory coupon;
        coupon.couponAddress = allowedCoupon;
        coupon.checks.expiration = block.timestamp;
        coupon.signature = signCoupon(coupon);

        vm.prank(marketplace);
        vm.expectRevert(InvalidSignature.selector);
        coupons.applyCoupon(trade, coupon);
    }

    function test_AppliesTheCouponToTheTrade() public {
        Types.Trade memory trade;
        trade.signer = signer.addr;
        Types.Coupon memory coupon;
        coupon.couponAddress = allowedCoupon;
        coupon.checks.expiration = block.timestamp;
        coupon.signature = signCoupon(coupon);

        assertEq(coupons.signatureUses(keccak256(coupon.signature)), 0);

        vm.prank(marketplace);
        vm.expectEmit(address(coupons));
        emit CouponApplied(marketplace, keccak256(trade.signature), keccak256(coupon.signature));
        Types.Trade memory updatedTrade = coupons.applyCoupon(trade, coupon);
        // Mock coupon implementation updates the signer of the trade to address(1337).
        assertEq(updatedTrade.signer, address(1337));
        assertEq(coupons.signatureUses(keccak256(coupon.signature)), 1);
    }
}

contract CancelSignatureTests is CouponsTests {
    event SignatureCancelled(address indexed _caller, bytes32 indexed _signature);
    
    function test_CanSendEmptyListOfCoupons() public {
        vm.prank(other);
        coupons.cancelSignature(new Types.Coupon[](0));
    }

    function test_RevertsIfInvalidSigner() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](1);
        couponList[0].signature = signCoupon(couponList[0]); 

        vm.prank(other);
        vm.expectRevert(InvalidSignature.selector);
        coupons.cancelSignature(couponList);
    }

    function test_SignatureCancelled() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](1);
        couponList[0].signature = signCoupon(couponList[0]); 

        bytes32 hashedSignature = keccak256(couponList[0].signature);

        assertEq(coupons.cancelledSignatures(hashedSignature), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(coupons));
        emit SignatureCancelled(signer.addr, hashedSignature);
        coupons.cancelSignature(couponList);

        assertEq(coupons.cancelledSignatures(hashedSignature), true);
    }

    function test_MultipleSignaturesCancelled() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](2);
        couponList[0].checks.expiration = block.timestamp;
        couponList[0].signature = signCoupon(couponList[0]); 
        couponList[1].checks.expiration = block.timestamp + 1;
        couponList[1].signature = signCoupon(couponList[1]);

        bytes32 hashedSignature1 = keccak256(couponList[0].signature);
        bytes32 hashedSignature2 = keccak256(couponList[1].signature);

        assertNotEq(hashedSignature1, hashedSignature2);

        assertEq(coupons.cancelledSignatures(hashedSignature1), false);
        assertEq(coupons.cancelledSignatures(hashedSignature2), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(coupons));
        emit SignatureCancelled(signer.addr, hashedSignature1);
        vm.expectEmit(address(coupons));
        emit SignatureCancelled(signer.addr, hashedSignature2);
        coupons.cancelSignature(couponList);

        assertEq(coupons.cancelledSignatures(hashedSignature1), true);
        assertEq(coupons.cancelledSignatures(hashedSignature2), true);
    }

    function test_CanCancelTheSameSignatureMultipleTimes() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](2);
        couponList[0].signature = signCoupon(couponList[0]); 
        couponList[1].signature = signCoupon(couponList[1]);

        bytes32 hashedSignature1 = keccak256(couponList[0].signature);
        bytes32 hashedSignature2 = keccak256(couponList[1].signature);

        assertEq(hashedSignature1, hashedSignature2);

        assertEq(coupons.cancelledSignatures(hashedSignature1), false);
        assertEq(coupons.cancelledSignatures(hashedSignature2), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(coupons));
        emit SignatureCancelled(signer.addr, hashedSignature1);
        vm.expectEmit(address(coupons));
        emit SignatureCancelled(signer.addr, hashedSignature2);
        coupons.cancelSignature(couponList);

        assertEq(coupons.cancelledSignatures(hashedSignature1), true);
        assertEq(coupons.cancelledSignatures(hashedSignature2), true);
    }
}
