// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CouponManager} from "../src/CouponManager.sol";
import {Types} from "../src/common/Types.sol";
import {ICoupon} from "../src/interfaces/ICoupon.sol";
import {MockCoupon} from "../src/mocks/MockCoupon.sol";

contract CouponManagerHarness is CouponManager {
    constructor(address _marketplace, address _owner, address[] memory _allowedCoupons) CouponManager(_marketplace, _owner, _allowedCoupons) {}

    function eip712CouponHash(Coupon memory _coupon) external view returns (bytes32) {
        return _hashTypedDataV4(_hashCoupon(_coupon));
    }

    function eip712MetaTransactionHash(MetaTransaction memory _metaTx) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionData)")),
                    _metaTx.nonce,
                    _metaTx.from,
                    keccak256(_metaTx.functionData)
                )
            )
        );
    }
}

abstract contract CouponsTests is Test {
    address marketplace;
    address owner;
    address allowedCoupon;
    address other;
    VmSafe.Wallet signer;
    VmSafe.Wallet metaTxSigner;
    CouponManagerHarness couponManager;
    ICoupon mockCoupon;

    error OwnableUnauthorizedAccount(address account);
    error InvalidSignature();

    function setUp() public {
        marketplace = address(1);
        owner = address(2);
        mockCoupon = new MockCoupon();
        allowedCoupon = address(mockCoupon);
        other = address(4);
        signer = vm.createWallet("signer");
        metaTxSigner = vm.createWallet("metaTxSigner");

        address[] memory allowedCoupons = new address[](1);
        allowedCoupons[0] = allowedCoupon;

        couponManager = new CouponManagerHarness(marketplace, owner, allowedCoupons);
    }

    function signCoupon(Types.Coupon memory _coupon) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, couponManager.eip712CouponHash(_coupon));
        return abi.encodePacked(r, s, v);
    }

    function signMetaTx(CouponManager.MetaTransaction memory _metaTx) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(metaTxSigner.privateKey, couponManager.eip712MetaTransactionHash(_metaTx));
        return abi.encodePacked(r, s, v);
    }
}

contract SetupTests is CouponsTests {
    function test_SetUpState() public view {
        assertEq(couponManager.marketplace(), marketplace);
        assertEq(couponManager.owner(), owner);
        assertEq(couponManager.allowedCoupons(allowedCoupon), true);
        assertEq(couponManager.allowedCoupons(address(4)), false);
    }
}

contract UpdateMarketplaceTests is CouponsTests {
    event MarketplaceUpdated(address indexed _caller, address indexed _marketplace);

    function test_RevertsIfCallerIsNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        couponManager.updateMarketplace(marketplace);
    }

    function test_RevertsIfCallerIsNotOwner_MetaTx() public {
        CouponManager.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(couponManager.updateMarketplace.selector, other);
        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, metaTxSigner.addr));
        couponManager.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_UpdatesTheMarketplace() public {
        vm.prank(owner);
        vm.expectEmit(address(couponManager));
        emit MarketplaceUpdated(owner, other);
        couponManager.updateMarketplace(other);
        assertEq(couponManager.marketplace(), other);
    }

    function test_UpdatesTheMarketplace_MetaTx() public {
        vm.prank(owner);
        couponManager.transferOwnership(metaTxSigner.addr);

        CouponManager.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(couponManager.updateMarketplace.selector, other);
        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectEmit(address(couponManager));
        emit MarketplaceUpdated(metaTxSigner.addr, other);
        couponManager.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
        assertEq(couponManager.marketplace(), other);
    }
}

