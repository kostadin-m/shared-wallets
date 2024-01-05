// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {SharedWalletFactory} from "../../src/SharedWalletFactory.sol";
import {SharedWallet} from "../../src/SharedWallet.sol";

contract SharedWalletFactoryTest is Test {
    SharedWalletFactory factory;

    function setUp() public {
        factory = new SharedWalletFactory();
    }

    function test_canCreateWallet() public {
        factory.createWallet("First wallet");

        SharedWallet wallet = SharedWallet(factory.getWallet(0));

        assertEq(wallet.name(), "First wallet");
    }

    function test_canCreateMultiWallets() public {
        factory.createWallet("First wallet");
        factory.createWallet("Second wallet");

        SharedWallet wallet1 = SharedWallet(factory.getWallet(0));
        SharedWallet wallet2 = SharedWallet(factory.getWallet(1));

        assertEq(wallet1.name(), "First wallet");
        assertEq(wallet2.name(), "Second wallet");
    }
}
