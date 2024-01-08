// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SharedWalletFactory} from "./SharedWalletFactory.sol";

contract SharedWalletStorage {
    error SharedWalletStorage__ShouldNotBeAMember(address user);
    error SharedWalletStorage__OnlyWalletCanCallThis();

    enum InvitationStatus {
        PENDING,
        ACCEPTED,
        REJECTED
    }

    struct Invitation {
        address wallet;
        address user;
        InvitationStatus status;
        uint256 voteId;
    }

    /////////////////////////////////////
    ////////////// STORAGE //////////////

    mapping(address => Invitation[]) private s_invitations;
    mapping(address => bool) private s_isWallet;
    mapping(address user => address[] wallets) private s_usersWallets;

    SharedWalletFactory private immutable s_factoryAddress;

    /////////////////////////
    ////// Constructor //////

    constructor() {
        s_factoryAddress = SharedWalletFactory(msg.sender);
    }

    /////////////////////////////////////
    ///////////// MODIFIERS /////////////

    modifier onlyWallet(address _sender) {
        if (!s_factoryAddress.isWallet(_sender))
            revert SharedWalletStorage__OnlyWalletCanCallThis();
        _;
    }

    /////////////////////////////////////
    ///////////// FUNCTIONS /////////////

    function sendUserInvitation(
        address _user,
        uint256 _voteId
    ) external onlyWallet(msg.sender) {
        s_invitations[_user].push(
            Invitation({
                wallet: msg.sender,
                user: _user,
                voteId: _voteId,
                status: InvitationStatus.PENDING
            })
        );
    }

    function updateInvitation(
        address _user,
        uint256 status
    ) external onlyWallet(msg.sender) {
        Invitation[] memory m_invitations = s_invitations[_user];
        uint256 invitationsLength = m_invitations.length;

        for (uint32 i; i < invitationsLength; ) {
            if (m_invitations[i].wallet == msg.sender) {
                s_invitations[_user][i].status = InvitationStatus(status);
                return;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     *
     * @param _user The user to add the wallet to
     * @dev This function can only be called by a wallet contract
     */
    function addWalletToUser(address _user) external onlyWallet(msg.sender) {
        s_usersWallets[_user].push(msg.sender);
    }

    /**
     *
     * @param _user  The user to remove the wallet from
     * @dev This function can only be called by a wallet contract
     */
    function removeWalletFromUser(
        address _user
    ) external onlyWallet(msg.sender) {
        address[] memory m_wallets = s_usersWallets[_user];
        uint256 walletsLength = m_wallets.length;

        for (uint32 i; i < walletsLength; ) {
            if (m_wallets[i] == msg.sender) {
                s_usersWallets[_user][i] = m_wallets[walletsLength - 1];
                s_usersWallets[_user].pop();
                return;
            }

            unchecked {
                ++i;
            }
        }
    }

    //////////////////////////////////////////////////////
    ////////////// EXTERNAL VIEW FUNCTIONS ///////////////

    function userWallets() external view returns (address[] memory) {
        return s_usersWallets[msg.sender];
    }

    function userInvitations() external view returns (Invitation[] memory) {
        return s_invitations[msg.sender];
    }
}
