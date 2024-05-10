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
    /// @param proof The Merkle proof used to verify that the Traded collection applies for the discount.
    struct CollectionDiscountCouponCallerData {
        bytes32[] proof;
    }

    error TradesWithOneSentCollectionItemAllowed();
    error InvalidProof(address _collectionAddress);
    error SignerIsNotTheCreator(address _signer, address _creator);
    error InvalidDiscountType(uint256 _discountType);

    /// @notice Applies the discount to the received assets of the Trade.
    /// @param _trade The Trade to apply the discount to.
    /// @param _coupon The Coupon to apply.
    /// @return - Trade with the discount applied.
    ///
    /// Only Trades with one sent Collection item are allowed.
    ///
    /// All received assets will have the discount applied. !!!EVEN IF THEY ARE NOT ERC20s!!!.
    function applyCoupon(MarketplaceTypes.Trade memory _trade, CouponTypes.Coupon memory _coupon)
        external
        view
        returns (MarketplaceTypes.Trade memory)
    {
        if (_trade.sent.length != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        MarketplaceTypes.Asset memory sentAsset = _trade.sent[0];

        ICollection collection = ICollection(sentAsset.contractAddress);

        address creator = collection.creator();

        if (creator != _trade.signer) {
            revert SignerIsNotTheCreator(_trade.signer, creator);
        }

        address collectionAddress = address(collection);

        CollectionDiscountCouponData memory data = abi.decode(_coupon.data, (CollectionDiscountCouponData));
        CollectionDiscountCouponCallerData memory callerData = abi.decode(_coupon.callerData, (CollectionDiscountCouponCallerData));

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(collectionAddress))));

        if (!MerkleProof.verify(callerData.proof, data.root, leaf)) {
            revert InvalidProof(collectionAddress);
        }

        for (uint256 i = 0; i < _trade.received.length; i++) {
            uint256 originalPrice = _trade.received[i].value;

            if (data.discountType == DISCOUNT_TYPE_RATE) {
                _trade.received[i].value = originalPrice - originalPrice * data.discount / 1_000_000;
            } else if (data.discountType == DISCOUNT_TYPE_FLAT) {
                _trade.received[i].value = originalPrice - data.discount;
            } else {
                revert InvalidDiscountType(data.discountType);
            }
        }

        return _trade;
    }
}
