// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Verifications} from "./common/Verifications.sol";
import {Types} from "./common/Types.sol";

interface ICouponImplementation {
    function applyCoupon(Types.Trade calldata _trade, Types.Coupon calldata _coupon) external view returns (Types.Trade memory);
}

interface ICoupons {
    function applyCoupon(Types.Trade calldata _trade, Types.Coupon calldata _coupon) external returns (Types.Trade memory);
}

abstract contract Coupons is ICoupons, Verifications {
    address public marketplace;
    mapping(address => bool) public allowedCouponImplementations;

    event AllowedCouponImplementationsChanged(address indexed _caller, address indexed _couponImplementation, bool _value);
    event CouponApplied(address indexed _caller, bytes32 indexed _tradeSignature, bytes32 indexed _couponSignature);

    error LengthMissmatch();
    error CouponImplementationNotAllowed(address _couponImplementation);

    constructor(address _marketplace) {
        marketplace = _marketplace;
    }

    function updateAllowedCouponImplementations(address[] memory _couponImplementations, bool[] memory _values) external onlyOwner {
        if (_couponImplementations.length != _values.length) {
            revert LengthMissmatch();
        }

        address caller = _msgSender();

        for (uint256 i = 0; i < _couponImplementations.length; i++) {
            address couponImplementation = _couponImplementations[i];
            bool value = _values[i];

            allowedCouponImplementations[couponImplementation] = value;

            emit AllowedCouponImplementationsChanged(caller, couponImplementation, value);
        }
    }

    function applyCoupon(Trade calldata _trade, Coupon calldata _coupon) external virtual returns (Trade memory) {
        address couponImplementation = _coupon.couponImplementation;

        if (!allowedCouponImplementations[couponImplementation]) {
            revert CouponImplementationNotAllowed(couponImplementation);
        }

        bytes32 hashedCouponSignature = keccak256(_coupon.signature);
        bytes32 hashedTradeSignature = keccak256(_trade.signature);
        uint256 currentSignatureUses = signatureUses[hashedCouponSignature];
        address caller = _msgSender();

        _verifyChecks(_coupon.checks, currentSignatureUses, _trade.signer, caller);

        emit CouponApplied(caller, hashedTradeSignature, hashedCouponSignature);

        signatureUses[hashedCouponSignature]++;

        return ICouponImplementation(couponImplementation).applyCoupon(_trade, _coupon);
    }
}

contract CouponImplementation is ICouponImplementation, Types {
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

    function applyCoupon(Trade memory _trade, Coupon memory _coupon) external pure returns (Trade memory) {
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

    function _applyMerkleCollectionDiscountCoupon(Trade memory _trade, CouponData memory _couponData, bytes memory _callerData)
        private
        pure
        returns (Trade memory)
    {
        MerkleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (MerkleCollectionDiscountCouponData));
        MerkleCollectionDiscountCouponCallerData memory callerData = abi.decode(_callerData, (MerkleCollectionDiscountCouponCallerData));

        Asset[] memory sent = _trade.sent;

        uint256 sentLength = sent.length;

        if (sentLength != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        Asset memory sentAsset = sent[0];

        address collectionAddress = sentAsset.contractAddress;

        if (!MerkleProof.verify(callerData.proof, data.root, keccak256(abi.encode(collectionAddress)))) {
            revert InvalidProof(collectionAddress);
        }

        Asset[] memory received = _trade.received;

        for (uint256 i = 0; i < received.length; i++) {
            Asset memory receivedAsset = received[i];

            uint256 originalPrice = receivedAsset.value;

            receivedAsset.value = originalPrice - originalPrice * data.rate / 1_000_000;
        }

        return _trade;
    }

    function _applySimpleCollectionDiscountCoupon(Trade memory _trade, CouponData memory _couponData) private pure returns (Trade memory) {
        SimpleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (SimpleCollectionDiscountCouponData));

        Asset[] memory sent = _trade.sent;

        uint256 sentLength = sent.length;

        if (sentLength != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        Asset memory sentAsset = sent[0];

        address collectionAddress = sentAsset.contractAddress;

        bool isApplied = false;

        for (uint256 i = 0; i < data.collections.length; i++) {
            if (data.collections[i] == collectionAddress) {
                isApplied = true;
                break;
            }
        }

        if (!isApplied) {
            revert CouponCannotBeApplied();
        }

        Asset[] memory received = _trade.received;

        for (uint256 i = 0; i < received.length; i++) {
            Asset memory receivedAsset = received[i];

            uint256 originalPrice = receivedAsset.value;

            receivedAsset.value = originalPrice - originalPrice * data.rate / 1_000_000;
        }

        return _trade;
    }
}
