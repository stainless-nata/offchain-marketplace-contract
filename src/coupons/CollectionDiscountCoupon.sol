// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";
import {ICollection} from "src/marketplace/ICollection.sol";

/// @notice Coupon that allows creators to apply discounts to Trades involving their Collections.
contract CollectionDiscountCoupon is CouponTypes, MarketplaceTypes {
    uint256 public constant DISCOUNT_TYPE_RATE = 1;
    uint256 public constant DISCOUNT_TYPE_FLAT = 2;

    /// @notice Schema Discount.
    /// @param rate The rate of the discount. Must be over 1 million instead of 100. For example, 10% would be 100_000.
    /// @param root The Merkle root of all the Collections that this Coupon will be valid for.
    struct CollectionDiscountCouponData {
        uint256 discountType;
        uint256 discount;
        bytes32 root;
    }

    /// @notice Schema of the data expected from the caller.
    /// @param proofs The Merkle proofs to validate that the collection items being traded are valid for the discount
    struct CollectionDiscountCouponCallerData {
        bytes32[][] proofs;
    }

    error TradeSentAndProofsLengthMismatch();
    error InvalidProof(uint256 _index);
    error SignerIsNotTheCreator(uint256 _index);
    error InvalidDiscountType();

    function applyCoupon(MarketplaceTypes.Trade memory _trade, CouponTypes.Coupon memory _coupon)
        external
        view
        returns (MarketplaceTypes.Trade memory)
    {
        CollectionDiscountCouponData memory data = abi.decode(_coupon.data, (CollectionDiscountCouponData));
        CollectionDiscountCouponCallerData memory callerData = abi.decode(_coupon.callerData, (CollectionDiscountCouponCallerData));

        if (_trade.sent.length != callerData.proofs.length) {
            revert TradeSentAndProofsLengthMismatch();
        }

        for (uint256 i = 0; i < _trade.sent.length; i++) {
            address collectionAddress = _trade.sent[i].contractAddress;

            if (ICollection(collectionAddress).creator() != _trade.signer) {
                revert SignerIsNotTheCreator(i);
            }

            if (!MerkleProof.verify(callerData.proofs[i], data.root, keccak256(bytes.concat(keccak256(abi.encode(address(collectionAddress))))))) {
                revert InvalidProof(i);
            }
        }

        for (uint256 i = 0; i < _trade.received.length; i++) {
            uint256 originalPrice = _trade.received[i].value;

            if (data.discountType == DISCOUNT_TYPE_RATE) {
                _trade.received[i].value = originalPrice - originalPrice * data.discount / 1_000_000;
            } else if (data.discountType == DISCOUNT_TYPE_FLAT) {
                _trade.received[i].value = originalPrice - data.discount;
            } else {
                revert InvalidDiscountType();
            }
        }

        return _trade;
    }
}
