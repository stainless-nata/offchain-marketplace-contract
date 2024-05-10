// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CollectionDiscountCoupon} from "src/coupons/CollectionDiscountCoupon.sol";
import {MockCollection} from "src/mocks/MockCollection.sol";

contract CollectionDiscountCouponHarness is CollectionDiscountCoupon {}

contract CollectionDiscountCouponTests is Test {
    address signer;
    CollectionDiscountCouponHarness collectionDiscountCoupon;
    MockCollection mockCollection1;
    MockCollection mockCollection2;

    function setUp() public {
        signer = address(1);
        collectionDiscountCoupon = new CollectionDiscountCouponHarness();
        mockCollection1 = new MockCollection();
        mockCollection2 = new MockCollection();
        console.log(address(mockCollection2));
    }
}

contract ApplyCollectionDiscountCouponTests is CollectionDiscountCouponTests {
    error TradeSentAndProofsLengthMismatch();
    error InvalidProof(uint256 _index);
    error SignerIsNotTheCreator(uint256 _index);
    error InvalidDiscountType();

    function test_RevertsIfCollectionDiscountCouponDataIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = bytes("");
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfCollectionDiscountCouponCallerDataIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = bytes("");

        CollectionDiscountCouponHarness.Trade memory trade;

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSentAndProofsLengthMismatch() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);

        vm.expectRevert(TradeSentAndProofsLengthMismatch.selector);
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSentAssetDoesNotHaveTheCreatorFunction() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);

        vm.expectRevert();
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSignerIsNotTheCreatorOfTheCollection() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);

        vm.expectRevert(abi.encodeWithSelector(SignerIsNotTheCreator.selector, 0));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSignerIsNotTheCreatorOfTheCollection_OfTheSecondCollection() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](2);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](2);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.sent[1].contractAddress = address(mockCollection2);

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(SignerIsNotTheCreator.selector, 1));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22;
        collectionDiscountCouponCallerData.proofs[0][1] = 0x91f8b8d2c336dbdb2484b34885b0070baf79ebd29c182c675de7a0f92adc273a;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, 0));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid_MerkleTreeWithOneValue() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0xaef723aaf2a9471d0444688035cd22ee9e9408f4d3390ce0a2a80b76aeab390a;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, 0));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid_MerkleTreeWithOneValue_OfTheSecondCollection() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](2);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](2);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.sent[1].contractAddress = address(mockCollection2);

        mockCollection1.transferCreatorship(signer);
        mockCollection2.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, 1));
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_RevertsIfInvalidDiscountType() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;
        collectionDiscountCouponData.discountType = 100;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](1);

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(InvalidDiscountType.selector);
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.discount = 500_000;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        CollectionDiscountCouponHarness.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1 ether);
        assertEq(updatedTrade.received[2].value, 1.5 ether);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_RevertsIfDiscountGreaterThan1_000_000() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.discount = 1_000_001;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(); // [FAIL. Reason: panic: arithmetic underflow or overflow (0x11)]
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_Allows0Discount() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.discount = 0;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        CollectionDiscountCouponHarness.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 1 ether);
        assertEq(updatedTrade.received[1].value, 2 ether);
        assertEq(updatedTrade.received[2].value, 3 ether);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_Allows1_000_000Discount() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.discount = 1_000_000;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        CollectionDiscountCouponHarness.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0);
        assertEq(updatedTrade.received[1].value, 0);
        assertEq(updatedTrade.received[2].value, 0);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_MerkleTreeWithOneValue() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.discount = 500_000;
        collectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        CollectionDiscountCouponHarness.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1 ether);
        assertEq(updatedTrade.received[2].value, 1.5 ether);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_FlatDiscount() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_FLAT();
        collectionDiscountCouponData.discount = 0.5 ether;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        CollectionDiscountCouponHarness.Trade memory updatedTrade = collectionDiscountCoupon.applyCoupon(trade, coupon);

        assertEq(updatedTrade.received[0].value, 0.5 ether);
        assertEq(updatedTrade.received[1].value, 1.5 ether);
        assertEq(updatedTrade.received[2].value, 2.5 ether);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues_FlatDiscount_RevertsIfDiscountIsGreaterThanOriginalPrice() public {
        CollectionDiscountCouponHarness.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_FLAT();
        collectionDiscountCouponData.discount = 1000 ether;
        collectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CollectionDiscountCouponHarness.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        collectionDiscountCouponCallerData.proofs[0][2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;

        CollectionDiscountCouponHarness.Coupon memory coupon;
        coupon.data = abi.encode(collectionDiscountCouponData);
        coupon.callerData = abi.encode(collectionDiscountCouponCallerData);

        CollectionDiscountCouponHarness.Trade memory trade;
        trade.signer = signer;
        trade.sent = new CollectionDiscountCouponHarness.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection1);
        trade.received = new CollectionDiscountCouponHarness.Asset[](3);
        trade.received[0].value = 1 ether;
        trade.received[1].value = 2 ether;
        trade.received[2].value = 3 ether;

        mockCollection1.transferCreatorship(signer);

        vm.expectRevert(); // [FAIL. Reason: panic: arithmetic underflow or overflow (0x11)]
        collectionDiscountCoupon.applyCoupon(trade, coupon);
    }
}
