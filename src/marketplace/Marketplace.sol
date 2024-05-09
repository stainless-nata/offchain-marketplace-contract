// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Verifications} from "src/common/Verifications.sol";
import {MarketplaceTypesHashing} from "src/marketplace/MarketplaceTypesHashing.sol";

abstract contract Marketplace is Verifications, MarketplaceTypesHashing, Pausable, ReentrancyGuard {
    mapping(bytes32 => bool) public usedTradeIds;

    event Traded(address indexed _caller, bytes32 indexed _signature);

    error UsedTradeId();

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function cancelSignature(Trade[] calldata _trades) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];
            _verifyTradeSignature(trade, caller);
            bytes32 hashedSignature = keccak256(trade.signature);
            _cancelSignature(hashedSignature);
        }
    }

    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            _verifyTrade(_trades[i], caller);
            _accept(_trades[i], caller);
        }
    }

    function _accept(Trade memory _trade, address _caller) internal {
        bytes32 hashedSignature = keccak256(_trade.signature);
        address signer = _trade.signer;

        emit Traded(_caller, hashedSignature);

        _transferAssets(_trade.sent, signer, _caller, signer, _caller);
        _transferAssets(_trade.received, _caller, signer, signer, _caller);
    }

    function getTradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.checks.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

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

    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        _verifySignature(_hashTrade(_trade), _trade.signature, _signer);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to, address _signer, address _caller) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from, _signer, _caller);
        }
    }

    function _transferAsset(Asset memory _asset, address _from, address _signer, address _caller) internal virtual {
        // Override
    }
}
