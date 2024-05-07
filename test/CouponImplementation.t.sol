// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {ICouponImplementation} from "../src/interfaces/ICouponImplementation.sol";
import {CouponImplementation} from "../src/CouponImplementation.sol";
import {Types} from "../src/common/Types.sol";
import {MockCollection} from "../src/mocks/MockCollection.sol";

contract CouponImplementationHarness is CouponImplementation {}

contract CouponImplementationTests is Test {
    address signer;
    CouponImplementationHarness couponImplementation;
    MockCollection mockCollection;

    function setUp() public {
        signer = address(1);
        couponImplementation = new CouponImplementationHarness();
        mockCollection = new MockCollection();
    }
}

contract ApplyCouponTests is CouponImplementationTests {
    error InvalidDiscountType(uint256 _discountType);

    function test_RevertsIfCouponDataIsInvalid() public {
        Types.Coupon memory coupon;
        coupon.data = bytes("");

        Types.Trade memory trade;

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfDiscountTypeIsInvalid() public {
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = 2;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;

        vm.expectRevert(abi.encodeWithSelector(InvalidDiscountType.selector, 2));
        couponImplementation.applyCoupon(trade, coupon);
    }
}

contract ApplySimpleCollectionDiscountCouponTests is CouponImplementationTests {
    error TradesWithOneSentCollectionItemAllowed();
    error SignerIsNotTheCreator(address _signer, address _creator);
    error CouponCannotBeApplied();

    function test_RevertsIfSimpleCollectionDiscountCouponDataIsInvalid() public {
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = bytes("");

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasZeroSentAssets() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasTwoSentAssets() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](2);

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSentAssetDoesNotHaveTheCreatorFunction() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](1);

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSignerIsNotTheCreatorOfTheCollection() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        vm.expectRevert(abi.encodeWithSelector(SignerIsNotTheCreator.selector, signer, address(0)));
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTheCollectionListInDataIsEmpty() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(CouponCannotBeApplied.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTheCollectionIsNotInTheCollectionListInData() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        simpleCollectionDiscountCouponData.collections = new address[](3);
        simpleCollectionDiscountCouponData.collections[0] = address(1);
        simpleCollectionDiscountCouponData.collections[1] = address(2);
        simpleCollectionDiscountCouponData.collections[2] = address(3);
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(CouponCannotBeApplied.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        simpleCollectionDiscountCouponData.collections = new address[](3);
        simpleCollectionDiscountCouponData.collections[0] = address(1);
        simpleCollectionDiscountCouponData.collections[1] = address(2);
        simpleCollectionDiscountCouponData.collections[2] = address(mockCollection);
        simpleCollectionDiscountCouponData.rate = 500_000;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(simpleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);
        trade.received = new Types.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection.transferCreatorship(signer);

        Types.Trade memory updatedTrade = couponImplementation.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1 ether);
        assertEq(updatedTrade.received[2].value, 1.5 ether);
    }
}
