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
    // keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH = 0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;

    // keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;

    // keccak256("Trade(Checks checks,AssetWithoutBeneficiary[] sent,Asset[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant TRADE_TYPE_HASH = 0x6a9beda065389ec62818727007cff89069ad7a2ae71cc72612ba2b563a009bfe;

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

    function _hashTrade(Trade memory _trade) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRADE_TYPE_HASH,
                keccak256(abi.encodePacked(_hashChecks(_trade.checks))),
                keccak256(abi.encodePacked(_hashAssetsWithoutBeneficiary(_trade.sent))),
                keccak256(abi.encodePacked(_hashAssets(_trade.received)))
            )
        );
    }

    function _hashAssetsWithoutBeneficiary(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] =
                keccak256(abi.encode(ASSET_WO_BENEFICIARY_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, keccak256(asset.extra)));
        }

        return hashes;
    }

    function _hashAssets(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] =
                keccak256(abi.encode(ASSET_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, keccak256(asset.extra), asset.beneficiary));
        }

        return hashes;
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
