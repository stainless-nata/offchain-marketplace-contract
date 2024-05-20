// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {DecentralandMarketplacePolygon} from "src/marketplace/DecentralandMarketplacePolygon.sol";
import {ICollection} from "src/marketplace/interfaces/ICollection.sol";
import {CouponManager} from "src/coupons/CouponManager.sol";
import {CollectionDiscountCoupon} from "src/coupons/CollectionDiscountCoupon.sol";

contract DecentralandMarketplacePolygonHarness is DecentralandMarketplacePolygon {
    constructor(address _owner, address _couponManager, address _feeCollector, uint256 _feeRate, address _royaltiesManager, uint256 _royaltiesRate)
        DecentralandMarketplacePolygon(_owner, _couponManager, _feeCollector, _feeRate, _royaltiesManager, _royaltiesRate)
    {}

    function eip712Name() external view returns (string memory) {
        return _EIP712Name();
    }

    function eip712Version() external view returns (string memory) {
        return _EIP712Version();
    }

    function eip712TradeHash(Trade memory _trade) external view returns (bytes32) {
        return _hashTypedDataV4(_hashTrade(_trade));
    }

    function eip712MetaTransactionHash(MetaTransaction memory _metaTx) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(bytes("MetaTransaction(uint256 nonce,address from,bytes functionData)")),
                    _metaTx.nonce,
                    _metaTx.from,
                    keccak256(_metaTx.functionData)
                )
            )
        );
    }
}

contract CouponManagerHarness is CouponManager {
    constructor(address _marketplace, address _owner, address[] memory _allowedCoupons) CouponManager(_marketplace, _owner, _allowedCoupons) {}

    function eip712CouponHash(Coupon memory _coupon) external view returns (bytes32) {
        return _hashTypedDataV4(_hashCoupon(_coupon));
    }
}

abstract contract DecentralandMarketplacePolygonTests is Test {
    address owner;
    address dao;
    address royaltiesManager;
    VmSafe.Wallet signer;
    VmSafe.Wallet metaTxSigner;
    address other;
    CollectionDiscountCoupon collectionDiscountCoupon;
    CouponManagerHarness couponManager;
    DecentralandMarketplacePolygonHarness marketplace;

    event MetaTransactionExecuted(address indexed _userAddress, address indexed _relayerAddress, bytes _functionData);

    error UnsupportedAssetType(uint256 _assetType);
    error OwnableUnauthorizedAccount(address account);

    function setUp() public virtual {
        uint256 forkId = vm.createFork("https://rpc.decentraland.org/polygon", 56395304); // Apr-29-2024 07:23:50 PM +UTC
        vm.selectFork(forkId);
        owner = 0x0E659A116e161d8e502F9036bAbDA51334F2667E;
        dao = 0xB08E3e7cc815213304d884C88cA476ebC50EaAB2;
        royaltiesManager = 0x90958D4531258ca11D18396d4174a007edBc2b42;
        signer = vm.createWallet("signer");
        metaTxSigner = vm.createWallet("metaTxSigner");
        other = 0x79c63172C7B01A8a5B074EF54428a452E0794E7A;

        collectionDiscountCoupon = new CollectionDiscountCoupon();

        address[] memory allowedCoupons = new address[](1);
        allowedCoupons[0] = address(collectionDiscountCoupon);

        couponManager = new CouponManagerHarness(address(0), owner, allowedCoupons);

        marketplace = new DecentralandMarketplacePolygonHarness(owner, address(couponManager), dao, 25_000, royaltiesManager, 25_000);

        vm.prank(owner);
        couponManager.updateMarketplace(address(marketplace));
    }

    function signTrade(DecentralandMarketplacePolygonHarness.Trade memory _trade) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, marketplace.eip712TradeHash(_trade));
        return abi.encodePacked(r, s, v);
    }

    function signMetaTx(DecentralandMarketplacePolygonHarness.MetaTransaction memory _metaTx) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(metaTxSigner.privateKey, marketplace.eip712MetaTransactionHash(_metaTx));
        return abi.encodePacked(r, s, v);
    }

    function signCoupon(CouponManagerHarness.Coupon memory _coupon) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, couponManager.eip712CouponHash(_coupon));
        return abi.encodePacked(r, s, v);
    }

    function _getBaseTrades() internal view virtual returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].signer = signer.addr;
        return trades;
    }
}

contract UnsupportedAssetTypeTests is DecentralandMarketplacePolygonTests {
    function test_RevertsIfAssetTypeIsInvalid() public {
        uint256 invalidAssetType = 100;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = invalidAssetType;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, invalidAssetType));
        marketplace.accept(trades);
    }
}

