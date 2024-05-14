// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {EIP712} from "src/common/EIP712.sol";
import {NativeMetaTransaction} from "src/common/NativeMetaTransaction.sol";
import {ICollection} from "src/marketplace/interfaces/ICollection.sol";
import {MarketplaceWithCouponManager} from "src/marketplace/MarketplaceWithCouponManager.sol";
import {DecentralandMarketplacePolygonAssetTypes} from "src/marketplace/DecentralandMarketplacePolygonAssetTypes.sol";
import {IRoyaltiesManager} from "src/marketplace/interfaces/IRoyaltiesManager.sol";
import {FeeCollector} from "src/marketplace/FeeCollector.sol";

/// @notice Decentraland Marketplace contract for the Polygon network assets. MANA, Wearables, Emotes, etc.
contract DecentralandMarketplacePolygon is
    DecentralandMarketplacePolygonAssetTypes,
    MarketplaceWithCouponManager,
    NativeMetaTransaction,
    FeeCollector
{
    /// @notice The royalties manager contract. Used to get the royalties receiver for collection nft trades.
    IRoyaltiesManager public royaltiesManager;

    /// @notice The rate of the royalties to be sent to the royalties receiver.
    uint256 public royaltiesRate;

    event RoyaltiesManagerUpdated(address indexed _caller, address indexed _royaltiesManager);
    event RoyaltiesRateUpdated(address indexed _caller, uint256 _royaltiesRate);

    error NotCreator();
    error NoRoyaltiesReceiver();

    /// @param _owner The owner of the contract.
    /// @param _couponManager The address of the coupon manager contract.
    /// @param _feeCollector The address that will receive erc20 fees.
    /// @param _feeRate The rate of the fee. 25_000 is 2.5%
    /// @param _royaltiesManager The address of the royalties manager contract.
    /// @param _royaltiesRate The rate of the royalties. 25_000 is 2.5%
    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate, address _royaltiesManager, uint256 _royaltiesRate)
        Ownable(_owner)
        MarketplaceWithCouponManager(_couponManager)
        FeeCollector(_feeCollector, _feeRate)
        EIP712("DecentralandMarketplacePolygon", "1.0.0")
    {
        _updateRoyaltiesManager(_royaltiesManager);
        _updateRoyaltiesRate(_royaltiesRate);
    }

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

    /// @notice Updates the royalties manager address.
    /// @param _royaltiesManager The new royalties manager address.
    function updateRoyaltiesManager(address _royaltiesManager) external onlyOwner {
        _updateRoyaltiesManager(_royaltiesManager);
    }

    /// @notice Updates the royalties rate.
    /// @param _royaltiesRate The new royalties rate.
    function updateRoyaltiesRate(uint256 _royaltiesRate) external onlyOwner {
        _updateRoyaltiesRate(_royaltiesRate);
    }

    /// @dev Overriden Marketplace function to transfer assets.
    /// Handles the transfer of ERC20 with royalties and fees, ERC721 and Collection Items.
    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal override {
        uint256 assetType = _asset.assetType;

        if (assetType == ASSET_TYPE_ERC20) {
            _transferERC20WithCollectorFee(_asset, _from, feeCollector, feeRate);
        } else if (assetType == ASSET_TYPE_ERC721) {
            _transferERC721(_asset, _from);
        } else if (assetType == ASSET_TYPE_COLLECTION_ITEM) {
            _transferERC721CollectionItem(_asset, _signer, _caller);
        } else if (assetType == ASSET_TYPE_ERC20_WITH_ROYALTIES) {
            _transferERC20WithRoyalties(_asset, _signer);
        } else {
            revert UnsupportedAssetType(assetType);
        }
    }

    /// @dev Transfers ERC721 assets.
    function _transferERC721(Asset memory _asset, address _from) private {
        IERC721 erc721 = IERC721(_asset.contractAddress);

        erc721.safeTransferFrom(_from, _asset.beneficiary, _asset.value);
    }

    /// @dev Mints collection items to the beneficiary.
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

    /// @dev Transfers ERC20 tokens.
    /// Transfers a percentage of the value to the royalties receiver.
    function _transferERC20WithRoyalties(Asset memory _asset, address _from) private {
        (address contractAddress, uint256 tokenId) = abi.decode(_asset.extra, (address, uint256));
        address royaltiesReceiver = royaltiesManager.getRoyaltiesReceiver(contractAddress, tokenId);

        if (royaltiesReceiver == address(0)) {
            revert NoRoyaltiesReceiver();
        }

        _transferERC20WithCollectorFee(_asset, _from, royaltiesReceiver, royaltiesRate);
    }

    /// @dev Updates the royalties manager address.
    /// @param _royaltiesManager The new royalties manager address.
    function _updateRoyaltiesManager(address _royaltiesManager) internal {
        royaltiesManager = IRoyaltiesManager(_royaltiesManager);

        emit RoyaltiesManagerUpdated(_msgSender(), _royaltiesManager);
    }

    /// @dev Updates the royalties rate.
    /// @param _royaltiesRate The new royalties rate.
    function _updateRoyaltiesRate(uint256 _royaltiesRate) internal {
        royaltiesRate = _royaltiesRate;

        emit RoyaltiesRateUpdated(_msgSender(), _royaltiesRate);
    }

    /// @dev Overriden function to obtain the caller of the transaction.
    /// The contract accepts meta transactions, so the caller could be the signer of the meta transaction or the real caller depending the situation.
    function _msgSender() internal view override returns (address) {
        return _getMsgSender();
    }
}
