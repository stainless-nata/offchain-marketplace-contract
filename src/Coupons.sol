// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Verifications} from "./common/Verifications.sol";
import {Structs} from "./common/Structs.sol";

interface ICouponImplementation {
    function applyCoupon(Structs.Trade calldata _trade, Structs.Coupon calldata _coupon) external view returns (Structs.Trade memory);
}

interface ICoupons {
    function applyCoupon(Structs.Trade calldata _trade, Structs.Coupon calldata _coupon) external returns (Structs.Trade memory);
}

abstract contract Coupons is ICoupons, Verifications {
    address public marketplace;
    mapping(address => bool) public allowedCouponImplementations;

    event AllowedCouponImplementationsChanged(address indexed _caller, address indexed _couponImplementation, bool _value);
    event CouponApplied(address indexed _caller, bytes32 indexed _tradeSignature, bytes32 indexed _couponSignature);

    error LengthMissmatch();
    error CouponImplementationNotAllowed(address couponImplementation);

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
