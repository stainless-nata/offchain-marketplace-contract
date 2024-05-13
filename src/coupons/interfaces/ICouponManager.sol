// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CouponTypes} from "src/coupons/CouponTypes.sol";
import {MarketplaceTypes} from "src/marketplace/MarketplaceTypes.sol";

interface ICouponManager {
    function applyCoupon(MarketplaceTypes.Trade calldata _trade, CouponTypes.Coupon calldata _coupon) external returns (MarketplaceTypes.Trade memory);
}
