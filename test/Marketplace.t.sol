// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC1271WalletMock} from "lib/openzeppelin-contracts/contracts/mocks/ERC1271WalletMock.sol";
import {Marketplace} from "../src/Marketplace.sol";

contract MarketplaceHarness is Marketplace {
    constructor(address _owner) Marketplace(_owner) {}

    function _transferAsset(Asset memory _asset, address _from, address _signer) internal override {
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
    address caller1;
    address caller2;

    VmSafe.Wallet signer1;
    VmSafe.Wallet signer2;
    VmSafe.Wallet signer3;

    MarketplaceHarness marketplace;

    function setUp() public {
        owner = vm.addr(0x1);

        caller1 = vm.addr(0x2);
        caller2 = vm.addr(0x3);

        signer1 = vm.createWallet("signer1");
        signer2 = vm.createWallet("signer2");
        signer3 = vm.createWallet("signer3");

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
        emit OwnershipTransferred(owner, caller1);
        marketplace.transferOwnership(caller1);
        assertEq(marketplace.owner(), caller1);
    }

    function test_transferOwnership_RevertIfNotOwner() public {
        vm.prank(caller1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, caller1));
        marketplace.transferOwnership(caller1);
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
        vm.prank(caller1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, caller1));
        marketplace.renounceOwnership();
    }

    // Pausable
    event Paused(address);
    event Unpaused(address);

    error EnforcedPause();
    error ExpectedPause();

    // pause

    function test_pause_RevertIfNotOwner() public {
        vm.prank(caller1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, caller1));
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
        vm.prank(caller1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, caller1));
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

    event ContractSignatureIndexIncreased(uint256 _to, address _by);
    event SignerSignatureIndexIncreased(uint256 _to, address _by);
    event SignatureCancelled();
    event Traded();

    error CancelledSignature();
    error SignatureReuse();
    error UsedTradeId();
    error NotEffective();
    error InvalidContractSignatureIndex();
    error InvalidSignerSignatureIndex();
    error Expired();
    error NotAllowed();
    error InvalidSignature();

    // increaseContractSignatureIndex

    function test_increaseContractSignatureIndex_RevertIfNotOwner() public {
        vm.prank(caller1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, caller1));
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

        assertEq(marketplace.signerSignatureIndex(caller1), 0);

        vm.prank(caller1);
        vm.expectEmit(address(marketplace));
        emit SignerSignatureIndexIncreased(1, caller1);
        marketplace.increaseSignerSignatureIndex();
        assertEq(marketplace.signerSignatureIndex(caller1), 1);
    }

    // cancelSignature

    function test_cancelSignature_RevertIfInvalidSigner() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.cancelSignature(trades);
    }

    function test_cancelSignature_SignatureCancelled() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(signer1.addr);
        vm.expectEmit(address(marketplace));
        emit SignatureCancelled();
        marketplace.cancelSignature(trades);
    }

    // accept

    // accept - Checks

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

        vm.prank(caller1);
        vm.expectRevert(InvalidContractSignatureIndex.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfInvalidSignerSignatureIndex() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].signerSignatureIndex = 1;

        vm.prank(caller1);
        vm.expectRevert(InvalidSignerSignatureIndex.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfCancelledSignature() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(signer1.addr);
        marketplace.cancelSignature(trades);

        vm.prank(caller1);
        vm.expectRevert(CancelledSignature.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfNotEffective() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].effective = block.timestamp + 1;

        vm.prank(caller1);
        vm.expectRevert(NotEffective.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfExpired() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp - 1;

        vm.prank(caller1);
        vm.expectRevert(Expired.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfNotAllowed() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].allowed = new address[](1);
        trades[0].allowed[0] = owner;

        vm.prank(caller1);
        vm.expectRevert(NotAllowed.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfInvalidSigner() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertIfSignatureIsResused() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].uses = 1;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        marketplace.accept(trades);

        vm.prank(caller1);
        vm.expectRevert(SignatureReuse.selector);
        marketplace.accept(trades);
    }

    // accept - Success

    function test_accept_Traded() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectEmit(address(marketplace));
        emit Traded();
        marketplace.accept(trades);
    }


        function test_accept_Traded_ManyAllowed() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].allowed = new address[](10);
        trades[0].allowed[0] = caller1;
        trades[0].allowed[1] = caller2;
        trades[0].allowed[2] = vm.addr(0x4);
        trades[0].allowed[3] = vm.addr(0x5);
        trades[0].allowed[4] = vm.addr(0x6);
        trades[0].allowed[5] = vm.addr(0x7);
        trades[0].allowed[6] = vm.addr(0x8);
        trades[0].allowed[7] = vm.addr(0x9);
        trades[0].allowed[8] = vm.addr(0xa);
        trades[0].allowed[9] = vm.addr(0xb);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(vm.addr(0xb));
        vm.expectEmit(address(marketplace));
        emit Traded();
        marketplace.accept(trades);
    }
    
    // accept - Sent asset beneficiary

    function test_accept_AllowsSentAssetBeneficiaryToBeChanged() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].sent = new MarketplaceHarness.Asset[](1);

        trades[0].sent[0].beneficiary = caller1;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].sent[0].beneficiary = owner;

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectEmit(address(marketplace));
        emit Traded();
        marketplace.accept(trades);
    }

    function test_accept_RevertIfReceivedAssetBeneficiaryIsChanged() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;
        trades[0].received = new MarketplaceHarness.Asset[](1);

        trades[0].received[0].beneficiary = caller1;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].received[0].beneficiary = owner;

        trades[0].signer = signer1.addr;
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.accept(trades);
    }

    // accept - ERC1271

    function test_accept_RevertIfERC1271VerificationFails() public {
        ERC1271WalletMock wallet = new ERC1271WalletMock(caller1);

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = address(wallet);
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        vm.expectRevert(InvalidSignature.selector);
        marketplace.accept(trades);
    }

    function test_accept_SignerIsERC1271() public {
        ERC1271WalletMock wallet = new ERC1271WalletMock(signer1.addr);

        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        trades[0].expiration = block.timestamp;

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

        trades[0].signer = address(wallet);
        trades[0].signature = abi.encodePacked(r, s, v);

        vm.prank(caller1);
        marketplace.accept(trades);
    }

    // accept - Trade ID

    function test_accept_RevertsIfTradeIdIsReused() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;
            trades[0].uses = 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer1.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(trades);

        {
            trades[0].expiration = block.timestamp + 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(trades);
    }

    function test_accept_RevertsIfTradeIdIsReused_OnlyAfterSignatureReusesReachesItsLimit() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;
            trades[0].uses = 2;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer1.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(trades);

        vm.prank(caller1);
        marketplace.accept(trades);

        {
            trades[0].expiration = block.timestamp + 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer1.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(trades);
    }

    function test_accept_CanTradeSameReceivedAssetsWithADifferentSalt() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;
            trades[0].uses = 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer1.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(trades);

        {
            trades[0].expiration = block.timestamp + 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(trades);

        {
            trades[0].salt = bytes32(abi.encode(1));

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(trades);
    }

    function test_accept_AnotherUserCanAcceptTradeWithSameSaltAndReceivedAssets() public {
        MarketplaceHarness.Trade[] memory trades = new MarketplaceHarness.Trade[](1);

        {
            trades[0].expiration = block.timestamp;
            trades[0].uses = 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signer = signer1.addr;
            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(trades);

        {
            trades[0].expiration = block.timestamp + 1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(trades[0])));

            trades[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(trades);

        vm.prank(caller2);
        marketplace.accept(trades);
    }

    function test_accept_RevertsIfTryingToAcceptDifferentTradeFromFinishedAuction() public {
        MarketplaceHarness.Trade[] memory offerA = new MarketplaceHarness.Trade[](1);

        {
            offerA[0].expiration = block.timestamp;
            offerA[0].uses = 1;
            offerA[0].allowed = new address[](1);
            offerA[0].allowed[0] = caller1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer1.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(offerA[0])));

            offerA[0].signer = signer1.addr;
            offerA[0].signature = abi.encodePacked(r, s, v);
        }

        MarketplaceHarness.Trade[] memory offerB = new MarketplaceHarness.Trade[](1);

        {
            offerB[0].expiration = block.timestamp;
            offerB[0].uses = 1;
            offerB[0].allowed = new address[](1);
            offerB[0].allowed[0] = caller1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer2.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(offerB[0])));

            offerB[0].signer = signer2.addr;
            offerB[0].signature = abi.encodePacked(r, s, v);
        }

        MarketplaceHarness.Trade[] memory offerC = new MarketplaceHarness.Trade[](1);

        {
            offerC[0].expiration = block.timestamp;
            offerC[0].uses = 1;
            offerC[0].allowed = new address[](1);
            offerC[0].allowed[0] = caller1;

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(signer3.privateKey, MessageHashUtils.toTypedDataHash(marketplace.getDomainSeparator(), marketplace.hashTrade(offerC[0])));

            offerC[0].signer = signer3.addr;
            offerC[0].signature = abi.encodePacked(r, s, v);
        }

        vm.prank(caller1);
        marketplace.accept(offerA);

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(offerB);

        vm.prank(caller1);
        vm.expectRevert(UsedTradeId.selector);
        marketplace.accept(offerC);
    }
}