contract TransferERC20Tests is DecentralandMarketplacePolygonTests {
    IERC20 erc20;
    uint256 erc20Sent;
    address erc20OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 value);

    error FailedInnerCall();

    function setUp() public override {
        super.setUp();
        erc20 = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        erc20Sent = 1 ether;
        erc20OriginalHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;
    }

    function _getBaseTradesForSent() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].received[0].contractAddress = address(erc20);
        trades[0].received[0].value = erc20Sent;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC20() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveEnoughERC20Balance() public {
        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        marketplace.accept(trades);
    }

    function test_TransfersERC20FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(signer.addr, other, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(signer.addr), 0);
        assertEq(erc20.balanceOf(other), erc20Sent);
    }

    function test_TransfersERC20FromCallerToSigner() public {
        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, erc20Sent);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(other), 0);
        assertEq(erc20.balanceOf(signer.addr), erc20Sent);
    }

    function test_TradeWithSentAndReceivedERC20() public {
        vm.prank(other);
        erc20.approve(address(marketplace), 1 ether);

        vm.prank(signer.addr);
        erc20.approve(address(marketplace), 2 ether);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, 1 ether);

        vm.prank(erc20OriginalHolder);
        erc20.transfer(signer.addr, 2 ether);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);

        trades[0].received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].received[0].contractAddress = address(erc20);
        trades[0].received[0].value = 1 ether;

        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC20();
        trades[0].sent[0].contractAddress = address(erc20);
        trades[0].sent[0].value = 2 ether;

        trades[0].checks.expiration = block.timestamp;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        uint256 signerBalance = erc20.balanceOf(signer.addr);
        uint256 otherBalance = erc20.balanceOf(other);

        vm.prank(other);
        vm.expectEmit(address(erc20));
        emit Transfer(signer.addr, other, 2 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, 1 ether);
        marketplace.accept(trades);

        assertEq(erc20.balanceOf(signer.addr), signerBalance - 1 ether);
        assertEq(erc20.balanceOf(other), otherBalance + 1 ether);
    }
}

contract TransferERC721Tests is DecentralandMarketplacePolygonTests {
    IERC721 erc721;
    uint256 erc721TokenId;
    address erc721OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        super.setUp();
        erc721 = IERC721(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        erc721TokenId = 1053122916685571866979180276836704323188950954005491112543109775497;
        erc721OriginalHolder = 0xc1325a7Cb84b41626eDCC97f5a124B592976cd5d;
    }

    function _getBaseTradesForSent() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].sent[0].contractAddress = address(erc721);
        trades[0].sent[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].received[0].contractAddress = address(erc721);
        trades[0].received[0].value = erc721TokenId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerHasNotApprovedTheMarketplaceToSendERC721() public {
        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, other, erc721TokenId);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfSignerDoesNotHaveTheERC721Token() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerDoesNotHaveTheERC721Token() public {
        vm.prank(other);
        erc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert();
        marketplace.accept(trades);
    }

    function test_TransfersERC721FromSignerToCaller() public {
        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(signer.addr, other, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), other);
    }

    function test_TransfersERC721FromCallerToSigner() public {
        vm.prank(other);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, other, erc721TokenId);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(erc721));
        emit Transfer(other, signer.addr, erc721TokenId);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);
    }
}

