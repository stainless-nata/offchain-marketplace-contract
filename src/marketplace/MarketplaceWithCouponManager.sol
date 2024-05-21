// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Marketplace} from "src/marketplace/Marketplace.sol";
import {ICouponManager} from "src/coupons/interfaces/ICouponManager.sol";
import {CouponTypes} from "src/coupons/CouponTypes.sol";

/// @notice Marketplace contract that also allows the use of coupons.
/// Coupons are a way to modify Trades before they are executed, like Discounts.
abstract contract MarketplaceWithCouponManager is Marketplace, CouponTypes {
    /// @notice The address of the CouponManager contract.
    ICouponManager public couponManager;

    event CouponManagerUpdated(address indexed _caller, address indexed _couponManager);

    error TradesAndCouponsLengthMismatch();

    constructor(address _couponManager) {
        _updateCouponManager(_couponManager);
    }

    /// @notice Accepts a list of Trades with the given Coupons.
    /// @param _trades The list of Trades to accept.
    /// @param _coupons The list of Coupons to apply to the Trades.
    function acceptWithCoupon(Trade[] calldata _trades, Coupon[] calldata _coupons) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _coupons.length) {
            revert TradesAndCouponsLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            // It is important to verify the Trade before applying the coupons to avoid issues with the signature.
            _verifyTrade(_trades[i], caller);

            // Modify the Trade with the coupon and accept it normally.
            _accept(couponManager.applyCoupon(_trades[i], _coupons[i]), caller);
        }
    }

    /// @notice Updates the CouponManager address.
    /// @param _couponManager The new address of the CouponManager.
    function updateCouponManager(address _couponManager) external onlyOwner {
        _updateCouponManager(_couponManager);
    }

    function _updateCouponManager(address _couponManager) private {
        couponManager = ICouponManager(_couponManager);

        emit CouponManagerUpdated(_msgSender(), _couponManager);
    }
}
