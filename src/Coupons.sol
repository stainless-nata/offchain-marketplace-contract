// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Verifications} from "./common/Verifications.sol";
import {Types} from "./common/Types.sol";
import {EIP712} from "./external/EIP712.sol";
import {ICouponImplementation} from "./interfaces/ICouponImplementation.sol";
import {ICoupons} from "./interfaces/ICoupons.sol";

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
