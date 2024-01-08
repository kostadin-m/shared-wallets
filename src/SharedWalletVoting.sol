// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract SharedWalletVoting {
    error SharedWalletVoting__VoteIsNotInProgress(uint256 voteId);
    error SharedWalletVoting__UserHasAlreadyVoted(address sender);
    error SharedWalletVoting__InvalidData();

    /////////////////////////////////////
    ///////////// ENUMS //////////////

    enum TypeOfVote {
        ADD_MEMBER,
        REMOVE_MEMBER,
        WITHDRAW_FUNDS,
        DESTROY
    }

    enum VoteStatus {
        IN_PROGRESS,
        PASSED,
        FAILED
    }

    /////////////////////////////////////
    ///////////// STRUCTS //////////////

    struct Vote {
        TypeOfVote typeOfVote;
        uint160 data;
        address author;
        uint32 votesFor;
        uint32 votesAgainst;
        VoteStatus status;
        mapping(address => bool) hasVoted;
    }

    /////////////////////////////////////
    ////////////// STORAGE //////////////

    mapping(uint256 voteId => Vote vote) votes;

    /////////////////////////////////////
    ///////////// EVENTS ///////////////

    event VoteCreated(
        uint256 indexed voteId,
        TypeOfVote indexed typeOfVote,
        uint160 data
    );
    event VoteExecuted(
        uint256 indexed voteId,
        TypeOfVote indexed typeOfVote,
        uint160 data
    );
    event VoteFailed(uint256 indexed voteId, TypeOfVote indexed typeOfVote);
    event MemberVoted(
        uint256 indexed voteId,
        TypeOfVote indexed typeOfVote,
        address indexed member,
        bool voteFor
    );

    /////////////////////////////////
    /////// EXTERNAL FUNCTIONS //////

    function createVote(
        uint256 _typeOfVoteIndex,
        uint160 _data
    ) external onlyMember returns (uint256) {
        TypeOfVote typeOfVote = TypeOfVote(_typeOfVoteIndex);

        address _addrData = address(_data);

        if (((typeOfVote != TypeOfVote.DESTROY && _addrData == address(0))))
            revert SharedWalletVoting__InvalidData();

        if (typeOfVote == TypeOfVote.REMOVE_MEMBER) {
            _shouldBeMember(_addrData);
        } else if (typeOfVote == TypeOfVote.ADD_MEMBER) {
            _shouldNotBeMember(_addrData);
        } else if (typeOfVote == TypeOfVote.WITHDRAW_FUNDS) {
            _shouldHaveValidFundsWithdrawal(msg.sender, _data);
        }

        uint256 voteId = uint256(
            keccak256(
                abi.encodePacked(uint256(typeOfVote), _data, block.timestamp)
            )
        );

        votes[voteId].author = msg.sender;
        votes[voteId].typeOfVote = typeOfVote;
        votes[voteId].data = _data;
        votes[voteId].status = VoteStatus.IN_PROGRESS;

        emit VoteCreated(voteId, typeOfVote, _data);

        return voteId;
    }

    function vote(uint256 _voteId, bool _voteFor) external onlyMember {
        Vote storage votingFor = votes[_voteId];

        if (votingFor.status != VoteStatus.IN_PROGRESS)
            revert SharedWalletVoting__VoteIsNotInProgress(_voteId);
        if (votingFor.hasVoted[msg.sender])
            revert SharedWalletVoting__UserHasAlreadyVoted(msg.sender);

        _handleVote(_voteId, _voteFor);
    }

    function tryToExecute(uint256 _voteId) external onlyMember {
        Vote storage voteToExec = votes[_voteId];

        if (voteToExec.status != VoteStatus.IN_PROGRESS)
            revert SharedWalletVoting__VoteIsNotInProgress(_voteId);

        uint32 votesFor = voteToExec.votesFor;
        uint32 votesAgainst = voteToExec.votesAgainst;

        (bool allMembersVoted, uint256 goal) = _attendance(_voteId);

        if (votesFor == goal) {
            _execute(_voteId, voteToExec.typeOfVote, voteToExec.data);
            voteToExec.status = VoteStatus.PASSED;

            emit VoteExecuted(_voteId, voteToExec.typeOfVote, voteToExec.data);
        } else if (votesAgainst == goal || allMembersVoted) {
            voteToExec.status = VoteStatus.FAILED;
            emit VoteFailed(_voteId, voteToExec.typeOfVote);
        }
    }

    ///////////////////////////////////
    /////// INTERNAL FUNCTIONS ////////

    /**
     * @dev Low level function to handle a vote
     * @notice This function will increment the vote count for the member and the vote count for the vote
     */
    function _handleVote(uint256 _voteId, bool _voteFor) internal {
        Vote storage voteToHandle = votes[_voteId];
        voteToHandle.hasVoted[msg.sender] = true;

        unchecked {
            if (_voteFor) voteToHandle.votesFor++;
            else voteToHandle.votesAgainst++;
        }

        emit MemberVoted(
            _voteId,
            voteToHandle.typeOfVote,
            msg.sender,
            _voteFor
        );
    }

    ////////////////////////////
    /////// ABSTRACTS /////////

    /**
     * @dev Low level function to check if the member is a member of the contract
     *
     */
    modifier onlyMember() virtual {
        _;
    }

    /**
     * @dev Low level function to check if the member is a member of the contract
     * @notice This function reverts if there is no member with the address
     */
    function _shouldBeMember(address _member) internal virtual;

    /**
     * @dev Low level function to check if the member is not a member of the contract
     * @notice This function reverts if there is a member with the address
     */
    function _shouldNotBeMember(address _member) internal virtual;

    /**
     * @dev Low level function to check if the member has enough funds to withdraw
     * @notice This function reverts if the member does not have enough funds to withdraw
     */
    function _shouldHaveValidFundsWithdrawal(
        address _member,
        uint256 _amount
    ) internal virtual;

    /**
     *
     * @param _voteId the id of the vote
     * @return allMemberVoted Boolean if all members voted
     * @return goal The goal of the vote
     */
    function _attendance(
        uint256 _voteId
    ) internal virtual returns (bool allMemberVoted, uint256 goal);

    /**
     * @notice This is the handler for withdrawing funds from the wallet
     * @param _voteId the vote id to execute
     * @param _typeOfVote the type of vote
     * @param _data the data of the vote
     * @notice This function overrides the parent function and will be called only if a vote has reached the attendance goal
     */
    function _execute(
        uint256 _voteId,
        TypeOfVote _typeOfVote,
        uint160 _data
    ) internal virtual {}
}
