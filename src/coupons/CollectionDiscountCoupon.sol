// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";
import {ICollection} from "src/marketplace/interfaces/ICollection.sol";
import {DecentralandMarketplacePolygonAssetTypes} from "src/marketplace/DecentralandMarketplacePolygonAssetTypes.sol";

/// @notice Coupon that allows creators to apply discounts to Trades involving their Collections.
contract CollectionDiscountCoupon is DecentralandMarketplacePolygonAssetTypes, CouponTypes, MarketplaceTypes {
    uint256 public constant DISCOUNT_TYPE_RATE = 1;
    uint256 public constant DISCOUNT_TYPE_FLAT = 2;

    /// @notice Schema Discount.
    /// @param discountType The type of discount to apply. DISCOUNT_TYPE_RATE for percentage discounts and DISCOUNT_TYPE_FLAT for fixed discounts.
    /// @param discount The value used to apply the discount. If discountType is DISCOUNT_TYPE_RATE, this value should be a percentage (e.g. 500_000 for 50% off). If discountType is DISCOUNT_TYPE_FLAT, this value should be the fixed discount amount.
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

    error InvalidSentOrProofsLength();
    error InvalidProof(uint256 _index);
    error SignerIsNotTheCreator(uint256 _index);
    error InvalidDiscountType();
    error UnsupportedSentAssetType(uint256 _index);
    error UnsupportedReceivedAssetType(uint256 _index);

    /// @notice Applies the discount to the received items of the Trade.
    /// @param _trade The Trade to apply the discount to.
    /// @param _coupon The Coupon to apply.
    /// @return - The Trade with the discount applied.
    function applyCoupon(MarketplaceTypes.Trade memory _trade, CouponTypes.Coupon memory _coupon)
        external
        view
        returns (MarketplaceTypes.Trade memory)
    {
        CollectionDiscountCouponData memory data = abi.decode(_coupon.data, (CollectionDiscountCouponData));
        CollectionDiscountCouponCallerData memory callerData = abi.decode(_coupon.callerData, (CollectionDiscountCouponCallerData));

        if (_trade.sent.length == 0 ||_trade.sent.length != callerData.proofs.length) {
            revert InvalidSentOrProofsLength();
        }

        // For each collection item being traded, a proof in the same index will be used to validate that the collection of that item is valid for the discount.
        for (uint256 i = 0; i < _trade.sent.length; i++) {
            Asset memory asset = _trade.sent[i];

            if (asset.assetType != ASSET_TYPE_COLLECTION_ITEM) {
                revert UnsupportedSentAssetType(i);
            }

            address collectionAddress = asset.contractAddress;

            if (ICollection(collectionAddress).creator() != _trade.signer) {
                revert SignerIsNotTheCreator(i);
            }

            if (!MerkleProof.verify(callerData.proofs[i], data.root, keccak256(bytes.concat(keccak256(abi.encode(address(collectionAddress))))))) {
                revert InvalidProof(i);
            }
        }

        // Every received asset must be an ERC20 token.
        // The discount will be applied to each one of them.
        // Keep in mind that if you provide a flat discount, the discount will be applied to each one.
        for (uint256 i = 0; i < _trade.received.length; i++) {
            if (_trade.received[i].assetType != ASSET_TYPE_ERC20) {
                revert UnsupportedReceivedAssetType(i);
            }

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
