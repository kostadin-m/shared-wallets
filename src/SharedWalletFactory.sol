// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SharedWallet} from "./SharedWallet.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SharedWalletStorage} from "./SharedWalletStorage.sol";

/**
 * @title SharedWalletFactory
 * @author web3km
 * @notice This contract acts as a clone factory following the EIP1167 standard
 */
contract SharedWalletFactory {
    using Clones for address;

    /// @notice The implementation contract
    /// @dev Used to clone SharedWallet contract (EIP1167)
    address private sharedWalletImpl;

    /// @notice The storage contract
    address private immutable sharedWalletStorage;

    address[] private s_wallets;

    mapping(address => bool) private s_isWallet;

    event SharedWalletCreated(address indexed wallet, address indexed owner);

    constructor() {
        sharedWalletImpl = address(new SharedWallet());
        sharedWalletStorage = address(new SharedWalletStorage());
    }

    function createWallet(
        string memory _name
    ) external returns (SharedWallet, SharedWalletStorage) {
        SharedWallet wallet = SharedWallet(sharedWalletImpl.clone());

        s_wallets.push(address(wallet));
        s_isWallet[address(wallet)] = true;

        wallet.initialize(sharedWalletStorage, _name, msg.sender);

        emit SharedWalletCreated(address(wallet), msg.sender);

        return (wallet, SharedWalletStorage(sharedWalletStorage));
    }

    function isWallet(address _wallet) external view returns (bool) {
        return s_isWallet[_wallet];
    }

    function getWallet(uint256 _index) external view returns (address) {
        return s_wallets[_index];
    }
}
