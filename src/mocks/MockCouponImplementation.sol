// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ICouponImplementation} from "../interfaces/ICouponImplementation.sol";
import {Types} from "../common/Types.sol";

contract MockCouponImplementation is ICouponImplementation {

    function applyCoupon(Types.Trade memory _trade, Types.Coupon memory) external pure returns (Types.Trade memory) {
        _trade.signer = address(1337);

        return _trade;
    }
}
