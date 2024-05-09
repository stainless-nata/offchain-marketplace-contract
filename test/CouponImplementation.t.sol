// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CouponImplementation} from "../src/CouponImplementation.sol";
import {Types} from "../src/common/Types.sol";
import {MockCollection} from "../src/mocks/MockCollection.sol";

contract CouponImplementationHarness is CouponImplementation {}

contract CouponImplementationTests is Test {
    address signer;
    CouponImplementationHarness couponImplementation;
    MockCollection mockCollection;

    error TradesWithOneSentCollectionItemAllowed();
    error SignerIsNotTheCreator(address _signer, address _creator);

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
        simpleCollectionDiscountCouponData.collections = new address[](10);
        simpleCollectionDiscountCouponData.collections[0] = address(1);
        simpleCollectionDiscountCouponData.collections[1] = address(2);
        simpleCollectionDiscountCouponData.collections[2] = address(3);
        simpleCollectionDiscountCouponData.collections[3] = address(4);
        simpleCollectionDiscountCouponData.collections[4] = address(5);
        simpleCollectionDiscountCouponData.collections[5] = address(6);
        simpleCollectionDiscountCouponData.collections[6] = address(7);
        simpleCollectionDiscountCouponData.collections[7] = address(8);
        simpleCollectionDiscountCouponData.collections[8] = address(9);
        simpleCollectionDiscountCouponData.collections[9] = address(10);
        
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
        simpleCollectionDiscountCouponData.collections = new address[](10);
        simpleCollectionDiscountCouponData.collections[0] = address(1);
        simpleCollectionDiscountCouponData.collections[1] = address(2);
        simpleCollectionDiscountCouponData.collections[2] = address(3);
        simpleCollectionDiscountCouponData.collections[3] = address(4);
        simpleCollectionDiscountCouponData.collections[4] = address(5);
        simpleCollectionDiscountCouponData.collections[5] = address(6);
        simpleCollectionDiscountCouponData.collections[6] = address(7);
        simpleCollectionDiscountCouponData.collections[7] = address(8);
        simpleCollectionDiscountCouponData.collections[8] = address(9);
        simpleCollectionDiscountCouponData.collections[9] = address(mockCollection);
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

    function test_AppliesTheDiscountToAllReceivedAssetValues_OnlyOneCollection() public {
        CouponImplementationHarness.SimpleCollectionDiscountCouponData memory simpleCollectionDiscountCouponData;
        simpleCollectionDiscountCouponData.collections = new address[](1);
        simpleCollectionDiscountCouponData.collections[0] = address(mockCollection);
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

contract ApplyMerkleCollectionDiscountCouponTests is CouponImplementationTests {
    error InvalidProof(address _collectionAddress);

    function test_RevertsIfMerkleCollectionDiscountCouponDataIsInvalid() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = bytes("");

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfMerkleCollectionDiscountCouponCallerDataIsInvalid() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = bytes("");

        Types.Trade memory trade;

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasZeroSentAssets() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeHasTwoSentAssets() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](2);

        vm.expectRevert(TradesWithOneSentCollectionItemAllowed.selector);
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfSentAssetDoesNotHaveTheCreatorFunction() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.sent = new Types.Asset[](1);

        vm.expectRevert();
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfTradeSignerIsNotTheCreatorOfTheCollection() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        vm.expectRevert(abi.encodeWithSelector(SignerIsNotTheCreator.selector, signer, address(0)));
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        merkleCollectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;

        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        merkleCollectionDiscountCouponCallerData.proof = new bytes32[](3);
        merkleCollectionDiscountCouponCallerData.proof[0] = 0xaef723aaf2a9471d0444688035cd22ee9e9408f4d3390ce0a2a80b76aeab390a;
        merkleCollectionDiscountCouponCallerData.proof[1] = 0x91f8b8d2c336dbdb2484b34885b0070baf79ebd29c182c675de7a0f92adc273a;
        merkleCollectionDiscountCouponCallerData.proof[2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, address(mockCollection)));
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_RevertsIfProofIsInvalid_MerkleTreeWithOneValue() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        merkleCollectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;

        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

        Types.Trade memory trade;
        trade.signer = signer;
        trade.sent = new Types.Asset[](1);
        trade.sent[0].contractAddress = address(mockCollection);

        mockCollection.transferCreatorship(signer);

        vm.expectRevert(abi.encodeWithSelector(InvalidProof.selector, address(mockCollection)));
        couponImplementation.applyCoupon(trade, coupon);
    }

    function test_AppliesTheDiscountToAllReceivedAssetValues() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        merkleCollectionDiscountCouponData.root = 0x56980103ca6f02663aeaa6b3895be0e41e507731e5a2655d3da8c9c8618ccc92;
        merkleCollectionDiscountCouponData.rate = 500_000;

        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        merkleCollectionDiscountCouponCallerData.proof = new bytes32[](3);
        merkleCollectionDiscountCouponCallerData.proof[0] = 0xa7c46294ffa3fad92dc8422b2e38b688ccf1b86172f5beaf864af9368d2844e5;
        merkleCollectionDiscountCouponCallerData.proof[1] = 0xb8e277bcec6ddfe5a414b2200b3abcb1d3ee435c66531e8f21898f36a7ed122f;
        merkleCollectionDiscountCouponCallerData.proof[2] = 0x7747f5b3dcece1341b1470c482b95e4b5565365e4169abeb52162734e62147cf;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

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

    function test_AppliesTheDiscountToAllReceivedAssetValues_MerkleTreeWithOneValue() public {
        CouponImplementationHarness.MerkleCollectionDiscountCouponData memory merkleCollectionDiscountCouponData;
        merkleCollectionDiscountCouponData.root = 0x7e321b7ae61d2fe49a2b9c8ba4d76b1b7f74d5eb773b09d8e23120a69998b51c;
        merkleCollectionDiscountCouponData.rate = 500_000;

        CouponImplementationHarness.MerkleCollectionDiscountCouponCallerData memory merkleCollectionDiscountCouponCallerData;
        
        CouponImplementationHarness.CouponData memory couponData;
        couponData.discountType = couponImplementation.COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT();
        couponData.data = abi.encode(merkleCollectionDiscountCouponData);

        Types.Coupon memory coupon;
        coupon.data = abi.encode(couponData);
        coupon.callerData = abi.encode(merkleCollectionDiscountCouponCallerData);

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
