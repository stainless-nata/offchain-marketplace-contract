// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";
import {ICollection} from "src/marketplace/ICollection.sol";

contract CollectionDiscountCoupon is CouponTypes, MarketplaceTypes {
    struct CollectionDiscountCouponData {
        uint256 rate;
        bytes32 root;
    }

    struct CollectionDiscountCouponCallerData {
        bytes32[] proof;
    }

    error TradesWithOneSentCollectionItemAllowed();
    error InvalidProof(address _collectionAddress);
    error SignerIsNotTheCreator(address _signer, address _creator);

    function applyCoupon(MarketplaceTypes.Trade memory _trade, CouponTypes.Coupon memory _coupon) external view returns (MarketplaceTypes.Trade memory) {
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
            _trade.received[i].value = originalPrice - originalPrice * data.rate / 1_000_000;
        }

        return _trade;
    }
}
