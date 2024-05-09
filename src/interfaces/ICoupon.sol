// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Types} from "../common/Types.sol";

interface ICoupon {
    function applyCoupon(Types.Trade calldata _trade, Types.Coupon calldata _coupon) external view returns (Types.Trade memory);
}
