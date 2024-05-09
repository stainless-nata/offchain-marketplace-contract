// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICoupon} from "src/coupons/ICoupon.sol";
import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";

contract MockCoupon is ICoupon {
    function applyCoupon(MarketplaceTypes.Trade memory _trade, CouponTypes.Coupon memory) external pure returns (MarketplaceTypes.Trade memory) {
        _trade.signer = address(1337);

        return _trade;
    }
}
