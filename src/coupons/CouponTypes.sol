// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonTypes} from "src/common/CommonTypes.sol";

/// @notice Types used by the Coupons.
abstract contract CouponTypes is CommonTypes {
    /// @notice Schema for the Coupon type.
    /// @param signature Signature of the coupon.
    /// @param checks Values to be verified before applying the coupon.
    /// @param couponAddress Address of the Coupon contract to be used.
    /// @param data Data to be used by the Coupon contract.
    /// @param callerData Data sent by the caller to be used by the Coupon contract.
    struct Coupon {
        bytes signature;
        Checks checks;
        address couponAddress;
        bytes data;
        bytes callerData;
    }
}
