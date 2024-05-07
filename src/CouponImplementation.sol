import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {Types} from "./common/Types.sol";
import {ICouponImplementation} from "./interfaces/ICouponImplementation.sol";

contract CouponImplementation is ICouponImplementation {
    uint256 public constant COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT = 0;
    uint256 public constant COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT = 1;

    struct CouponData {
        uint256 discountType;
        bytes data;
    }

    struct MerkleCollectionDiscountCouponData {
        uint256 rate;
        bytes32 root;
    }

    struct MerkleCollectionDiscountCouponCallerData {
        bytes32[] proof;
    }

    struct SimpleCollectionDiscountCouponData {
        uint256 rate;
        address[] collections;
    }

    error InvalidDiscountType(uint256 _discountType);
    error TradesWithOneSentCollectionItemAllowed();
    error InvalidProof(address _collectionAddress);
    error CouponCannotBeApplied();

    function applyCoupon(Types.Trade memory _trade, Types.Coupon memory _coupon) external pure returns (Types.Trade memory) {
        CouponData memory couponData = abi.decode(_coupon.data, (CouponData));

        uint256 discountType = couponData.discountType;

        if (discountType == COUPON_TYPE_MERKLE_COLLECTION_DISCOUNT) {
            return _applyMerkleCollectionDiscountCoupon(_trade, couponData, _coupon.callerData);
        } else if (discountType == COUPON_TYPE_SIMPLE_COLLECTION_DISCOUNT) {
            return _applySimpleCollectionDiscountCoupon(_trade, couponData);
        } else {
            revert InvalidDiscountType(discountType);
        }
    }

    function _applyMerkleCollectionDiscountCoupon(Types.Trade memory _trade, CouponData memory _couponData, bytes memory _callerData)
        private
        pure
        returns (Types.Trade memory)
    {
        MerkleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (MerkleCollectionDiscountCouponData));
        MerkleCollectionDiscountCouponCallerData memory callerData = abi.decode(_callerData, (MerkleCollectionDiscountCouponCallerData));

        Types.Asset memory sentAsset = _getFirstAsset(_trade.sent);

        if (!MerkleProof.verify(callerData.proof, data.root, keccak256(abi.encode(sentAsset.contractAddress)))) {
            revert InvalidProof(sentAsset.contractAddress);
        }

        _trade.received = _applyDiscountToAssets(_trade.received, data.rate);

        return _trade;
    }

    function _applySimpleCollectionDiscountCoupon(Types.Trade memory _trade, CouponData memory _couponData) private pure returns (Types.Trade memory) {
        SimpleCollectionDiscountCouponData memory data = abi.decode(_couponData.data, (SimpleCollectionDiscountCouponData));

        Types.Asset memory sentAsset = _getFirstAsset(_trade.sent);

        bool isApplied = false;

        for (uint256 i = 0; i < data.collections.length; i++) {
            if (data.collections[i] == sentAsset.contractAddress) {
                isApplied = true;
                break;
            }
        }

        if (!isApplied) {
            revert CouponCannotBeApplied();
        }

        _trade.received = _applyDiscountToAssets(_trade.received, data.rate);

        return _trade;
    }

    function _getFirstAsset(Types.Asset[] memory _assets) private pure returns (Types.Asset memory) {
        if (_assets.length != 1) {
            revert TradesWithOneSentCollectionItemAllowed();
        }

        return _assets[0];
    }

    function _applyDiscountToAssets(Types.Asset[] memory _assets, uint256 _rate) private pure returns (Types.Asset[] memory) {
        for (uint256 i = 0; i < _assets.length; i++) {
            uint256 originalPrice = _assets[i].value;
            _assets[i].value = originalPrice - originalPrice * _rate / 1_000_000;
        }

        return _assets;
    }
}
