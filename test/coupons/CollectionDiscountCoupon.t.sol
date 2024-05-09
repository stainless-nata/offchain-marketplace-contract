// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CollectionDiscountCoupon} from "../../src/coupons/CollectionDiscountCoupon.sol";
import {Types} from "../../src/common/Types.sol";
import {MockCollection} from "../../src/mocks/MockCollection.sol";

contract CollectionDiscountCouponHarness is CollectionDiscountCoupon {}

contract CollectionDiscountCouponTests is Test {
    address signer;
    CollectionDiscountCouponHarness collectionDiscountCoupon;
    MockCollection mockCollection;

    function setUp() public {
        signer = address(1);
        collectionDiscountCoupon = new CollectionDiscountCouponHarness();
        mockCollection = new MockCollection();
    }
}

contract ApplyCollectionDiscountCouponTests is CollectionDiscountCouponTests {
    error InvalidProof(address _collectionAddress);
    error SignerIsNotTheCreator(address _signer, address _creator);
    error TradesWithOneSentCollectionItemAllowed();

    function test_RevertsIfCollectionDiscountCouponDataIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = bytes("");
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCollectionDiscountCouponCallerDataIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = bytes("");

        Types.Trade memory trade;

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasZeroSentAssets() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasTwoSentAssets() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](2);

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSentAssetDoesNotHaveTheCreatorFunction() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](1);

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSignerIsNotTheCreatorOfTheCollection() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        vm.expectRevert(abi.encodeWithSelector(SignerIsNotTheCreator.selector, signer, address(0)));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proof = new bytes32[](3);
        collectionDiscountCouponCallerData.proof[0] = 0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22;
        collectionDiscountCouponCallerData.proof[1] = 0x91f8b8d2c336dbdb2484b34885b0070baf79ebd29c182c675de7a0f92adc273a;
        collectionDiscountCouponCallerData.proof[2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, address(mockCollection)));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid_MerkleTreeWithOneValue() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0xaef723aaf2a9471d0444688035cd22ee9e9408f4d3390ce0a2a80b76aeab390a;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, address(mockCollection)));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;
        collectionDiscountCouponData.rate = 500_000;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proof = new bytes32[](3);
        collectionDiscountCouponCallerData.proof[0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proof[1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proof[2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);
        trade.received = new Types.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection.transferCreatorship(signer);

        Types.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1 ether);
        assertEq(updatedTrade.received[2].value, 1.5 ether);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_MerkleTreeWithOneValue() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;
        collectionDiscountCouponData.rate = 500_000;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        Types.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);
        trade.received = new Types.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection.transferCreatorship(signer);

        Types.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1 ether);
        assertEq(updatedTrade.received[2].value, 1.5 ether);
    }
}
