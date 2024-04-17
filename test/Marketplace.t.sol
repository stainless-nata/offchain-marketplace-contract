// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {Marketplace} from "../src/Marketplace.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

contract MarketplaceHarness is Marketplace {
    constructor(address _owner) Marketplace(_owner) {}

    function _transferAsset(Asset memory _asset, address _from) internal override {
        // The contents of this function are to be tested on the corresponding Ethereum or Polygon marketplace contracts.
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function hashTrade(Trade memory _trade) external pure returns (bytes32) {
        return _hashTrade(_trade);
    }
}

contract MarketplaceTest is Test {
    address owner;
    address other;

    VmSafe.Wallet signer;

    MarketplaceHarness marketplace;

    function setUp() public {
        owner = vm.addr(0x1);
        other = vm.addr(0x2);

        signer = vm.createWallet("signer");

        marketplace = new MarketplaceHarness(owner);
    }

    function test_SetUpState() public view {
        assertEq(marketplace.owner(), owner);
    }

    // Ownable

    event OwnershipTransferred(address indexed, address indexed);

    error OwnableUnauthorizedAccount(address);
    error OwnableInvalidOwner(address);

    // transferOwnership

    function test_transferOwnership_OwnershipTransferred() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit OwnershipTransferred(owner, other);
        marketplace.transferOwnership(other);
        assertEq(marketplace.owner(), other);
    }

    function test_transferOwnership_RevertIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.transferOwnership(other);
    }

    function test_transferOwnership_RevertIfAddressZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(OwnableInvalidOwner.selector, address(0)));
        marketplace.transferOwnership(address(0));
    }

    // renounceOwnership

    function test_renounceOwnership_OwnershipTransferred() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit OwnershipTransferred(owner, address(0));
        marketplace.renounceOwnership();
    }

    function test_renounceOwnership_RevertIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.renounceOwnership();
    }

    // Pausable
    event Paused(address);
    event Unpaused(address);

    error EnforcedPause();
    error ExpectedPause();

    // pause

    function test_pause_RevertIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.pause();
    }

    function test_pause_RevertIfPaused() public {
        vm.prank(owner);
        marketplace.pause();

        vm.prank(owner);
        vm.expectRevert(EnforcedPause.selector);
        marketplace.pause();
    }

    function test_pause_Paused() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit Paused(owner);
        marketplace.pause();
        assertEq(marketplace.paused(), true);
    }

    // unpause

    function test_unpause_RevertIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.unpause();
    }

    function test_unpause_RevertIfNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(ExpectedPause.selector);
        marketplace.unpause();
    }

    function test_unpause_Unpaused() public {
        vm.prank(owner);
        marketplace.pause();
        assertEq(marketplace.paused(), true);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit Unpaused(owner);
        marketplace.unpause();
        assertEq(marketplace.paused(), false);
    }

    // Marketplace

    event ContractSignatureIndexIncreased(uint256, address);
    event SignerSignatureIndexIncreased(uint256, address);
    event Traded(MarketplaceHarness.Trade);

    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error Expired();
    error NotAllowed();
    error ECDSAInvalidSignatureLength(uint256);
    error InvalidSignature();
    error SignatureReuse();

    // increaseContractSignatureIndex

    function test_increaseContractSignatureIndex_RevertIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.increaseContractSignatureIndex();
    }

    function test_increaseContractSignatureIndex_Increased() public {
        assertEq(marketplace.contractSignatureIndex(), 0);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit ContractSignatureIndexIncreased(1, owner);
        marketplace.increaseContractSignatureIndex();
        assertEq(marketplace.contractSignatureIndex(), 1);
    }

    // increaseSignerSignatureIndex

    function test_increaseSignerSignatureIndex_Increased() public {
        assertEq(marketplace.signerSignatureIndex(owner), 0);

        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit SignerSignatureIndexIncreased(1, owner);
        marketplace.increaseSignerSignatureIndex();
        assertEq(marketplace.signerSignatureIndex(owner), 1);

        assertEq(marketplace.signerSignatureIndex(other), 0);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit SignerSignatureIndexIncreased(1, other);
        marketplace.increaseSignerSignatureIndex();
        assertEq(marketplace.signerSignatureIndex(other), 1);
    }

    // accept

    function test_accept_RevertIfPaused() public {
        vm.prank(owner);
        marketplace.pause();

        MarketplaceHarness.Trade[] memory trades;
        vm.expectRevert(EnforcedPause.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfInvalidContractSignatureIndex() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].contractSignatureIndex = 1;

        vm.prank(other);
        vm.expectRevert(InvalidContractSignatureIndex.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfInvalidSignerSignatureIndex() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].signerSignatureIndex = 1;

        vm.prank(other);
        vm.expectRevert(InvalidSignerSignatureIndex.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfExpired() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp - 1;

        vm.prank(other);
        vm.expectRevert(Expired.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfNotAllowed() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].allowed = new address[](1);
        trades[0].allowed[0] = owner;

        vm.prank(other);
        vm.expectRevert(NotAllowed.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfInvalidSigner() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer.privateKey,
            MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
        );

        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(other);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.accept(trades);
    }

    function test_accept_Traded() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer.privateKey,
            MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
        );

        trades[0].signer = signer.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit Traded(trades[0]);
        marketplace.accept(trades);
    }

    function test_accept_AssetBeneficiaryIsChanged() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].sent = new MarketplaceHarness.Asset[](1);

        trades[0].sent[0].beneficiary = other;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer.privateKey,
            MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
        );

        trades[0].sent[0].beneficiary = owner;

        trades[0].signer = signer.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit Traded(trades[0]);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfReceivedAssetBeneficiaryIsChanged() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].received = new MarketplaceHarness.Asset[](1);

        trades[0].received[0].beneficiary = other;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer.privateKey,
            MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
        );

        trades[0].received[0].beneficiary = owner;

        trades[0].signer = signer.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(other);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfSignatureIsResused() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].uses = 1;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signer.privateKey,
            MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0]))
        );

        trades[0].signer = signer.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(other);
        marketplace.accept(trades);

        vm.prank(other);
        vm.expectRevert(SignatureReuse.selector);
        marketplace.accept(trades);
    }
}
