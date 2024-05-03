// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {EIP712} from "./external/EIP712.sol";
import {Verifications} from "./common/Verifications.sol";

/// @notice Marketplace contract that allows the execution of signed Trades.
/// Users can sign a Trade indicating which assets are to be traded. Another user can the accept the Trade using the signature, executing the exchange if all checks are valid.
abstract contract Marketplace is Verifications, Pausable, ReentrancyGuard {
    // keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH = 0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;

    // keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;

    // keccak256("Trade(Checks checks,AssetWithoutBeneficiary[] sent,Asset[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant TRADE_TYPE_HASH = 0x6a9beda065389ec62818727007cff89069ad7a2ae71cc72612ba2b563a009bfe;

    // keccak256("Modifier(Checks checks,uint256 modifierType,bytes data)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant MODIFIER_TYPE_HASH = 0x5f8554ec0f2e85d95d0a1c8b4b287d433c736606ae28b55167c9bc7caa0c4a19;

    /// @notice Tracks if a Trade has already been used.
    /// @dev Trade Ids are composed from the result of hashing the salt, the msg.sender and the received assets.
    ///
    /// This allows connecting Trades, allowing a way in which after one Trade is accepted, all those related Trades can be automatically invalidated.
    ///
    /// For example:
    ///
    /// User A wants to make an Auction to sell Asset A
    ///
    /// User B signs a Trade to buy Asset A from User A for 100 DAI
    /// User C signs a Trade to buy Asset A from User A for 200 DAI
    /// User D signs a Trade to buy Asset A from User A for 300 DAI (All these use the same salt)
    ///
    /// User A accepts the Trade from User D
    ///
    /// The Trades signed by User B and User C are automatically invalidated, and User A can't accept them anymore.
    ///
    /// NOTE: To make the best use out of this feature, it is recommended to set only the address of the user that can accept the Trade in the allowed field.
    /// On the previous example, if the allowed field was empty or had more than just User A, other addresses would be able to accept those Trades.
    ///
    /// NOTE: Trade Ids are recorded only when a signature has been used the amount of times specified in the Trade.
    /// This means that if a Trade has a uses value of 0, the Trade Id will never be recorded.
    /// Or if the Trades has 100 uses, the Trade Id will only be recorded after the 100th use.
    mapping(bytes32 => bool) public usedTradeIds;

    /// @dev Schema for a traded asset.
    /// @param assetType - The type of asset being traded. Useful for the implementation to know how to handle the asset.
    /// @param contractAddress - The address of the contract that holds the asset.
    /// @param value - Depends on the asset. It could be the amount for ERC20s or the tokenId for ERC721s.
    /// @param beneficiary - The address that will receive the asset. If the address is 0x0, the beneficiary will be the signer or the caller accordingly.
    /// @param extra - Extra data that the implementation might need to handle the asset. Like the fingerprint on ComposableERC721 nfts.
    /// @param unverifiedExtra - Extra data that is not included in the signature validation. Useful for data that is only important for the caller and not the signer.
    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        address beneficiary;
        bytes extra;
        bytes unverifiedExtra;
    }

    /// @dev Schema for a Trade.
    /// @param signer - The address of the user that signed the Trade.
    /// @param signature - The signature of the Trade.
    /// @param checks - The checks that need to be validated to accept the Trade.
    /// @param sent - An array of assets that the signer is sending in the Trade.
    /// @param received - An array of assets that the signer is receiving in the Trade.
    struct Trade {
        address signer;
        bytes signature;
        Checks checks;
        Asset[] sent;
        Asset[] received;
    }

    /// @dev Schema for a Trade modifier.
    /// @param signature - The signature of the modifier.
    /// @param checks - The checks that need to be validated to accept the modifier.
    /// @param modifierType - The type of modifier.
    /// @param data - The data of the modifier.
    struct Modifier {
        bytes signature;
        Checks checks;
        uint256 modifierType;
        bytes data;
    }

    event Traded(address indexed _caller, bytes32 indexed _signature);

    error UsedTradeId();
    error TradesAndModifiersLengthMismatch();

    constructor(address _owner) EIP712("Marketplace", "1.0.0") Ownable(_owner) {}

    /// @notice The owner can pause the contract to prevent some external functions from being called.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice The owner can unpause the contract to resume its normal behavior.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Signers can cancel their Trade signatured to prevent them from being used.
    /// @param _trades - An array of Trades to be cancelled.
    function cancelSignature(Trade[] calldata _trades) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            _verifyTradeSignature(trade, caller);

            bytes32 hashedSignature = keccak256(trade.signature);

            _cancelSignature(hashedSignature);
        }
    }

    /// @notice Accepts a Trade if all checks are valid.
    /// @param _trades - An array of Trades to be accepted.
    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            _accept(_trades[i], caller);
        }
    }

    /// @notice Accepts a Trade after applying a Modification.
    /// @param _trades - An array of Trades to be accepted.
    /// @param _modifiers - An array of Modifiers to be applied to the Trades.
    function acceptWithModifier(Trade[] calldata _trades, Modifier[] calldata _modifiers) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        if (_trades.length != _modifiers.length) {
            revert TradesAndModifiersLengthMismatch();
        }

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];
            Modifier memory mod = _modifiers[i];

            bytes32 hashedSignature = keccak256(mod.signature);
            address signer = trade.signer;
            uint256 currentSignatureUses = signatureUses[hashedSignature];

            _verifyChecks(mod.checks, currentSignatureUses, signer, caller);
            _verifyModifierSignature(mod, signer);

            signatureUses[hashedSignature]++;

            _applyModifier(trade, mod);
            _accept(trade, caller);
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

    /// @dev Generates a trade id from a Trade's salt, the msg.sender of the transaction, and the received assets.
    function getTradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.checks.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

    /// @dev Verifies that the signature provided in the Trade is valid.
    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        _verifySignature(_hashTrade(_trade), _trade.signature, _signer);
    }

    /// @dev Verifies that the signature provided in the Modifier is valid.
    function _verifyModifierSignature(Modifier memory _modifier, address _signer) private view {
        _verifySignature(_hashModifier(_modifier), _modifier.signature, _signer);
    }

    /// @dev Hashes a Trade according to the EIP712 standard.
    /// Used to validate that the signer provided in the Trade is the one that signed it.
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

    /// @dev Hashes an array of assets without the beneficiary.
    function _hashAssetsWithoutBeneficiary(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] =
                keccak256(abi.encode(ASSET_WO_BENEFICIARY_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, keccak256(asset.extra)));
        }

        return hashes;
    }

    /// @dev Hashes an array of assets.
    function _hashAssets(Asset[] memory _assets) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_assets.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            Asset memory asset = _assets[i];

            hashes[i] =
                keccak256(abi.encode(ASSET_TYPE_HASH, asset.assetType, asset.contractAddress, asset.value, keccak256(asset.extra), asset.beneficiary));
        }

        return hashes;
    }

    function _hashModifier(Modifier memory _modifier) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MODIFIER_TYPE_HASH, keccak256(abi.encodePacked(_hashChecks(_modifier.checks))), _modifier.modifierType, keccak256(_modifier.data)
            )
        );
    }

    /// @dev Transfers an array of assets from one address to another.
    /// If the asset has a defined beneficiary, the asset will be transferred to the beneficiary instead of the _to address.
    function _transferAssets(Asset[] memory _assets, address _from, address _to, address _signer) private {
        for (uint256 i = 0; i < _assets.length; i++) {
            Asset memory asset = _assets[i];

            if (asset.beneficiary == address(0)) {
                asset.beneficiary = _to;
            }

            _transferAsset(asset, _from, _signer);
        }
    }

    /// @dev This function needs to be implemented by the child contract to handle the transfer of the assets.
    /// @param _asset - The asset to be transferred.
    /// @param _from - The address that is sending the asset.
    /// @param _signer - The signer of the Trade.
    function _transferAsset(Asset memory _asset, address _from, address _signer) internal virtual;

    /// @dev This function needs to be implemented by the child contract to handle the application of the modifier.
    /// @param _trade - The Trade to be modified.
    /// @param _modifier - The modifier to be applied.
    function _applyModifier(Trade memory _trade, Modifier memory _modifier) internal virtual;
}