contract TransferCollectionItemTests is DecentralandMarketplacePolygonTests {
    ICollection collection;
    uint256 collectionItemId;
    address collectionItemOriginalCreator;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    error NotCreator();

    function setUp() public override {
        super.setUp();
        collection = ICollection(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        collectionItemId = 10;
        collectionItemOriginalCreator = 0x3cf368FaeCdb4a4E542c0efD17850ae133688C2a;
    }

    function _getBaseTradesForSent() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_COLLECTION_ITEM();
        trades[0].sent[0].contractAddress = address(collection);
        trades[0].sent[0].value = collectionItemId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function _getBaseTradesForReceived() private view returns (DecentralandMarketplacePolygonHarness.Trade[] memory) {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].received[0].assetType = marketplace.ASSET_TYPE_COLLECTION_ITEM();
        trades[0].received[0].contractAddress = address(collection);
        trades[0].received[0].value = collectionItemId;
        trades[0].signature = signTrade(trades[0]);
        return trades;
    }

    function test_RevertsIfSignerIsNotTheCreator() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfCallerIsNotTheCreator() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert(NotCreator.selector);
        marketplace.accept(trades);
    }

    function test_RevertsIfTheMarketplaceIsNotCollectionMinterOfTheSentAsset() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectRevert("_issueToken: CALLER_CAN_NOT_MINT");
        marketplace.accept(trades);
    }

    function test_RevertsIfTheMarketplaceIsNotCollectionMinterOfTheReceivedAsset() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(other);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectRevert("_issueToken: CALLER_CAN_NOT_MINT");
        marketplace.accept(trades);
    }

    function test_MintsAndTranfersTheItemToTheCaller() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        vm.prank(signer.addr);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        vm.prank(other);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), other, expectedTokenId);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(expectedTokenId), other);
    }

    function test_MintsAndTranfersTheItemToTheCaller_MetaTx() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        vm.prank(signer.addr);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForSent();

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit MetaTransactionExecuted(metaTx.from, other, metaTx.functionData);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), metaTxSigner.addr, expectedTokenId);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);

        assertEq(collection.ownerOf(expectedTokenId), metaTxSigner.addr);
    }

    function test_MintsAndTranfersTheItemToTheSigner() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(other);

        vm.prank(other);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        vm.prank(other);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), signer.addr, expectedTokenId);
        marketplace.accept(trades);

        assertEq(collection.ownerOf(expectedTokenId), signer.addr);
    }

    function test_MintsAndTranfersTheItemToTheSigner_MetaTx() public {
        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(metaTxSigner.addr);

        vm.prank(metaTxSigner.addr);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTradesForReceived();

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit MetaTransactionExecuted(metaTx.from, other, metaTx.functionData);
        vm.expectEmit(address(collection));
        uint256 expectedTokenId = 1053122916685571866979180276836704323188950954005491112543109775772;
        emit Transfer(address(0), signer.addr, expectedTokenId);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);

        assertEq(collection.ownerOf(expectedTokenId), signer.addr);
    }
}

contract ExecuteMetaTransactionTests is DecentralandMarketplacePolygonTests {
    error Expired();
    error MetaTransactionFailedWithoutReason();

    function test_RevertsIfNonceIsInvalid() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 1;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert("NativeMetaTransaction#executeMetaTransaction: SIGNER_AND_SIGNATURE_DO_NOT_MATCH");
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfFromIsInvalid() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = other;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert("NativeMetaTransaction#executeMetaTransaction: SIGNER_AND_SIGNATURE_DO_NOT_MATCH");
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_EmitMetaTransactionExecutedEvent() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].signature = signTrade(trades[0]);

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectEmit(address(marketplace));
        emit MetaTransactionExecuted(metaTx.from, other, metaTx.functionData);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfTradeIsExpiredWithBubbledUpError() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].checks.expiration = block.timestamp - 1;
        trades[0].signature = signTrade(trades[0]);

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert(Expired.selector);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }

    function test_RevertsIfERC721AssetHasContractAddressZeroWithWithoutReasonError() public {
        DecentralandMarketplacePolygonHarness.Trade[] memory trades = _getBaseTrades();
        trades[0].sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        trades[0].sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        trades[0].sent[0].contractAddress = address(0);
        trades[0].sent[0].value = 1;
        trades[0].signature = signTrade(trades[0]);

        DecentralandMarketplacePolygonHarness.MetaTransaction memory metaTx;
        metaTx.nonce = 0;
        metaTx.from = metaTxSigner.addr;
        metaTx.functionData = abi.encodeWithSelector(marketplace.accept.selector, trades);

        bytes memory metaTxSignature = signMetaTx(metaTx);

        vm.prank(other);
        vm.expectRevert(MetaTransactionFailedWithoutReason.selector);
        marketplace.executeMetaTransaction(metaTx.from, metaTx.functionData, metaTxSignature);
    }
}

contract UpdateCouponsTests is DecentralandMarketplacePolygonTests {
    event CouponManagerUpdated(address indexed _caller, address indexed _couponManager);

    function test_RevertsIfNotOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.updateCouponManager(other);
    }

    function test_CouponManagerUpdated() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit CouponManagerUpdated(owner, other);
        marketplace.updateCouponManager(other);
    }
}

contract UpdateFeeCollectorTests is DecentralandMarketplacePolygonTests {
    event FeeCollectorUpdated(address indexed _caller, address indexed _feeCollector);

    function test_RevertsIfCallerIsNotTheOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.updateFeeCollector(dao);
    }

    function test_UpdatesFeeCollector() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit FeeCollectorUpdated(owner, dao);
        marketplace.updateFeeCollector(dao);
        assertEq(marketplace.feeCollector(), dao);
    }
}

