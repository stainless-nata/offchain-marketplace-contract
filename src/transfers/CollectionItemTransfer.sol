// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Context} from "lib/openzeppelin-contracts/contracts/utils/Context.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICollection} from "../interfaces/ICollection.sol";
import {ICollectionStore} from "../interfaces/ICollectionStore.sol";
import {Marketplace} from "../Marketplace.sol";

abstract contract CollectionItemTransfer is Context {
    /// @dev The item id that represents an empty item.
    /// This is because the item id 0 represents the firt item of a collection.
    uint256 private constant EMPTY_ITEM_ID = 1337;

    /// @dev The type of discounts that can be applied.
    /// Flat will subtract the discount from the price.
    /// Rate will discount a % from the price.
    uint256 private constant DISCOUNT_TYPE_FLAT = 0;
    uint256 private constant DISCOUNT_TYPE_RATE = 1;

    IERC20 private immutable collectionStoreErc20;
    uint256 private immutable collectionStoreFeeRate;
    uint256 private immutable collectionStoreFeeRateBase;
    address private immutable collectionStoreFeeCollector;

    error NotCreator();
    error DifferentCollectionContractAddress();
    error DifferentCollectionItemId();
    error InvalidPrice();
    error InvalidDiscountType();

    constructor(ICollectionStore _collectionStore) {
        collectionStoreErc20 = _collectionStore.acceptedToken();
        collectionStoreFeeRate = _collectionStore.fee();
        collectionStoreFeeRateBase = _collectionStore.BASE_FEE();
        collectionStoreFeeCollector = _collectionStore.feeOwner();
    }

    function _transferCollectionItem(Marketplace.Asset memory _asset, address _signer) internal {
        ICollection collection = ICollection(_asset.contractAddress);

        address creator = collection.creator();

        if (creator != _signer && creator != _msgSender()) {
            revert NotCreator();
        }

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        collection.issueTokens(beneficiaries, itemIds);
    }

    function _transferCollectionItemWithDiscount(Marketplace.Asset memory _asset, address _signer) internal {
        // Extract the item that the user wants to buy.
        (address contractAddress, uint256 itemId, uint256 price) = abi.decode(_asset.unverifiedExtra, (address, uint256, uint256));

        // Extract the extra Trade data defined by the signer.
        // The discountedItemId defined by the signer is only useful if the contract address for the collection is provided.
        // If an item id is provided and the collection address is address(0), it will be ignored.
        (uint256 discountType, uint256 discountedItemId) = abi.decode(_asset.extra, (uint256, uint256));

        // The signer can define on what level the discount is applied.
        // - If the contract address is address(0) the discount is for all the _signer's collections.
        // - If the contract address is defined the discount is for a specific collection.
        // - If the item id is defined the discount is for a specific item only.
        if (_asset.contractAddress != address(0)) {
            if (_asset.contractAddress != contractAddress) {
                revert DifferentCollectionContractAddress();
            }

            if (discountedItemId != EMPTY_ITEM_ID && discountedItemId != itemId) {
                revert DifferentCollectionItemId();
            }
        }

        ICollection collection = ICollection(contractAddress);

        // Only the creator of the collection can apply discounts.
        if (collection.creator() != _signer) {
            revert NotCreator();
        }

        // Get the price of the collection.
        (,,, uint256 itemPrice, address itemBeneficiary,,) = collection.items(itemId);

        // If the price the original price the caller wants to pay is different from the price of the item, revert.
        // This is to prevent the signer from updating the price beforehand without the caller noticing.
        if (price != itemPrice) {
            revert InvalidPrice();
        }

        uint256 priceWithDiscount;

        // Apply the discount to the price of the item.
        if (discountType == DISCOUNT_TYPE_FLAT) {
            priceWithDiscount = price - _asset.value;
        } else if (discountType == DISCOUNT_TYPE_RATE) {
            priceWithDiscount = price - (price * _asset.value / collectionStoreFeeRateBase);
        } else {
            revert InvalidDiscountType();
        }

        address caller = _msgSender();

        // Get how much from the discounted price has to go to the fee owner.
        uint256 fee = priceWithDiscount * collectionStoreFeeRate / collectionStoreFeeRateBase;

        // Make the caller pay for the item with the discounted price.
        // Also sends the fee to the feeOwner.
        SafeERC20.safeTransferFrom(collectionStoreErc20, caller, itemBeneficiary, priceWithDiscount - fee);
        SafeERC20.safeTransferFrom(collectionStoreErc20, caller, collectionStoreFeeCollector, fee);

        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = _asset.beneficiary;

        uint256[] memory itemIds = new uint256[](1);
        itemIds[0] = _asset.value;

        // Issue the item to the beneficiary defined by the caller.
        collection.issueTokens(beneficiaries, itemIds);
    }
}
