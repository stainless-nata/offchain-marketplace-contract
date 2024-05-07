// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Verifications} from "./common/Verifications.sol";
import {Types} from "./common/Types.sol";
import {EIP712} from "./external/EIP712.sol";
import {ICouponImplementation} from "./interfaces/ICouponImplementation.sol";

interface ICoupons {
    function applyCoupon(Types.Trade calldata _trade, Types.Coupon calldata _coupon) external returns (Types.Trade memory);
}

contract Coupons is ICoupons, Verifications {
    address public marketplace;
    mapping(address => bool) public allowedCouponImplementations;

    event MarketplaceUpdated(address indexed _caller, address indexed _marketplace);
    event AllowedCouponImplementationsUpdated(address indexed _caller, address indexed _couponImplementation, bool _value);
    event CouponApplied(address indexed _caller, bytes32 indexed _tradeSignature, bytes32 indexed _couponSignature);

    error LengthMissmatch();
    error UnauthorizedCaller(address _caller);
    error CouponImplementationNotAllowed(address _couponImplementation);

    constructor(address _marketplace, address _owner, address[] memory _allowedCouponImplementations) EIP712("Coupons", "1.0.0") Ownable(_owner) {
        _updateMarketplace(_marketplace);

        for (uint256 i = 0; i < _allowedCouponImplementations.length; i++) {
            _updateAllowedCouponImplementations(_allowedCouponImplementations[i], true);
        }
    }

    function updateMarketplace(address _marketplace) external onlyOwner {
        _updateMarketplace(_marketplace);
    }

    function updateAllowedCouponImplementations(address[] memory _couponImplementations, bool[] memory _values) external onlyOwner {
        if (_couponImplementations.length != _values.length) {
            revert LengthMissmatch();
        }

        for (uint256 i = 0; i < _couponImplementations.length; i++) {
            _updateAllowedCouponImplementations(_couponImplementations[i], _values[i]);
        }
    }

    function applyCoupon(Trade calldata _trade, Coupon calldata _coupon) external virtual returns (Trade memory) {
        address caller = _msgSender();

        if (caller != marketplace) {
            revert UnauthorizedCaller(caller);
        }

        address couponImplementation = _coupon.couponImplementation;

        if (!allowedCouponImplementations[couponImplementation]) {
            revert CouponImplementationNotAllowed(couponImplementation);
        }

        bytes32 hashedCouponSignature = keccak256(_coupon.signature);
        bytes32 hashedTradeSignature = keccak256(_trade.signature);
        uint256 currentSignatureUses = signatureUses[hashedCouponSignature];

        _verifyChecks(_coupon.checks, currentSignatureUses, _trade.signer, caller);
        _verifyCouponSignature(_coupon, _trade.signer);

        emit CouponApplied(caller, hashedTradeSignature, hashedCouponSignature);

        signatureUses[hashedCouponSignature]++;

        return ICouponImplementation(couponImplementation).applyCoupon(_trade, _coupon);
    }

    function _verifyCouponSignature(Coupon memory _coupon, address _signer) private view {
        _verifySignature(_hashCoupon(_coupon), _coupon.signature, _signer);
    }

    function _updateMarketplace(address _marketplace) private {
        marketplace = _marketplace;

        emit MarketplaceUpdated(_msgSender(), _marketplace);
    }

    function _updateAllowedCouponImplementations(address _couponImplementation, bool _value) private {
        allowedCouponImplementations[_couponImplementation] = _value;

        emit AllowedCouponImplementationsUpdated(_msgSender(), _couponImplementation, _value);
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

        Asset memory sentAsset = _getFirstAsset(_trade.sent);

        if (!MerkleProof.verify(callerData.proof, data.root, keccak256(abi.encode(sentAsset.contractAddress)))) {
            revert InvalidProof(sentAsset.contractAddress);
        }

        _trade.received = _applyDiscountToAssets(_trade.received, data.rate);

        return _trade;
    }

    function _applySimpleCollectionDiscountCoupon(Trade memory _trade, CouponData memory _couponData) private pure returns (Trade memory) {
        SimpleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (SimpleCollectionDiscountCouponData));

        Asset memory sentAsset = _getFirstAsset(_trade.sent);

        bool isApplied = false;

        for (uint256 i = 0; i < data.collections.length; i++) {
            if (data.collections[i] == sentAsset.contractAddress) {
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

    function _getFirstAsset(Asset[] memory _assets) private pure returns (Asset memory) {
        if (_assets.length != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        return _assets[0];
    }

    function _applyDiscountToAssets(Asset[] memory _assets, uint256 _rate) private pure returns (Asset[] memory) {
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 originalPrice = _assets[i].value;
            _assets[i].value = originalPrice - originalPrice * _rate / 1_000_000;
        }

        return _assets;
    }
}
