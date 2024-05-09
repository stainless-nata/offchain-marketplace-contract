// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonTypes} from "src/common/CommonTypes.sol";

abstract contract CouponTypes is CommonTypes {
    struct Coupon {
        bytes signature;
        Checks checks;
        address couponAddress;
        bytes data;
        bytes callerData;
    }
}
