// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SharedWalletVoting} from "./SharedWalletVoting.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SharedWalletStorage} from "./SharedWalletStorage.sol";

/**
 * @title SharedWallet
 * @author Kostadin Atanasov Madjerski
 * @dev This is the main implementation of the shared wallet contract
 * @notice constructor is replaced with initialize function because of minimal proxy pattern (EIP1167)
 */
contract SharedWallet is Initializable, SharedWalletVoting, ReentrancyGuard {
    error SharedWallet__ShouldNotBeAMember(address user);
    error SharedWallet__MustDepositMoreThanZero();
    error SharedWallet__NotEnoughFunds();
    error SharedWallet__ShouldBeAMember(address user);
    error SharedWallet__TransactionFailed();
    error SharedWallet__CannotRemoveOwner();
    error SharedWallet__OnlyInviteeCanAcceptInvitation();
    error SharedWallet__OnlyInviteeCanDeclineInvitation();
    error SharedWallet__VoteNotPassed();
    error SharedWallet__MemberInsufficientFunds();

    /////////////////////////////////////
    ///////////// STRUCTS //////////////

    /**
     * @notice this is the struct that represents a member
     * @param isMember if the member is a member
     * @param voteCount the number of votes the member has
     * @param amountDeposited the amount of funds the member has deposited
     */
    struct Member {
        bool isMember;
        uint256 amountDeposited;
    }

    /////////////////////////////////////
    ////////////// STORAGE //////////////

    address private i_owner;
    SharedWalletStorage private i_sharedWalletStorage;
    address[] private s_membersLog;
    uint256 internal s_totalAmountDeposited;

    string public name;
    uint32 public s_numberOfMembers;

    mapping(address member => Member) internal members;

    /////////////////////////////////////
    ///////////// EVENTS /////////////

    event SharedWallet__MemberAdded(address user);
    event SharedWallet__MemberRemoved(address user);

    /////////////////////////////////////
    ///////////// MODIFIERS /////////////

    modifier onlyMember() override {
        if (!members[msg.sender].isMember)
            revert SharedWallet__ShouldBeAMember(msg.sender);
        _;
    }

    function initialize(
        address _sharedWalletStorage,
        string memory _name,
        address _owner
    ) public initializer {
        i_owner = _owner;
        i_sharedWalletStorage = SharedWalletStorage(_sharedWalletStorage);
        name = _name;
        _addMember(_owner);
    }

    //////////////////////////////////////////////
    ///////////// EXTERNAL FUNCTIONS /////////////

    /**
     * @param _voteId the id of the vote
     * @dev This function will be called only from the invitee to accept the invitation
     * @dev If he accepts the invitation the invitation will get removed and he will be added as a member
     */
    function acceptInvitation(uint256 _voteId) external {
        Vote storage _vote = votes[_voteId];

        if (_vote.typeOfVote != TypeOfVote.ADD_MEMBER)
            revert SharedWallet__OnlyInviteeCanAcceptInvitation();

        if (_vote.status != VoteStatus.PASSED)
            revert SharedWallet__VoteNotPassed();

        if (address(_vote.data) != msg.sender)
            revert SharedWallet__OnlyInviteeCanAcceptInvitation();

        i_sharedWalletStorage.updateInvitation(
            msg.sender,
            uint256(SharedWalletStorage.InvitationStatus.ACCEPTED)
        );

        _addMember(msg.sender);
    }

    function declineInvitation(uint256 _voteId) external {
        Vote storage _vote = votes[_voteId];

        if (address(_vote.data) != msg.sender)
            revert SharedWallet__OnlyInviteeCanDeclineInvitation();

        i_sharedWalletStorage.updateInvitation(
            msg.sender,
            uint256(SharedWalletStorage.InvitationStatus.REJECTED)
        );
    }

    /**
     * @notice This is the handler for depositing funds into the wallet
     *
     */
    function depositIntoWallet() external payable onlyMember {
        if (msg.value == 0) revert SharedWallet__MustDepositMoreThanZero();

        unchecked {
            members[msg.sender].amountDeposited += msg.value;
            s_totalAmountDeposited = s_totalAmountDeposited + msg.value;
        }
    }

    function leave() external onlyMember {
        _removeMember(msg.sender);
    }

    //////////////////////////////////////
    ///// PRIVATE INTERNAL FUNCTIONS /////

    /**
     * @param _user the address of the user to send the invitation to
     * @param _voteId the id of the vote that has voted to add a new member
     * @dev Low level function call only when a vote for adding member has passed
     */
    function _sendInvitation(address _user, uint256 _voteId) internal {
        i_sharedWalletStorage.sendUserInvitation(_user, _voteId);
    }

    /**
     * @param _user the address of the user to add
     * @dev This is a low level function call only if a vote for adding member has passed
     * @dev Make sure that the voteData was validated before calling this function
     */
    function _addMember(address _user) private {
        Member memory member = members[_user];

        if (member.isMember) revert SharedWallet__ShouldNotBeAMember(_user);

        members[_user].isMember = true;

        unchecked {
            ++s_numberOfMembers;
        }

        i_sharedWalletStorage.addWalletToUser(_user);

        s_membersLog.push(_user);

        emit SharedWallet__MemberAdded(_user);
    }

    /**
     * @param _voteId the id of the vote
     * @notice this is a private function and should be called ONLY IF A VOTE DID PASS
     * @notice Call this function onlyy when a vote for WITHDRAW_FUNDS has passed
     * @dev Make sure that the voteData was validated before calling this function
     * @dev Most of the checks are made in the parent contract in tryToExecute function
     */
    function _withdraw(uint256 _voteId) private {
        Vote storage vote = votes[_voteId];
        address author = vote.author;
        uint160 voteData = vote.data;

        unchecked {
            members[author].amountDeposited -= voteData;
            s_totalAmountDeposited = s_totalAmountDeposited - voteData;
        }

        (bool success, ) = payable(author).call{value: voteData}("");

        if (!success) revert SharedWallet__TransactionFailed();
    }

    /**
     * @param  _member of the vote
     * @notice this is a private function and should be called ONLY IF A VOTE FOR REMOVING USER DID PASS
     * @dev Here we will remove the user from the members and return all of his funds
     * @dev Make sure that the voteData was validated before calling this function
     * @dev This function will be called only if there is a member to remove
     */
    function _removeMember(address _member) private {
        if (_member == i_owner) revert SharedWallet__CannotRemoveOwner();

        Member memory member = members[_member];
        uint256 value = member.amountDeposited;

        i_sharedWalletStorage.removeWalletFromUser(_member);

        if (value > 0 && value <= s_totalAmountDeposited) {
            unchecked {
                s_totalAmountDeposited = s_totalAmountDeposited - value;
            }

            (bool success, ) = payable(_member).call{value: value}("");

            if (!success) revert SharedWallet__TransactionFailed();
        }

        delete members[_member];
        unchecked {
            --s_numberOfMembers;
        }
    }

    /**
     * @notice This function will destroy the wallet and return all of the funds to the members
     * @dev This function is called only if a vote for destroying the wallet has passed
     * @dev Make sure that the voteData was validated before calling this function
     */
    function _destroyWallet() private {
        address[] memory membersLog = s_membersLog;
        uint256 numberOfMembers = membersLog.length;
        uint256 totalAmountDeposited = s_totalAmountDeposited;

        for (uint256 i = 0; i < numberOfMembers; ) {
            address member = membersLog[i];
            Member memory memberToDelete = members[member];
            uint256 amountDeposited = memberToDelete.amountDeposited;

            i_sharedWalletStorage.removeWalletFromUser(member);

            if (amountDeposited != 0) {
                if (totalAmountDeposited < amountDeposited)
                    revert SharedWallet__NotEnoughFunds();

                totalAmountDeposited = totalAmountDeposited - amountDeposited;

                (bool success, ) = payable(member).call{value: amountDeposited}(
                    ""
                );

                if (!success) revert SharedWallet__TransactionFailed();
            }

            delete members[member];

            unchecked {
                ++i;
                --numberOfMembers;
            }
        }

        s_numberOfMembers = 0;
        s_totalAmountDeposited = 0;

        selfdestruct(payable(i_owner));
    }

    ///////////////////////////////////////
    /////////// OVERRIDES ////////////////

    function _execute(
        uint256 _voteId,
        TypeOfVote _typeOfVote,
        uint160 _data
    ) internal override nonReentrant {
        if (_typeOfVote == TypeOfVote.ADD_MEMBER) {
            _sendInvitation(address(_data), _voteId);
        } else if (_typeOfVote == TypeOfVote.REMOVE_MEMBER) {
            _removeMember(address(_data));
        } else if (_typeOfVote == TypeOfVote.WITHDRAW_FUNDS) {
            _withdraw(_voteId);
        } else if (_typeOfVote == TypeOfVote.DESTROY) {
            _destroyWallet();
        }
    }

    function _shouldBeMember(address _user) internal view override {
        if (!members[_user].isMember)
            revert SharedWallet__ShouldBeAMember(_user);
    }

    function _shouldNotBeMember(address _user) internal view override {
        if (members[_user].isMember)
            revert SharedWallet__ShouldNotBeAMember(_user);
    }

    function _shouldHaveValidFundsWithdrawal(
        address _user,
        uint256 _amount
    ) internal view override {
        if (members[_user].amountDeposited < _amount)
            revert SharedWallet__MemberInsufficientFunds();
    }

    function _attendance(
        uint256 _voteId
    ) internal view override returns (bool allMemberVoted, uint256 goal) {
        Vote storage vote = votes[_voteId];
        uint256 totalVotes = vote.votesFor + vote.votesAgainst;

        return (totalVotes == s_numberOfMembers, totalVotes / 2 + 1);
    }

    /////////////////////////////////////
    ///////////// GETTERS //////////////

    /**
     * @notice This function will return the amount deposited by a user
     * @param _user the address of the user
     * @return the amount deposited by the user
     */
    function getAmountDeposited(address _user) external view returns (uint256) {
        return members[_user].amountDeposited;
    }

    /**
     * @notice This function will return the total amount deposited in the wallet
     * @return the total amount deposited in the wallet
     */
    function getTotalAmountDeposited() external view returns (uint256) {
        return s_totalAmountDeposited;
    }

    /**
     * @notice This function will return the owner of the wallet
     * @return the owner of the wallet
     */
    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getMember(
        address _user
    ) external view returns (bool isMember, uint256 amountDeposited) {
        Member memory member = members[_user];

        return (member.isMember, member.amountDeposited);
    }

    function getNumberOfMembers() external view returns (uint32) {
        return s_numberOfMembers;
    }

    function getVote(
        uint256 _voteId
    )
        external
        view
        returns (TypeOfVote, uint160, address, uint256, uint256, VoteStatus)
    {
        Vote storage voteToGet = votes[_voteId];

        return (
            voteToGet.typeOfVote,
            voteToGet.data,
            voteToGet.author,
            voteToGet.votesFor,
            voteToGet.votesAgainst,
            voteToGet.status
        );
    }

    function getMembersLog() external view returns (address[] memory) {
        return s_membersLog;
    }
}
