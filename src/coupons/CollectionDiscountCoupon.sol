// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";
import {ICollection} from "src/marketplace/ICollection.sol";
import {DecentralandMarketplacePolygonAssetTypes} from "src/marketplace/DecentralandMarketplacePolygonAssetTypes.sol";

/// @notice Coupon that allows creators to apply discounts to Trades involving their Collections.
contract CollectionDiscountCoupon is DecentralandMarketplacePolygonAssetTypes, CouponTypes, MarketplaceTypes {
    /// @notice Schema Discount.
    /// @param discount The rate of the discount. Must be between over 1 million instead of 100. For example, 10% would be 100_000.
    /// @param root The Merkle root of all the Collections that this Coupon will be valid for.
    struct CollectionDiscountCouponData {
        uint256 discount;
        bytes32 root;
    }

    /// @notice Schema of the data expected from the caller.
    /// @param proofs The Merkle proofs to validate that the collection items being traded are valid for the discount
    struct CollectionDiscountCouponCallerData {
        bytes32[][] proofs;
    }

    error TradeSentAndProofsLengthMismatch();
    error UnsupportedSentAssetType(uint256 _index);
    error SignerIsNotTheCreator(uint256 _index);
    error InvalidProof(uint256 _index);
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

        if (_trade.sent.length != callerData.proofs.length) {
            revert TradeSentAndProofsLengthMismatch();
        }

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

        for (uint256 i = 0; i < _trade.received.length; i++) {
            if (_trade.received[i].assetType != ASSET_TYPE_ERC20) {
                revert UnsupportedReceivedAssetType(i);
            }

            uint256 originalPrice = _trade.received[i].value;

            _trade.received[i].value = originalPrice - originalPrice * data.discount / 1_000_000;
        }

        return _trade;
    }
}
