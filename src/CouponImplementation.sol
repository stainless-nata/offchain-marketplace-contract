// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Types} from "./common/Types.sol";
import {ICouponImplementation} from "./interfaces/ICouponImplementation.sol";
import {ICollection} from "./interfaces/ICollection.sol";

contract CouponImplementation is ICouponImplementation {
    uint256 public constant COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT = 0;
    uint256 public constant COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT = 1;

    struct CouponData {
        uint256 discountType;
        bytes data;
    }

    struct MerkleCollectionDiscountCouponData {
        uint256 rate;
        bytes32 root;
    }

    struct MerkleCollectionDiscountCouponCallerData {
        bytes32[] proof;
    }

    struct SimpleCollectionDiscountCouponData {
        uint256 rate;
        address[] collections;
    }

    error InvalidDiscountType(uint256 _discountType);
    error TradesWithOneSentCollectionItemAllowed();
    error InvalidProof(address _collectionAddress);
    error CouponCannotBeApplied();
    error SignerIsNotTheCreator(address _signer, address _creator);

    function applyCoupon(Types.Trade memory _trade, Types.Coupon memory _coupon) external view returns (Types.Trade memory) {
        CouponData memory couponData = abi.decode(_coupon.data, (CouponData));

        uint256 discountType = couponData.discountType;

        if (discountType == COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT) {
            return _applyMerkleCollectionDiscountCoupon(_trade, couponData, _coupon.callerData);
        } else if (discountType == COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT) {
            return _applySimpleCollectionDiscountCoupon(_trade, couponData);
        } else {
            revert InvalidDiscountType(discountType);
        }
    }

    function _applyMerkleCollectionDiscountCoupon(Types.Trade memory _trade, CouponData memory _couponData, bytes memory _callerData)
        private
        view
        returns (Types.Trade memory)
    {
        MerkleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (MerkleCollectionDiscountCouponData));
        MerkleCollectionDiscountCouponCallerData memory callerData = abi.decode(_callerData, (MerkleCollectionDiscountCouponCallerData));

        address collection = _getCollectionAddress(_trade);

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(collection))));

        if (!MerkleProof.verify(callerData.proof, data.root, leaf)) {
            revert InvalidProof(collection);
        }

        _trade.received = _applyDiscountToAssets(_trade.received, data.rate);

        return _trade;
    }

    function _applySimpleCollectionDiscountCoupon(Types.Trade memory _trade, CouponData memory _couponData)
        private
        view
        returns (Types.Trade memory)
    {
        SimpleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (SimpleCollectionDiscountCouponData));

        address collection = _getCollectionAddress(_trade);

        bool isApplied = false;

        for (uint256 i = 0; i < data.collections.length; i++) {
            if (data.collections[i] == collection) {
                isApplied = true;
                break;
            }
        }

        if (!isApplied) {
            revert CouponCannotBeApplied();
        }

        _trade.received = _applyDiscountToAssets(_trade.received, data.rate);

        return _trade;
    }

    function _getCollectionAddress(Types.Trade memory _trade) private view returns(address) {
        if (_trade.sent.length != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        Types.Asset memory sentAsset = _trade.sent[0];

        ICollection collection = ICollection(sentAsset.contractAddress);

        address creator = collection.creator();

        if (creator != _trade.signer) {
            revert SignerIsNotTheCreator(_trade.signer, creator);
        }

        return address(collection);
    }

    function _applyDiscountToAssets(Types.Asset[] memory _assets, uint256 _rate) private pure returns (Types.Asset[] memory) {
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 originalPrice = _assets[i].value;
            _assets[i].value = originalPrice - originalPrice * _rate / 1_000_000;
        }

        return _assets;
    }
}
