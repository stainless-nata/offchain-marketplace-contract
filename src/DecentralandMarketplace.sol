// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Marketplace} from "src/marketplace/Marketplace.sol";
import {ICouponManager} from "src/coupons/ICouponManager.sol";
import {EIP712} from "src/common/EIP712.sol";
import {NativeMetaTransaction} from "src/common/NativeMetaTransaction.sol";
import {IComposable} from "src/IComposable.sol";
import {ICollection} from "src/ICollection.sol";
import {CouponTypes} from "src/coupons/CouponTypes.sol";

contract DecentralandMarketplace is Marketplace, NativeMetaTransaction, CouponTypes {
    uint256 public constant ASSET_TYPE_ERC20 = 1;
    uint256 public constant ASSET_TYPE_ERC20_WITH_FEE = 2;
    uint256 public constant ASSET_TYPE_ERC721 = 3;
    uint256 public constant ASSET_TYPE_ERC721_COMPOSABLE = 4;
    uint256 public constant ASSET_TYPE_ERC721_COLLECTION_ITEM = 5;

    ICouponManager public couponManager;

    event CouponManagerUpdated(address indexed _caller, address indexed _couponManager);

    error TradesAndCouponsLengthMismatch();
    error InvalidFingerprint();
    error NotCreator();
    error UnsupportedAssetType(uint256 _assetType);

    constructor(address _owner, address _couponManager) Ownable(_owner) EIP712("DecentralandMarketplace", "1.0.0") {
        _updateCouponManager(_couponManager);
    }

    function updateCouponManager(address _couponManager) external onlyOwner {
        _updateCouponManager(_couponManager);
    }

    function acceptWithCoupon(Trade[] calldata _trades, Coupon[] calldata _coupons) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _coupons.length) {
            revert TradesAndCouponsLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);
            _accept(couponManager.applyCoupon(_trades[i], _coupons[i]), caller);
        }
    }

    function _updateCouponManager(address _couponManager) private {
        couponManager = ICouponManager(_couponManager);

        emit CouponManagerUpdated(_msgSender(), _couponManager);
    }

    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20) {
            _transferERC20(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC20_WITH_FEE) {
            _transferERC20WithFee(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC721) {
            _transferERC721(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC721_COMPOSABLE) {
            _transferERC721Composable(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC721_COLLECTION_ITEM) {
            _transferERC721CollectionItem(_asset, _signer, _caller);
        } else {
            revert UnsupportedAssetType(assetType);
        }
    }

    function _transferERC20(Asset memory _asset, address _from) private {
        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, _asset.beneficiary, _asset.value);
    }

    function _transferERC20WithFee(Asset memory _asset, address _from) private {
        (uint256 feeRate, address feeBeneficiary) = abi.decode(_asset.extra, (uint256, address));

        uint256 fee = _asset.value * feeRate / 1_000_000;

        IERC20 erc20 = IERC20(_asset.contractAddress);

        SafeERC20.safeTransferFrom(erc20, _from, _asset.beneficiary, _asset.value - fee);
        SafeERC20.safeTransferFrom(erc20, _from, feeBeneficiary, fee);
    }

    function _transferERC721(Asset memory _asset, address _from) private {
        IERC721(_asset.contractAddress).safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }

    function _transferERC721Composable(Asset memory _asset, address _from) private {
        IComposable composable = IComposable(_asset.contractAddress);

        (bytes32 fingerprint) = abi.decode(_asset.extra, (bytes32));

        if (!composable.verifyFingerprint(_asset.value, abi.encode(fingerprint))) {
            revert InvalidFingerprint();
        }

        composable.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }

    function _transferERC721CollectionItem(Asset memory _asset, address _signer, address _caller) private {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        if (creator != _signer && creator != _caller) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }

    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }
}
