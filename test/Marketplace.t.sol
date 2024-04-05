// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Marketplace, Trade} from "../src/Marketplace.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract MarketplaceHarness is Marketplace {
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}

contract MarketplaceTest is Test {
    function setUp() public {}

    function test_Accept() public {
        // Instantiate the Marketplace contract.
        MarketplaceHarness marketplace = new MarketplaceHarness();
        // Instantiate the MockERC20 contract.
        MockERC20 erc20 = new MockERC20();

        // Private key of the signer.
        uint256 signerPrivateKey = 1;
        // Private key of the caller.
        uint256 callerPrivateKey = 2;

        // Address of the signer;
        address signer = vm.addr(signerPrivateKey);
        // Address of the caller;
        address caller = vm.addr(callerPrivateKey);

        // Mint 1 ether to the signer.
        erc20.mint(signer, 1 ether);
        // Mint 1 ether to the caller.
        erc20.mint(caller, 1 ether);

        // Allow the marketplace to spend 1 ether of the signer's balance.
        vm.prank(signer);
        erc20.approve(address(marketplace), 1 ether);
        // Allow the marketplace to spend 1 ether of the caller's balance.
        vm.prank(caller);
        erc20.approve(address(marketplace), 1 ether);

        // Get the domain separator of the marketplace contract.
        bytes32 domainSeparator = marketplace.getDomainSeparator();

        // Get the digest.
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparator, keccak256(abi.encode(keccak256("Trade(bool testBool)"), true))
        );

        // Create the signature.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        console.logUint(v);
        console.logBytes32(r);
        console.logBytes32(s);

        vm.prank(caller);
        marketplace.accept(Trade({signer: signer, signature: abi.encodePacked(r, s, v), testBool: true}));
    }
}
