// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {EIP712} from "./external/EIP712.sol";
import {Verifications} from "./common/Verifications.sol";
import {Modifiers} from "./Modifiers.sol";

/// @notice Marketplace contract that allows the execution of signed Trades.
/// Users can sign a Trade indicating which assets are to be traded. Another user can the accept the Trade using the signature, executing the exchange if all checks are valid.
abstract contract Marketplace is Verifications, Pausable, ReentrancyGuard {
    Modifiers public modifiers;
    mapping(bytes32 => bool) public usedTradeIds;

    event Traded(address indexed _caller, bytes32 indexed _signature);

    error UsedTradeId();
    error TradesAndModifiersLengthMismatch();

    constructor(address _owner, address _modifiers) EIP712("Marketplace", "1.0.0") Ownable(_owner) {
        modifiers = Modifiers(_modifiers);
    }

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
            _accept(_trades[i], caller);
        }
    }

    function acceptWithModifier(Trade[] calldata _trades, Modifier[] calldata _modifiers) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _modifiers.length) {
            revert TradesAndModifiersLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            _accept(modifiers.applyModifier(_trades[i], _modifiers[i]), caller);
        }
    }

    function _accept(Trade memory _trade, address _caller) private {
        bytes32 hashedSignature = keccak256(_trade.signature);
        address signer = _trade.signer;
        bytes32 tradeId = getTradeId(_trade, _caller);
        uint256 currentSignatureUses = signatureUses[hashedSignature];

        if (cancelledSignatures[hashedSignature]) {
            revert CancelledSignature();
        }

        if (usedTradeIds[tradeId]) {
            revert UsedTradeId();
        }

        _verifyChecks(_trade.checks, currentSignatureUses, signer, _caller);
        _verifyTradeSignature(_trade, signer);

        if (currentSignatureUses + 1 == _trade.checks.uses) {
            usedTradeIds[tradeId] = true;
        }

        signatureUses[hashedSignature]++;

        emit Traded(_caller, hashedSignature);

        _transferAssets(_trade.sent, signer, _caller, signer);
        _transferAssets(_trade.received, _caller, signer, signer);
    }

    function getTradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.checks.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        _verifySignature(_hashTrade(_trade), _trade.signature, _signer);
    }

    function _transferAssets(Asset[] memory _assets, address _from, address _to, address _signer) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from, _signer);
        }
    }

    function _transferAsset(Asset memory _asset, address _from, address _signer) internal virtual;
}
