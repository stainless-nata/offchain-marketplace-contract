// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Marketplace} from "src/marketplace/Marketplace.sol";
import {ICouponManager} from "src/coupons/interfaces/ICouponManager.sol";
import {CouponTypes} from "src/coupons/CouponTypes.sol";

abstract contract MarketplaceWithCouponManager is Marketplace, CouponTypes {
    ICouponManager public couponManager;

    event CouponManagerUpdated(address indexed _caller, address indexed _couponManager);

    error TradesAndCouponsLengthMismatch();

    constructor(address _couponManager) {
        _updateCouponManager(_couponManager);
    }

    function acceptWithCoupon(Trade[] calldata _trades, Coupon[] calldata _coupons) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _coupons.length) {
            revert TradesAndCouponsLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);
            _accept(couponManager.applyCoupon(_trades[i], _coupons[i]), caller);
        }
    }

    function updateCouponManager(address _couponManager) external onlyOwner {
        _updateCouponManager(_couponManager);
    }

    function _updateCouponManager(address _couponManager) private {
        couponManager = ICouponManager(_couponManager);

        emit CouponManagerUpdated(_msgSender(), _couponManager);
    }
}
