// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CommonTypesHashing} from "src/common/CommonTypesHashing.sol";
import {CouponTypes} from "src/coupons/CouponTypes.sol";

/// @notice Hashing functions for the Coupon types. Used for EIP712 signatures.
abstract contract CouponTypesHashing is CouponTypes, CommonTypesHashing {
    // keccak256("Coupon(Checks checks,address couponAddress,bytes data)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,bytes32 allowedRoot,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant COUPON_TYPE_HASH = 0x292da07e676081e3ba5e18abd89865d35a8c4b0bb60f9f45a2ba35ae4428a902;

    function _hashCoupon(Coupon memory _coupon) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                COUPON_TYPE_HASH, 
                _hashChecks(_coupon.checks), 
                _coupon.couponAddress, 
                keccak256(_coupon.data)
            )
        );
    }
}
