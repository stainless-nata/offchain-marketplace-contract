// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Verifications} from "src/common/Verifications.sol";
import {EIP712} from "src/common/EIP712.sol";
import {ICoupon} from "src/coupons/interfaces/ICoupon.sol";
import {CouponTypesHashing} from "src/coupons/CouponTypesHashing.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";

contract CouponManager is Verifications, CouponTypesHashing, MarketplaceTypes {
    address public marketplace;
    mapping(address => bool) public allowedCoupons;

    event MarketplaceUpdated(address indexed _caller, address indexed _marketplace);
    event AllowedCouponsUpdated(address indexed _caller, address indexed _coupon, bool _value);
    event CouponApplied(address indexed _caller, bytes32 indexed _tradeSignature, bytes32 indexed _couponSignature);

    error LengthMissmatch();
    error UnauthorizedCaller(address _caller);
    error CouponNotAllowed(address _coupon);

    constructor(address _marketplace, address _owner, address[] memory _allowedCoupons) EIP712("CouponManager", "1.0.0") Ownable(_owner) {
        _updateMarketplace(_marketplace);

        for (uint256 i = 0; i < _allowedCoupons.length; i++) {
            _updateAllowedCoupons(_allowedCoupons[i], true);
        }
    }

    function updateMarketplace(address _marketplace) external onlyOwner {
        _updateMarketplace(_marketplace);
    }

    function updateAllowedCoupons(address[] memory _coupons, bool[] memory _values) external onlyOwner {
        if (_coupons.length != _values.length) {
            revert LengthMissmatch();
        }

        for (uint256 i = 0; i < _coupons.length; i++) {
            _updateAllowedCoupons(_coupons[i], _values[i]);
        }
    }

    function cancelSignature(Coupon[] calldata _coupons) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _coupons.length; i++) {
            Coupon memory coupon = _coupons[i];

            _verifyCouponSignature(coupon, caller);

            _cancelSignature(keccak256(coupon.signature));
        }
    }

    function applyCoupon(Trade calldata _trade, Coupon calldata _coupon) external virtual returns (Trade memory) {
        address caller = _msgSender();

        if (caller != marketplace) {
            revert UnauthorizedCaller(caller);
        }

        address couponAddress = _coupon.couponAddress;

        if (!allowedCoupons[couponAddress]) {
            revert CouponNotAllowed(couponAddress);
        }

        bytes32 hashedCouponSignature = keccak256(_coupon.signature);
        bytes32 hashedTradeSignature = keccak256(_trade.signature);
        uint256 currentSignatureUses = signatureUses[hashedCouponSignature];
        address signer = _trade.signer;

        _verifyChecks(_coupon.checks, hashedCouponSignature, currentSignatureUses, signer, caller);
        _verifyCouponSignature(_coupon, signer);

        emit CouponApplied(caller, hashedTradeSignature, hashedCouponSignature);

        signatureUses[hashedCouponSignature]++;

        return ICoupon(couponAddress).applyCoupon(_trade, _coupon);
    }

    function _verifyCouponSignature(Coupon memory _coupon, address _signer) private view {
        _verifySignature(_hashCoupon(_coupon), _coupon.signature, _signer);
    }

    function _updateMarketplace(address _marketplace) private {
        marketplace = _marketplace;

        emit MarketplaceUpdated(_msgSender(), _marketplace);
    }

    function _updateAllowedCoupons(address _coupon, bool _value) private {
        allowedCoupons[_coupon] = _value;

        emit AllowedCouponsUpdated(_msgSender(), _coupon, _value);
    }
}