contract UpdateAllowedCouponsTests is CouponsTests {
    event AllowedCouponsUpdated(address indexed _caller, address indexed _coupon, bool _value);

    error LengthMissmatch();

    function test_RevertsIfCallerIsNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        couponManager.updateAllowedCoupons(new address[](0), new bool[](0));
    }

    function test_RevertsIfLengthsMismatch() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        couponManager.updateAllowedCoupons(new address[](1), new bool[](0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(LengthMissmatch.selector));
        couponManager.updateAllowedCoupons(new address[](0), new bool[](1));
    }

    function test_UpdatesAllowedCoupons() public {
        assertEq(couponManager.allowedCoupons(allowedCoupon), true);
        assertEq(couponManager.allowedCoupons(other), false);

        address[] memory allowedCoupons = new address[](2);
        allowedCoupons[0] = allowedCoupon;
        allowedCoupons[1] = other;

        bool[] memory values = new bool[](2);
        values[0] = false;
        values[1] = true;

        vm.prank(owner);
        vm.expectEmit(address(couponManager));
        emit AllowedCouponsUpdated(owner, allowedCoupon, false);
        vm.expectEmit(address(couponManager));
        emit AllowedCouponsUpdated(owner, other, true);
        couponManager.updateAllowedCoupons(allowedCoupons, values);

        assertEq(couponManager.allowedCoupons(allowedCoupon), false);
        assertEq(couponManager.allowedCoupons(other), true);
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
        couponManager.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCouponImplementationIsNotAllowed() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;
        coupon.couponAddress = other;

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSelector(CouponNotAllowed.selector, other));
        couponManager.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCheckFails() public {
        Types.Trade memory trade;
        Types.Coupon memory coupon;
        coupon.couponAddress = allowedCoupon;

        vm.prank(marketplace);
        vm.expectRevert(Expired.selector);
        couponManager.applyCoupon(trade, coupon);
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
        couponManager.applyCoupon(trade, coupon);
    }

    function test_AppliesTheCouponToTheTrade() public {
        Types.Trade memory trade;
        trade.signer = signer.addr;
        Types.Coupon memory coupon;
        coupon.couponAddress = allowedCoupon;
        coupon.checks.expiration = block.timestamp;
        coupon.signature = signCoupon(coupon);

        assertEq(couponManager.signatureUses(keccak256(coupon.signature)), 0);

        vm.prank(marketplace);
        vm.expectEmit(address(couponManager));
        emit CouponApplied(marketplace, keccak256(trade.signature), keccak256(coupon.signature));
        Types.Trade memory updatedTrade = couponManager.applyCoupon(trade, coupon);
        // Mock coupon implementation updates the signer of the trade to address(1337).
        assertEq(updatedTrade.signer, address(1337));
        assertEq(couponManager.signatureUses(keccak256(coupon.signature)), 1);
    }
}

contract CancelSignatureTests is CouponsTests {
    event SignatureCancelled(address indexed _caller, bytes32 indexed _signature);

    function test_CanSendEmptyListOfCoupons() public {
        vm.prank(other);
        couponManager.cancelSignature(new Types.Coupon[](0));
    }

    function test_RevertsIfInvalidSigner() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](1);
        couponList[0].signature = signCoupon(couponList[0]);

        vm.prank(other);
        vm.expectRevert(InvalidSignature.selector);
        couponManager.cancelSignature(couponList);
    }

    function test_SignatureCancelled() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](1);
        couponList[0].signature = signCoupon(couponList[0]);

        bytes32 hashedSignature = keccak256(couponList[0].signature);

        assertEq(couponManager.cancelledSignatures(hashedSignature), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(couponManager));
        emit SignatureCancelled(signer.addr, hashedSignature);
        couponManager.cancelSignature(couponList);

        assertEq(couponManager.cancelledSignatures(hashedSignature), true);
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

        assertEq(couponManager.cancelledSignatures(hashedSignature1), false);
        assertEq(couponManager.cancelledSignatures(hashedSignature2), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(couponManager));
        emit SignatureCancelled(signer.addr, hashedSignature1);
        vm.expectEmit(address(couponManager));
        emit SignatureCancelled(signer.addr, hashedSignature2);
        couponManager.cancelSignature(couponList);

        assertEq(couponManager.cancelledSignatures(hashedSignature1), true);
        assertEq(couponManager.cancelledSignatures(hashedSignature2), true);
    }

    function test_CanCancelTheSameSignatureMultipleTimes() public {
        Types.Coupon[] memory couponList = new Types.Coupon[](2);
        couponList[0].signature = signCoupon(couponList[0]);
        couponList[1].signature = signCoupon(couponList[1]);

        bytes32 hashedSignature1 = keccak256(couponList[0].signature);
        bytes32 hashedSignature2 = keccak256(couponList[1].signature);

        assertEq(hashedSignature1, hashedSignature2);

        assertEq(couponManager.cancelledSignatures(hashedSignature1), false);
        assertEq(couponManager.cancelledSignatures(hashedSignature2), false);

        vm.prank(signer.addr);
        vm.expectEmit(address(couponManager));
        emit SignatureCancelled(signer.addr, hashedSignature1);
        vm.expectEmit(address(couponManager));
        emit SignatureCancelled(signer.addr, hashedSignature2);
        couponManager.cancelSignature(couponList);

        assertEq(couponManager.cancelledSignatures(hashedSignature1), true);
        assertEq(couponManager.cancelledSignatures(hashedSignature2), true);
    }
}