contract UpdateFeeRateTests is DecentralandMarketplacePolygonTests {
    event FeeRateUpdated(address indexed _caller, uint256 _feeRate);

    function test_RevertsIfCallerIsNotTheOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.updateFeeRate(100);
    }

    function test_UpdatesFeeRate() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit FeeRateUpdated(owner, 100);
        marketplace.updateFeeRate(100);
        assertEq(marketplace.feeRate(), 100);
    }
}

contract UpdateRoyaltiesManagerTests is DecentralandMarketplacePolygonTests {
    event RoyaltiesManagerUpdated(address indexed _caller, address indexed _royaltiesManager);

    function test_RevertsIfCallerIsNotTheOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.updateRoyaltiesManager(dao);
    }

    function test_UpdatesFeeCollector() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit RoyaltiesManagerUpdated(owner, dao);
        marketplace.updateRoyaltiesManager(dao);
        assertEq(address(marketplace.royaltiesManager()), dao);
    }
}

contract UpdateRoyaltiesRateTests is DecentralandMarketplacePolygonTests {
    event RoyaltiesRateUpdated(address indexed _caller, uint256 _royaltiesRate);

    function test_RevertsIfCallerIsNotTheOwner() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, other));
        marketplace.updateRoyaltiesRate(100);
    }

    function test_UpdatesFeeRate() public {
        vm.prank(owner);
        vm.expectEmit(address(marketplace));
        emit RoyaltiesRateUpdated(owner, 100);
        marketplace.updateRoyaltiesRate(100);
        assertEq(marketplace.royaltiesRate(), 100);
    }
}

