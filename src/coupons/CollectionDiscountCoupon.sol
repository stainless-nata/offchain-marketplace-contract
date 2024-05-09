// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Types} from "../common/Types.sol";
import {ICouponImplementation} from "../interfaces/ICouponImplementation.sol";
import {ICollection} from "../interfaces/ICollection.sol";

contract CollectionDiscountCoupon is ICouponImplementation {
    struct CollectionDiscountCouponData {
        uint256 rate;
        bytes32 root;
    }

    struct CollectionDiscountCouponCallerData {
        bytes32[] proof;
    }

    error TradesWithOneSentCollectionItemAllowed();
    error InvalidProof(address _collectionAddress);
    error SignerIsNotTheCreator(address _signer, address _creator);

    function applyCoupon(Types.Trade memory _trade, Types.Coupon memory _coupon) external view returns (Types.Trade memory) {
        if (_trade.sent.length != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        Types.Asset memory sentAsset = _trade.sent[0];

        ICollection collection = ICollection(sentAsset.contractAddress);

        address creator = collection.creator();

        if (creator != _trade.signer) {
            revert SignerIsNotTheCreator(_trade.signer, creator);
        }

        address collectionAddress = address(collection);

        CollectionDiscountCouponData memory data = abi.decode(_coupon.data, (CollectionDiscountCouponData));
        CollectionDiscountCouponCallerData memory callerData = abi.decode(_coupon.callerData, (CollectionDiscountCouponCallerData));

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(collectionAddress))));

        if (!MerkleProof.verify(callerData.proof, data.root, leaf)) {
            revert InvalidProof(collectionAddress);
        }

        for (uint256 i = 0; i < _trade.received.length; i++) {
            uint256 originalPrice = _trade.received[i].value;
            _trade.received[i].value = originalPrice - originalPrice * data.rate / 1_000_000;
        }

        return _trade;
    }
}
