// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "src/common/EIP712.sol";
import {IComposable} from "src/marketplace/IComposable.sol";
import {MarketplaceWithCouponManager} from "src/marketplace/MarketplaceWithCouponManager.sol";
import {DecentralandMarketplaceEthereumAssetTypes} from "src/marketplace/DecentralandMarketplaceEthereumAssetTypes.sol";

contract DecentralandMarketplaceEthereum is DecentralandMarketplaceEthereumAssetTypes, MarketplaceWithCouponManager {
    address public feeCollector;
    uint256 public feeRate;

    error InvalidFingerprint();

    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate)
        Ownable(_owner)
        EIP712("DecentralandMarketplaceEthereum", "1.0.0")
        MarketplaceWithCouponManager(_couponManager)
    {
        feeCollector = _feeCollector;
        feeRate = _feeRate;
    }

    function _transferAsset(Asset memory _asset, address _from, address, address) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20) {
            _transferERC20(_asset, _from);
        } else if (assetType == ASSET_TYPE_ERC721) {
            _transferERC721(_asset, _from);
        } else {
            revert UnsupportedAssetType(assetType);
        }
    }

    function _transferERC20(Asset memory _asset, address _from) private {
        uint256 originalValue = _asset.value;
        uint256 fee = originalValue * feeRate / 1_000_000;

        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, _asset.beneficiary, originalValue - fee);
        SafeERC20.safeTransferFrom(IERC20(_asset.contractAddress), _from, feeCollector, fee);
    }

    function _transferERC721(Asset memory _asset, address _from) private {
        IComposable erc721 = IComposable(_asset.contractAddress);

        if (erc721.supportsInterface(erc721.verifyFingerprint.selector)) {
            (bytes32 fingerprint) = abi.decode(_asset.extra, (bytes32));

            if (!erc721.verifyFingerprint(_asset.value, abi.encode(fingerprint))) {
                revert InvalidFingerprint();
            }
        }

        erc721.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }
}