contract ExampleTests is DecentralandMarketplacePolygonTests {
    IERC20 erc20;
    uint256 erc20Sent;
    address erc20OriginalHolder;

    IERC721 collectionErc721;
    uint256 collectionErc721TokenId;
    address collectionErc721OriginalHolder;

    ICollection collection;
    uint256 collectionItemId;
    address collectionItemOriginalCreator;

    IERC721 erc721;
    uint256 erc721TokenId;
    address erc721OriginalHolder;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public override {
        super.setUp();

        erc20 = IERC20(0xA1c57f48F0Deb89f569dFbE6E2B7f46D33606fD4);
        erc20Sent = 100 ether;
        erc20OriginalHolder = 0x673e6B75a58354919FF5db539AA426727B385D17;

        collectionErc721 = IERC721(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        collectionErc721TokenId = 1053122916685571866979180276836704323188950954005491112543109775497;
        collectionErc721OriginalHolder = 0xc1325a7Cb84b41626eDCC97f5a124B592976cd5d;

        collection = ICollection(0xDed1e53D7A43aC1844b66c0Ca0F02627EB42e16d);
        collectionItemId = 10;
        collectionItemOriginalCreator = 0x3cf368FaeCdb4a4E542c0efD17850ae133688C2a;

        erc721 = IERC721(0x67F4732266C7300cca593C814d46bee72e40659F);
        erc721TokenId = 597997;
        erc721OriginalHolder = 0x5d01fb10c7C68c53c391F3C1e435FeA4D1E14434;
    }

    function test_TradeERC721ForERC20_ERC721IsCollectionNFT_RoyaltyGoesToCreator() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(collectionErc721OriginalHolder);
        collectionErc721.transferFrom(collectionErc721OriginalHolder, signer.addr, collectionErc721TokenId);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        collectionErc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        sent[0].contractAddress = address(collectionErc721);
        sent[0].value = collectionErc721TokenId;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        received[0].contractAddress = address(erc20);
        received[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        assertEq(collectionErc721.ownerOf(collectionErc721TokenId), signer.addr);
        uint256 collectionItemOriginalCreatorBalance = erc20.balanceOf(collectionItemOriginalCreator);
        uint256 signerBalance = erc20.balanceOf(signer.addr);

        vm.prank(other);
        // TODO: Find a way to expect events with the same name but different arguments
        // vm.expectEmit(address(collectionErc721));
        // emit Transfer(signer.addr, other, collectionErc721TokenId);
        vm.expectEmit(address(erc20));
        emit Transfer(other, collectionItemOriginalCreator, 2.5 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, 97.5 ether);
        marketplace.accept(trades);

        assertEq(collectionErc721.ownerOf(collectionErc721TokenId), other);
        assertEq(erc20.balanceOf(collectionItemOriginalCreator), collectionItemOriginalCreatorBalance + 2.5 ether);
        assertEq(erc20.balanceOf(signer.addr), signerBalance + 97.5 ether);
    }

    function test_TradeERC721ForERC20_ERC721IsNotCollectionNFT_FeeGoesToCollector() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        sent[0].contractAddress = address(erc721);
        sent[0].value = erc721TokenId;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        received[0].contractAddress = address(erc20);
        received[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);
        uint256 daoBalance = erc20.balanceOf(dao);
        uint256 signerBalance = erc20.balanceOf(signer.addr);

        vm.prank(other);
        // TODO: Find a way to expect events with the same name but different arguments
        // vm.expectEmit(address(erc721));
        // emit Transfer(signer.addr, other, erc721TokenId);
        vm.expectEmit(address(erc20));
        emit Transfer(other, dao, 2.5 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, 97.5 ether);
        marketplace.accept(trades);

        assertEq(erc721.ownerOf(erc721TokenId), other);
        assertEq(erc20.balanceOf(dao), daoBalance + 2.5 ether);
        assertEq(erc20.balanceOf(signer.addr), signerBalance + 97.5 ether);
    }

    function test_Trade2ERC721ForERC20_OneIsCollectionNFT_TheOtherIsNot_FeesAndRoyaltiesArePaid() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(collectionErc721OriginalHolder);
        collectionErc721.transferFrom(collectionErc721OriginalHolder, signer.addr, collectionErc721TokenId);

        vm.prank(erc721OriginalHolder);
        erc721.transferFrom(erc721OriginalHolder, signer.addr, erc721TokenId);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        collectionErc721.setApprovalForAll(address(marketplace), true);

        vm.prank(signer.addr);
        erc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](2);
        sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        sent[0].contractAddress = address(collectionErc721);
        sent[0].value = collectionErc721TokenId;
        sent[1].assetType = marketplace.ASSET_TYPE_ERC721();
        sent[1].contractAddress = address(erc721);
        sent[1].value = erc721TokenId;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        received[0].contractAddress = address(erc20);
        received[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        assertEq(collectionErc721.ownerOf(collectionErc721TokenId), signer.addr);
        assertEq(erc721.ownerOf(erc721TokenId), signer.addr);
        uint256 collectionItemOriginalCreatorBalance = erc20.balanceOf(collectionItemOriginalCreator);
        uint256 daoBalance = erc20.balanceOf(dao);
        uint256 signerBalance = erc20.balanceOf(signer.addr);

        vm.prank(other);
        // TODO: Find a way to expect events with the same name but different arguments
        // vm.expectEmit(address(erc721));
        // emit Transfer(signer.addr, other, erc721TokenId);
        vm.expectEmit(address(erc20));
        emit Transfer(other, dao, 2.5 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, collectionItemOriginalCreator, 2.5 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, 95 ether);
        marketplace.accept(trades);

        assertEq(collectionErc721.ownerOf(collectionErc721TokenId), other);
        assertEq(erc721.ownerOf(erc721TokenId), other);
        assertEq(erc20.balanceOf(dao), daoBalance + 2.5 ether);
        assertEq(erc20.balanceOf(collectionItemOriginalCreator), collectionItemOriginalCreatorBalance + 2.5 ether);
        assertEq(erc20.balanceOf(signer.addr), signerBalance + 95 ether);
    }

    function test_TradeERC721ForERC20_ERC721IsCollectionNFT_ApplyCollectionDiscountCoupon() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(collectionItemOriginalCreator);
        collection.transferCreatorship(signer.addr);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        address[] memory setMintersMinters = new address[](1);
        setMintersMinters[0] = address(marketplace);
        bool[] memory setMintersValues = new bool[](1);
        setMintersValues[0] = true;
        collection.setMinters(setMintersMinters, setMintersValues);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        sent[0].assetType = marketplace.ASSET_TYPE_COLLECTION_ITEM();
        sent[0].contractAddress = address(collection);
        sent[0].value = collectionItemId;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC20();
        received[0].contractAddress = address(erc20);
        received[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        CollectionDiscountCoupon.CollectionDiscountCouponData memory collectionDiscountCouponData;
        collectionDiscountCouponData.discount = 500_000;
        collectionDiscountCouponData.discountType = collectionDiscountCoupon.DISCOUNT_TYPE_RATE();
        collectionDiscountCouponData.root = 0x68ad9c0c778776109596c0568ba9c69ca861338e902dfb8aa5be05be190c65ae;

        CollectionDiscountCoupon.CollectionDiscountCouponCallerData memory collectionDiscountCouponCallerData;
        collectionDiscountCouponCallerData.proofs = new bytes32[][](1);
        collectionDiscountCouponCallerData.proofs[0] = new bytes32[](3);
        collectionDiscountCouponCallerData.proofs[0][0] = 0x161691c7185a37ff918e70bebef716ddd87844ac47f419ea23eaf4fe983fbf2c;
        collectionDiscountCouponCallerData.proofs[0][1] = 0xf1bd988d50408c15a0d017a73ff63ab5c30cc78771b609d99142fa4052c02baa;
        collectionDiscountCouponCallerData.proofs[0][2] = 0xd50d464af1a64cdd6868c42456bc58cfc561fac83e19d742b6397ae5eb44660f;

        DecentralandMarketplacePolygonHarness.Coupon[] memory coupons = new DecentralandMarketplacePolygonHarness.Coupon[](1);
        coupons[0].checks.expiration = block.timestamp;
        coupons[0].couponAddress = address(collectionDiscountCoupon);
        coupons[0].data = abi.encode(collectionDiscountCouponData);
        coupons[0].callerData = abi.encode(collectionDiscountCouponCallerData);
        coupons[0].signature = signCoupon(coupons[0]);

        uint256 daoBalance = erc20.balanceOf(dao);
        uint256 signerBalance = erc20.balanceOf(signer.addr);

        vm.prank(other);
        // // TODO: Find a way to expect events with the same name but different arguments
        // // vm.expectEmit(address(collectionErc721));
        // // emit Transfer(signer.addr, other, collectionErc721TokenId);
        vm.expectEmit(address(erc20));
        emit Transfer(other, dao, 1.25 ether);
        vm.expectEmit(address(erc20));
        emit Transfer(other, signer.addr, 48.75 ether);
        marketplace.acceptWithCoupon(trades, coupons);

        assertEq(collection.ownerOf(1053122916685571866979180276836704323188950954005491112543109775772), other);
        assertEq(erc20.balanceOf(dao), daoBalance + 1.25 ether);
        assertEq(erc20.balanceOf(signer.addr), signerBalance + 48.75 ether);
    }

    function test_RevertsIfReceivedAssetTypeIsErc20WithFees() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(collectionErc721OriginalHolder);
        collectionErc721.transferFrom(collectionErc721OriginalHolder, signer.addr, collectionErc721TokenId);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        collectionErc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        sent[0].assetType = marketplace.ASSET_TYPE_ERC721();
        sent[0].contractAddress = address(collectionErc721);
        sent[0].value = collectionErc721TokenId;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC20_WITH_FEES();
        received[0].contractAddress = address(erc20);
        received[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, marketplace.ASSET_TYPE_ERC20_WITH_FEES()));
        marketplace.accept(trades);
    }

    function test_RevertsIfSentAssetTypeIsErc20WithFees() public {
        vm.prank(erc20OriginalHolder);
        erc20.transfer(other, erc20Sent);

        vm.prank(collectionErc721OriginalHolder);
        collectionErc721.transferFrom(collectionErc721OriginalHolder, signer.addr, collectionErc721TokenId);

        vm.prank(other);
        erc20.approve(address(marketplace), erc20Sent);

        vm.prank(signer.addr);
        collectionErc721.setApprovalForAll(address(marketplace), true);

        DecentralandMarketplacePolygonHarness.Asset[] memory sent = new DecentralandMarketplacePolygonHarness.Asset[](1);
        sent[0].assetType = marketplace.ASSET_TYPE_ERC20_WITH_FEES();
        sent[0].contractAddress = address(erc20);
        sent[0].value = erc20Sent;

        DecentralandMarketplacePolygonHarness.Asset[] memory received = new DecentralandMarketplacePolygonHarness.Asset[](1);
        received[0].assetType = marketplace.ASSET_TYPE_ERC721();
        received[0].contractAddress = address(collectionErc721);
        received[0].value = collectionErc721TokenId;

        DecentralandMarketplacePolygonHarness.Trade[] memory trades = new DecentralandMarketplacePolygonHarness.Trade[](1);
        trades[0].checks.expiration = block.timestamp;
        trades[0].sent = sent;
        trades[0].received = received;
        trades[0].signer = signer.addr;
        trades[0].signature = signTrade(trades[0]);

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedAssetType.selector, marketplace.ASSET_TYPE_ERC20_WITH_FEES()));
        marketplace.accept(trades);
    }
}
