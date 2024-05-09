// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Types} from "../common/Types.sol";

interface ICouponManager {
    function applyCoupon(Types.Trade calldata _trade, Types.Coupon calldata _coupon) external returns (Types.Trade memory);
}
