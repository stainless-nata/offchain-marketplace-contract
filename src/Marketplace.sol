// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {EIP712} from "./external/EIP712.sol";

/// @notice Marketplace contract that allows the execution of signed Trades.
/// Users can sign a Trade indicating which assets are to be traded. Another user can the accept the Trade using the signature, executing the exchange if all checks are valid.
abstract contract Marketplace is EIP712, Ownable, Pausable, ReentrancyGuard {
    // keccak256("AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)")
    bytes32 private constant ASSET_WO_BENEFICIARY_TYPE_HASH = 0x7be57332caf51c5f0f0fa0e7c362534d22d81c0bee1ffac9b573acd336e032bd;

    // keccak256("Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)")
    bytes32 private constant ASSET_TYPE_HASH = 0xe5f9e1ebc316d1bde562c77f47da7dc2cccb903eb04f9b82e29212b96f9e57e1;

    // keccak256("ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant EXTERNAL_CHECK_TYPE_HASH = 0xdf361982fbc6415130c9d78e2e25ec087cf4812d4c0714d41cc56537ee15ac24;

    // keccak256("Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant CHECKS_TYPE_HASH = 0x2f962336c5429beb00c5ed44703aebcb2aaf2600ba276ef74dc82ca3bc073651;

    // keccak256("Trade(Checks checks,AssetWithoutBeneficiary[] sent,Asset[] received)Asset(uint256 assetType,address contractAddress,uint256 value,bytes extra,address beneficiary)AssetWithoutBeneficiary(uint256 assetType,address contractAddress,uint256 value,bytes extra)Checks(uint256 uses,uint256 expiration,uint256 effective,bytes32 salt,uint256 contractSignatureIndex,uint256 signerSignatureIndex,address[] allowed,ExternalCheck[] externalChecks)ExternalCheck(address contractAddress,bytes4 selector,uint256 value,bool required)")
    bytes32 private constant TRADE_TYPE_HASH = 0x6a9beda065389ec62818727007cff89069ad7a2ae71cc72612ba2b563a009bfe;

    /// @dev Selectors used to identify the functions to be called on external checks.
    /// bytes4(keccak256("balanceOf(address)"))
    bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231;
    /// bytes4(keccak256("ownerOf(uint256)"))
    bytes4 private constant OWNER_OF_SELECTOR = 0x6352211e;

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

    /// @dev Schema for an external check.
    /// @param contractAddress - The address of the contract that holds the function used to perform a check.
    /// @param selector - The selector of the function to be called.
    /// @param value - Numeric value used on checks. It is the tokenId for ownerOf checks, or the min amount for balanceOf checks.
    /// @param required - If the check is required or optional.
    ///
    /// Read more about external checks in the _verifyExternalChecks function.
    struct ExternalCheck {
        address contractAddress;
        bytes4 selector;
        uint256 value;
        bool required;
    }

    /// @dev Schema for base signature validation params.
    /// @param uses - How many times the signature can be used. 0 means it can be used indefinitely.
    /// @param expiration - The timestamp when the signature expires.
    /// @param effective - The timestamp when the signature can be used.
    /// @param salt - A random value to make the signature unique.
    /// @param contractSignatureIndex - The contract signature index that was used to sign the Trade.
    /// @param signerSignatureIndex - The signer signature index that was used to sign the Trade.
    /// @param allowed - An array of addresses that are allowed to accept the Trade. An empty array means any address can accept it.
    /// @param externalChecks - An array of external checks that need to be validated to accept the Trade. An empty array means no checks are required.
    struct Checks {
        uint256 uses;
        uint256 expiration;
        uint256 effective;
        bytes32 salt;
        uint256 contractSignatureIndex;
        uint256 signerSignatureIndex;
        address[] allowed;
        ExternalCheck[] externalChecks;
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
    error ExternalChecksFailed();
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
            address signer = trade.signer;
            bytes32 tradeId = getTradeId(trade, caller);
            uint256 currentSignatureUses = signatureUses[hashedSignature];

            if (cancelledSignatures[hashedSignature]) {
                revert CancelledSignature();
            }

            if (usedTradeIds[tradeId]) {
                revert UsedTradeId();
            }

            _verifyChecks(trade.checks, currentSignatureUses, signer, caller);
            _verifyTradeSignature(trade, signer);

            if (currentSignatureUses + 1 == trade.checks.uses) {
                usedTradeIds[tradeId] = true;
            }

            signatureUses[hashedSignature]++;

            emit Traded(caller, hashedSignature);

            _transferAssets(trade.sent, signer, caller, signer);
            _transferAssets(trade.received, caller, signer, signer);
        }
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

    function _hashChecks(Checks memory _checks) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CHECKS_TYPE_HASH,
                _checks.uses,
                _checks.expiration,
                _checks.effective,
                _checks.salt,
                _checks.contractSignatureIndex,
                _checks.signerSignatureIndex,
                keccak256(abi.encodePacked(_checks.allowed)),
                keccak256(abi.encodePacked(_hashExternalChecks(_checks.externalChecks)))
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

    function _hashExternalChecks(ExternalCheck[] memory _externalChecks) private pure returns (bytes32[] memory) {
        bytes32[] memory hashes = new bytes32[](_externalChecks.length);

        for (uint256 i = 0; i < hashes.length; i++) {
            ExternalCheck memory externalCheck = _externalChecks[i];

            hashes[i] = keccak256(
                abi.encode(
                    EXTERNAL_CHECK_TYPE_HASH, externalCheck.contractAddress, externalCheck.selector, externalCheck.value, externalCheck.required
                )
            );
        }

        return hashes;
    }

    function _verifyChecks(Checks memory _checks, uint256 _currentSignatureUses, address _signer, address _caller) private view {
        if (_checks.uses > 0 && _currentSignatureUses >= _checks.uses) {
            revert SignatureReuse();
        }

        if (_checks.effective > block.timestamp) {
            revert NotEffective();
        }

        if (contractSignatureIndex != _checks.contractSignatureIndex) {
            revert InvalidContractSignatureIndex();
        }

        if (signerSignatureIndex[_signer] != _checks.signerSignatureIndex) {
            revert InvalidSignerSignatureIndex();
        }

        if (_checks.expiration < block.timestamp) {
            revert Expired();
        }

        if (_checks.allowed.length > 0) {
            _verifyAllowed(_checks.allowed, _caller);
        }

        if (_checks.externalChecks.length > 0) {
            _verifyExternalChecks(_checks.externalChecks, _caller);
        }
    }

    function _verifyAllowed(address[] memory _allowed, address _caller) private pure {
        for (uint256 j = 0; j < _allowed.length; j++) {
            if (_allowed[j] == _caller) {
                return;
            }
        }

        revert NotAllowed();
    }

    /// @dev Runs external checks to validate the Trade.
    ///
    /// These checks include:
    /// - balanceOf checks, were the Trade expects the caller to have a certain amount of an asset, or more.
    /// - ownerOf checks, were the Trade expects the caller to be the owner of an asset.
    /// - custom checks, were the Trade calls a provided function with the caller as an argument and expects `true` as a result.
    ///
    /// Users can play with checks in different ways:
    /// - Define 2 required checks like owning 100 or more DAI and be the owner of an Bored Ape.
    /// - Define 2 optional checks like being the owner of any Decentraland Estate, or owning 10 or more CryptoPunks.
    /// - Define 1 required check and 2 optional checks. In this case the caller has to pass the required check, and only one of the optional checks.
    ///
    /// NOTE: If the Trade only has 1 optional check, it is the same as if it was required.
    /// A Trade with 1 required check and 1 optional check is the same as having 2 required checks.
    function _verifyExternalChecks(ExternalCheck[] memory _externalChecks, address _caller) private view {
        // These vars are used to track if an optional check has already passed in order to skip the other optional checks.
        bool hasOptionalChecks = false;
        bool hasPassingOptionalCheck = false;

        for (uint256 i = 0; i < _externalChecks.length; i++) {
            ExternalCheck memory externalCheck = _externalChecks[i];

            bool isRequiredCheck = externalCheck.required;

            // Skip the optional check if another one has already passed.
            if (!isRequiredCheck && hasPassingOptionalCheck) {
                continue;
            }

            bytes4 selector = externalCheck.selector;

            bytes memory functionData;

            // Set the call data depending on the provided selector.
            // The ownerOf function requires a uint256 value as an argument that would be a tokenId.
            // balanceOf and other custom calls require the caller address as param.
            if (selector == OWNER_OF_SELECTOR) {
                functionData = abi.encodeWithSelector(selector, externalCheck.value);
            } else {
                functionData = abi.encodeWithSelector(selector, _caller);
            }

            (bool success, bytes memory data) = externalCheck.contractAddress.staticcall(functionData);

            if (!success) {
                // Do nothing here, an unsuccessful call will be treated as a failed check later.
            } else if (selector == BALANCE_OF_SELECTOR) {
                success = abi.decode(data, (uint256)) >= externalCheck.value;
            } else if (selector == OWNER_OF_SELECTOR) {
                success = abi.decode(data, (address)) == _caller;
            } else {
                success = abi.decode(data, (bool));
            }

            // There is no need to proceed if a required check fails.
            if (!success && isRequiredCheck) {
                revert ExternalChecksFailed();
            }

            // Track that an optional check has passed.
            // If it is the first optional check to pass, set the flag to skip the other optional checks.
            if (!isRequiredCheck) {
                hasOptionalChecks = true;

                if (success) {
                    hasPassingOptionalCheck = true;
                }
            }
        }

        // If there were optional checks and none of them passed, revert.
        if (hasOptionalChecks && !hasPassingOptionalCheck) {
            revert ExternalChecksFailed();
        }
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
