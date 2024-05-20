// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Verifications} from "src/common/Verifications.sol";
import {MarketplaceTypesHashing} from "src/marketplace/MarketplaceTypesHashing.sol";

/// @notice Main Marketplace asbtract contract that contains the logic to validate and accept Trades.
abstract contract Marketplace is Verifications, MarketplaceTypesHashing, Pausable, ReentrancyGuard {
    /// @notice Trade ids that have been already used.
    /// Trade ids are composed by hashing:
    /// Salt + Caller + Received Assets (Contract Address + Value)
    mapping(bytes32 => bool) public usedTradeIds;

    /// @dev The event is emitted with the hashed signature so it can be identified off chain.
    event Traded(address indexed _caller, bytes32 indexed _signature);

    error UsedTradeId();

    /// @notice Pauses the contract so no new trades can be accepted.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract to resume normal operations.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Revokes a signature so it cannot be used anymore.
    /// The caller must be the signer of the signature.
    /// @param _trades The list of Trade signatures to cancel.
    function cancelSignature(Trade[] calldata _trades) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            _verifyTradeSignature(trade, caller);

            _cancelSignature(keccak256(trade.signature));
        }
    }

    /// @notice Accept a list of Trades.
    /// @param _trades The list of Trades to accept.
    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);

            _accept(_trades[i], caller);
        }
    }

    /// @notice Returns the trade id for a given Trade.
    /// @param _trade The Trade to get the id from.
    /// @param _caller The address that called the contract.
    ///
    /// @dev The trade id is composed of hashing the following values:
    /// Salt + Caller + Received Assets (Contract Address + Value)
    function getTradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.checks.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

    /// @dev Accepts a Trade.
    /// This function is internal to allow child contracts to using in their own accept function.
    /// Does not perform any checks, only transfers the assets and emits the Traded event.
    function _accept(Trade memory _trade, address _caller) internal {
        Trade memory modifiedTrade = _modifyTrade(_trade);

        bytes32 hashedSignature = keccak256(modifiedTrade.signature);
        address signer = modifiedTrade.signer;

        emit Traded(_caller, hashedSignature);

        _transferAssets(modifiedTrade.sent, signer, _caller, signer, _caller);
        _transferAssets(modifiedTrade.received, _caller, signer, signer, _caller);
    }

    /// @dev Verifies that the Trade passes all checks and the signature is valid.
    function _verifyTrade(Trade memory _trade, address _caller) internal {
        bytes32 hashedSignature = keccak256(_trade.signature);
        address signer = _trade.signer;
        bytes32 tradeId = getTradeId(_trade, _caller);
        uint256 currentSignatureUses = signatureUses[hashedSignature];

        if (usedTradeIds[tradeId]) {
            revert UsedTradeId();
        }

        _verifyChecks(_trade.checks, hashedSignature, currentSignatureUses, signer, _caller);
        _verifyTradeSignature(_trade, signer);

        if (currentSignatureUses + 1 == _trade.checks.uses) {
            usedTradeIds[tradeId] = true;
        }

        signatureUses[hashedSignature]++;
    }

    /// @dev Verifies that the Trade signature is valid.
    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        _verifySignature(_hashTrade(_trade), _trade.signature, _signer);
    }

    /// @dev Transfers all the provided assets using the overriden _transferAsset function.
    /// Updates all the asset beneficiaries to the provided _to address in case the original beneficiary is the 0 address.
    function _transferAssets(Asset[] memory _assets, address _from, address _to, address _signer, address _caller) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from, _signer, _caller);
        }
    }

    /// @dev Allows the child contract to update the Trade before accepting it.
    function _modifyTrade(Trade memory _trade) internal view virtual returns (Trade memory) {
        return _trade; // Override
    }

    /// @dev Allows the child contract to handle the transfer of assets.
    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal virtual {
        // Override
    }
}
