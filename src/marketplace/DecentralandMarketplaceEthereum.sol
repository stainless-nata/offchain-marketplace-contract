// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "src/common/EIP712.sol";
import {IComposable} from "src/marketplace/interfaces/IComposable.sol";
import {MarketplaceWithCouponManager} from "src/marketplace/MarketplaceWithCouponManager.sol";
import {DecentralandMarketplaceEthereumAssetTypes} from "src/marketplace/DecentralandMarketplaceEthereumAssetTypes.sol";
import {FeeCollector} from "src/marketplace/FeeCollector.sol";

/// @notice Decentraland Marketplace contract for the Ethereum network assets. MANA, LAND, Estates, Names, etc.
contract DecentralandMarketplaceEthereum is DecentralandMarketplaceEthereumAssetTypes, MarketplaceWithCouponManager, FeeCollector {
    error InvalidFingerprint();

    /// @param _owner The owner of the contract.
    /// @param _couponManager The address of the coupon manager contract.
    /// @param _feeCollector The address that will receive erc20 fees.
    /// @param _feeRate The rate of the fee. 25_000 is 2.5%
    constructor(
        address _owner,
        address _couponManager,
        address _feeCollector,
        uint256 _feeRate
    ) 
        EIP712("DecentralandMarketplaceEthereum", "1.0.0")
        Ownable(_owner)
        MarketplaceWithCouponManager(_couponManager)
        FeeCollector(_feeCollector, _feeRate)
    {}

    /// @notice Updates the fee collector address.
    /// @param _feeCollector The new fee collector address.
    function updateFeeCollector(address _feeCollector) external onlyOwner {
        _updateFeeCollector(_msgSender(), _feeCollector);
    }

    /// @notice Updates the fee rate.
    /// @param _feeRate The new fee rate.
    function updateFeeRate(uint256 _feeRate) external onlyOwner {
        _updateFeeRate(_msgSender(), _feeRate);
    }

    /// @dev Overriden Marketplace function to transfer assets.
    /// Handles the transfer of ERC20 and ERC721 assets.
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

    /// @dev Transfers ERC20 assets to the beneficiary.
    /// A part of the value is taken as a fee and transferred to the fee collector.
    function _transferERC20(Asset memory _asset, address _from) internal {
        uint256 originalValue = _asset.value;
        uint256 fee = originalValue * feeRate / 1_000_000;

        IERC20 erc20 = IERC20(_asset.contractAddress);

        SafeERC20.safeTransferFrom(erc20, _from, _asset.beneficiary, originalValue - fee);
        SafeERC20.safeTransferFrom(erc20, _from, feeCollector, fee);
    }

    /// @dev Transfers ERC721 assets to the beneficiary.
    /// Takes into account Composable ERC721 contracts like Estates.
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
