// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {EIP712} from "./external/EIP712.sol";

/// @notice Marketplace contract that allows the execution of signed Trades.
/// Users can sign a Trade indicating which assets are to be traded. Another user can the accept the Trade using the signature, executing the exchange if all checks are valid.
abstract contract Marketplace is EIP712, Ownable, Pausable, ReentrancyGuard {
    /// keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH = 0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;
    /// keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;
    /// keccak256("Trade(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,AssetWithoutBeneficiary[] sent,Asset[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant TRADE_TYPE_HASH = 0xb967bcaa9c7a374d193cf0f8af42cb15a1f51f6e94e22610b82c42c7cb93dd86;

    /// @notice The current contract signature index.
    /// Trades need to be signed with the current contract signature index.
    /// The owner of the contract can increase it to invalidate older signatures.
    uint256 public contractSignatureIndex;

    /// @notice The current signer signature index.
    /// Trades need to be signed with the current signer signature index.
    /// Any user can increase their signer index to invalidate their older signatures.
    mapping(address => uint256) public signerSignatureIndex;

    /// @notice How many times a signature has been used.
    /// Depending on the Trade, signatures can be used from 1 to an indefinite amount of times.
    mapping(bytes32 => uint256) public signatureUses;

    /// @notice Tracks if a signature has been manually cancelled by their corresponding signers.
    mapping(bytes32 => bool) public cancelledSignatures;

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
    /// @param extra - Extra data that the implementation might need to handle the asset. Like the data provided on an ERC721 safeTransferFrom calls.
    /// @param beneficiary - The address that will receive the asset. If the address is 0x0, the beneficiary will be the signer or the caller accordingly.
    struct Asset {
        uint256 assetType;
        address contractAddress;
        uint256 value;
        bytes extra;
        address beneficiary;
    }

    /// @dev Schema for a Trade.
    /// @param signer - The address of the user that signed the Trade.
    /// @param signature - The signature of the Trade.
    /// @param uses - How many times the signature can be used. 0 means it can be used indefinitely.
    /// @param expiration - The timestamp when the signature expires.
    /// @param effective - The timestamp when the signature can be used.
    /// @param salt - A random value to make the signature unique.
    /// @param contractSignatureIndex - The contract signature index that was used to sign the Trade.
    /// @param signerSignatureIndex - The signer signature index that was used to sign the Trade.
    /// @param allowed - An array of addresses that are allowed to accept the Trade. An empty array means any address can accept it.
    /// @param sent - An array of assets that the signer is sending in the Trade.
    /// @param received - An array of assets that the signer is receiving in the Trade.
    struct Trade {
        address signer;
        bytes signature;
        uint256 uses;
        uint256 expiration;
        uint256 effective;
        bytes32 salt;
        uint256 contractSignatureIndex;
        uint256 signerSignatureIndex;
        address[] allowed;
        Asset[] sent;
        Asset[] received;
    }

    event ContractSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignerSignatureIndexIncreased(address indexed _caller, uint256 indexed _newValue);
    event SignatureCancelled(address indexed _caller, bytes32 indexed _signature);
    event Traded(address indexed _caller, bytes32 indexed _signature);

    error CancelledSignature();
    error SignatureReuse();
    error UsedTradeId();
    error NotEffective();
    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error Expired();
    error NotAllowed();
    error InvalidSignature();

    constructor(address _owner) EIP712("Marketplace", "1.0.0") Ownable(_owner) {}

    /// @notice The owner can pause the contract to prevent some external functions from being called.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice The owner can unpause the contract to resume its normal behavior.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice The owner can increase the contract signature index to invalidate all Trades signed with a lower index.
    function increaseContractSignatureIndex() external onlyOwner {
        uint256 newIndex = ++contractSignatureIndex;

        emit ContractSignatureIndexIncreased(_msgSender(), newIndex);
    }

    /// @notice Any user can increase their signer signature index to invalidate all Trades signed with a lower index.
    function increaseSignerSignatureIndex() external {
        address caller = _msgSender();

        uint256 newIndex = ++signerSignatureIndex[caller];

        emit SignerSignatureIndexIncreased(caller, newIndex);
    }

    /// @notice Signers can cancel their Trade signatured to prevent them from being used.
    /// @param _trades - An array of Trades to be cancelled.
    function cancelSignature(Trade[] calldata _trades) external {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            _verifyTradeSignature(trade, caller);

            bytes32 hashedSignature = keccak256(trade.signature);

            cancelledSignatures[hashedSignature] = true;

            emit SignatureCancelled(caller, hashedSignature);
        }
    }

    /// @notice Accepts a Trade if all checks are valid.
    /// @param _trades - An array of Trades to be accepted.
    function accept(Trade[] calldata _trades) external whenNotPaused nonReentrant {
        address caller = _msgSender();

        for (uint256 i = 0; i < _trades.length; i++) {
            Trade memory trade = _trades[i];

            bytes32 hashedSignature = keccak256(trade.signature);

            if (cancelledSignatures[hashedSignature]) {
                revert CancelledSignature();
            }

            uint256 storedSignatureUses = signatureUses[hashedSignature]++;

            if (trade.uses > 0 && storedSignatureUses >= trade.uses) {
                revert SignatureReuse();
            }

            bytes32 tradeId = _tradeId(trade, caller);

            if (usedTradeIds[tradeId]) {
                revert UsedTradeId();
            }

            if (trade.effective > block.timestamp) {
                revert NotEffective();
            }

            if (contractSignatureIndex != trade.contractSignatureIndex) {
                revert InvalidContractSignatureIndex();
            }

            address signer = trade.signer;

            if (signerSignatureIndex[signer] != trade.signerSignatureIndex) {
                revert InvalidSignerSignatureIndex();
            }

            if (trade.expiration < block.timestamp) {
                revert Expired();
            }

            address[] memory allowed = trade.allowed;

            uint256 allowedLength = trade.allowed.length;

            if (allowedLength > 0) {
                bool isAllowed = false;

                for (uint256 j = 0; j < allowedLength; j++) {
                    if (allowed[j] == caller) {
                        isAllowed = true;
                        break;
                    }
                }

                if (!isAllowed) {
                    revert NotAllowed();
                }
            }

            _verifyTradeSignature(trade, signer);

            if (storedSignatureUses + 1 == trade.uses) {
                usedTradeIds[tradeId] = true;
            }

            emit Traded(caller, hashedSignature);

            _transferAssets(trade.sent, signer, caller, signer);

            _transferAssets(trade.received, caller, signer, signer);
        }
    }

    /// @dev Hashes a Trade according to the EIP712 standard.
    /// Used to validate that the signer provided in the Trade is the one that signed it.
    function _hashTrade(Trade memory _trade) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRADE_TYPE_HASH,
                _trade.uses,
                _trade.expiration,
                _trade.effective,
                _trade.salt,
                _trade.contractSignatureIndex,
                _trade.signerSignatureIndex,
                keccak256(abi.encodePacked(_trade.allowed)),
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

    /// @dev Generates a trade id from a Trade's salt, the msg.sender of the transaction, and the received assets.
    function _tradeId(Trade memory _trade, address _caller) public pure returns (bytes32) {
        bytes32 tradeId = keccak256(abi.encodePacked(_trade.salt, _caller));

        for (uint256 i = 0; i < _trade.received.length; i++) {
            Asset memory asset = _trade.received[i];

            tradeId = keccak256(abi.encodePacked(tradeId, asset.contractAddress, asset.value));
        }

        return tradeId;
    }

    /// @dev Verifies that the signature provided in the Trade is valid.
    function _verifyTradeSignature(Trade memory _trade, address _signer) private view {
        if (!SignatureChecker.isValidSignatureNow(_signer, _hashTypedDataV4(_hashTrade(_trade)), _trade.signature)) {
            revert InvalidSignature();
        }
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
}
