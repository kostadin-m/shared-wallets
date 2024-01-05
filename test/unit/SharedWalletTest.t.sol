// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {SharedWallet} from "../../src/SharedWallet.sol";
import {SharedWalletVoting} from "../../src/SharedWalletVoting.sol";
import {SharedWalletStorage} from "../../src/SharedWalletStorage.sol";
import {SharedWalletFactory} from "../../src/SharedWalletFactory.sol";

contract SharedWalletTest is Test {
    SharedWallet sharedWallet;
    SharedWalletStorage storageContract;
    SharedWalletFactory factory;

    address OWNER = makeAddr("owner");
    address NEW_MEMBER = makeAddr("newMember");
    address NEW_MEMBER_2 = makeAddr("newMember2");
    address NEW_MEMBER_3 = makeAddr("newMember3");

    function setUp() public {
        vm.startPrank(OWNER);
        factory = new SharedWalletFactory();

        (sharedWallet, storageContract) = factory.createWallet("test");
        vm.stopPrank();
    }

    //////////////////////////////////////////////
    /// HELPER MODIFIERS & FUNCTIONS MODIFIERS ///

    function _generateVoteId(
        uint256 typeOfVote,
        uint160 data
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(typeOfVote, data)));
    }

    function _createVote(
        uint256 typeOfVote,
        uint160 data
    ) internal returns (uint256) {
        vm.prank(OWNER);
        return sharedWallet.createVote(typeOfVote, data);
    }

    function _vote(uint256 voteId, bool voteFor, address member) internal {
        vm.startPrank(member);
        sharedWallet.vote(voteId, voteFor);
        vm.stopPrank();
    }

    function _acceptInvite(address _member, uint256 _voteId) internal {
        vm.startPrank(_member);
        sharedWallet.acceptInvitation(_voteId);
        vm.stopPrank();
    }

    function _addMember(address _member) internal {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(_member)
        );

        _vote(voteId, true, OWNER);

        (bool isUserMember, ) = sharedWallet.getMember(NEW_MEMBER);
        (bool isSecondUserMember, ) = sharedWallet.getMember(NEW_MEMBER_2);

        if (isUserMember) _vote(voteId, true, NEW_MEMBER);
        if (isSecondUserMember) _vote(voteId, true, NEW_MEMBER_2);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        _acceptInvite(_member, voteId);
    }

    modifier withNewMember(address _member) {
        _addMember(_member);
        _;
    }

    modifier withCreatedVote(uint160 data, uint256 typeOfVote) {
        _createVote(typeOfVote, data);
        _;
    }

    /////////////////////////////////////
    ///////////// TESTS ////////////////

    function test_InitialBalanceIsZero() public {
        assertEq(sharedWallet.getTotalAmountDeposited(), 0);
    }

    function test_initialNumberOfMembersIsOne() public {
        assertEq(sharedWallet.getNumberOfMembers(), 1);
    }

    function test_createVoteRevertsIfCalledByAnOutsidePerson() public {
        address outsidePerson = makeAddr("newMember");

        uint256 typeofVote = uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER);

        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWallet.SharedWallet__ShouldBeAMember.selector,
                outsidePerson
            )
        );
        vm.prank(outsidePerson);
        sharedWallet.createVote(typeofVote, uint160(OWNER));
    }

    function test_createVoteRevertsIfTheNewMemberIsAlreadyAMember() public {
        uint256 typeofVote = uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER);

        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWallet.SharedWallet__ShouldNotBeAMember.selector,
                OWNER
            )
        );

        _createVote(typeofVote, uint160(OWNER));
    }

    ////////////////////////////////////////////////
    ///////       Adding members tests      ////////

    function test_OwnerIsTheFirstMember() public {
        address expectedMember = address(OWNER);
        address[] memory actualMember = sharedWallet.getMembersLog();

        assertEq(expectedMember, actualMember[0]);
    }

    function test_canCreateAVoteToAddANewMember()
        public
        withCreatedVote(
            uint160(NEW_MEMBER),
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER)
        )
    {
        uint256 voteId = _generateVoteId(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER)
        );

        SharedWalletVoting.TypeOfVote expectedTypeOfVote = SharedWalletVoting
            .TypeOfVote
            .ADD_MEMBER;

        SharedWalletVoting.VoteStatus expectedStatus = SharedWalletVoting
            .VoteStatus
            .IN_PROGRESS;

        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        assertEq(uint256(typeOfVote), uint256(expectedTypeOfVote));
        assertEq(data, uint160(NEW_MEMBER));
        assertEq(author, OWNER);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 0);
        assertEq(uint256(expectedStatus), uint256(status));
    }

    function test_revertsIfTryingToAddANewMemberWithInvalidData() public {
        vm.expectRevert(
            SharedWalletVoting.SharedWalletVoting__InvalidData.selector
        );
        vm.prank(OWNER);
        sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(0)
        );
    }

    function test_canAddMember() public withNewMember(NEW_MEMBER) {
        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER
        );

        assertEq(isMember, true);
        assertEq(amountDeposited, 0);
    }

    ////////////////////////////////////
    ///////  DEPOSIT TESTS ////////////

    function test_revertsIfUserHasInsufficientFunds() public {
        vm.expectRevert();
        vm.prank(NEW_MEMBER);
        sharedWallet.depositIntoWallet{value: 5 ether}();
    }

    function test_MemberCanDepositIntoWallet() public {
        uint256 amountToDeposit = 5 ether;

        hoax(OWNER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        assertEq(sharedWallet.getAmountDeposited(OWNER), amountToDeposit);
        assertEq(sharedWallet.getTotalAmountDeposited(), amountToDeposit);
    }

    function test_everyMemberCanDepositIntoWallet()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;

        hoax(NEW_MEMBER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        assertEq(sharedWallet.getAmountDeposited(NEW_MEMBER), amountToDeposit);
        assertEq(sharedWallet.getTotalAmountDeposited(), amountToDeposit);

        hoax(OWNER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        assertEq(sharedWallet.getAmountDeposited(OWNER), amountToDeposit);
        assertEq(sharedWallet.getTotalAmountDeposited(), amountToDeposit * 2);
    }

    function test_depositRevertsIfTheAmountIsZero() public {
        vm.expectRevert(
            SharedWallet.SharedWallet__MustDepositMoreThanZero.selector
        );
        vm.prank(OWNER);
        sharedWallet.depositIntoWallet{value: 0}();
    }

    /////////////////////////////////
    /////// VOTE LOGIC TEST /////////

    function test_revertsIfWeTryToExecuteAPassedOrFailedVote()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWalletVoting
                    .SharedWalletVoting__VoteIsNotInProgress
                    .selector,
                voteId
            )
        );
        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);
    }

    function test_userCantVote2TimesOnTheSameVote()
        public
        withCreatedVote(
            uint160(NEW_MEMBER),
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER)
        )
    {
        uint256 voteId = _generateVoteId(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER)
        );

        _vote(voteId, true, OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWalletVoting
                    .SharedWalletVoting__UserHasAlreadyVoted
                    .selector,
                OWNER
            )
        );
        _vote(voteId, true, OWNER);
    }

    function test_voteShouldPassIfAllMemberVoteFor()
        public
        withNewMember(NEW_MEMBER)
    {
        vm.prank(OWNER);
        uint256 voteId = sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        console.log("owner", OWNER);
        console.log("new member", NEW_MEMBER);

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.prank(NEW_MEMBER_2);
        sharedWallet.acceptInvitation(voteId);

        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER_2
        );

        uint256 expectedTypeOfVote = uint256(
            SharedWalletVoting.TypeOfVote.ADD_MEMBER
        );

        //// NEW MEMBER ASSERTS
        assertEq(isMember, true);
        assertEq(amountDeposited, 0);

        //// VOTE ASSERTS
        assertEq(uint256(typeOfVote), expectedTypeOfVote);
        assertEq(data, uint160(NEW_MEMBER_2));
        assertEq(author, OWNER);
        assertEq(votesFor, 2);
        assertEq(votesAgainst, 0);
        assertEq(
            uint256(status),
            uint256(SharedWalletVoting.VoteStatus.PASSED)
        );
    }

    function test_voteShouldFailIfAllMembersVoteAgainstTheSameOption()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, false, OWNER);
        _vote(voteId, false, NEW_MEMBER);

        vm.startPrank(OWNER);
        sharedWallet.tryToExecute(voteId);
        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER_2
        );

        uint256 expectedTypeOfVote = uint256(
            SharedWalletVoting.TypeOfVote.ADD_MEMBER
        );

        //// NEW MEMBER ASSERTS
        assertEq(isMember, false);
        assertEq(amountDeposited, 0);

        //// VOTE ASSERTS
        assertEq(uint256(typeOfVote), expectedTypeOfVote);
        assertEq(data, uint160(NEW_MEMBER_2));
        assertEq(author, OWNER);
        assertEq(votesFor, 0);
        assertEq(votesAgainst, 2);
        assertEq(
            uint256(status),
            uint256(SharedWalletVoting.VoteStatus.FAILED)
        );
    }

    function test_shouldFailIfVotesForAreEqualToVotesAgains()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, false, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(NEW_MEMBER);
        sharedWallet.tryToExecute(voteId);

        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER_2
        );

        uint256 expectedTypeOfVote = uint256(
            SharedWalletVoting.TypeOfVote.ADD_MEMBER
        );

        //// NEW MEMBER ASSERTS
        assertEq(isMember, false);
        assertEq(amountDeposited, 0);

        //// VOTE ASSERTS
        assertEq(uint256(typeOfVote), expectedTypeOfVote);
        assertEq(data, uint160(NEW_MEMBER_2));
        assertEq(author, OWNER);
        assertEq(votesFor, 1);
        assertEq(votesAgainst, 1);
        assertEq(
            uint256(status),
            uint256(SharedWalletVoting.VoteStatus.FAILED)
        );
    }

    function test_voteWillSucceedIfMajorityVotesFor()
        public
        withNewMember(NEW_MEMBER)
        withNewMember(NEW_MEMBER_2)
        withCreatedVote(
            uint160(NEW_MEMBER_3),
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER)
        )
    {
        uint256 voteId = _generateVoteId(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_3)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);
        _vote(voteId, false, NEW_MEMBER_2);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.prank(NEW_MEMBER_3);
        sharedWallet.acceptInvitation(voteId);

        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER_3
        );

        uint256 expectedTypeOfVote = uint256(
            SharedWalletVoting.TypeOfVote.ADD_MEMBER
        );

        //// NEW MEMBER ASSERTS
        assertEq(isMember, true);
        assertEq(amountDeposited, 0);

        //// VOTE ASSERTS
        assertEq(uint256(typeOfVote), expectedTypeOfVote);
        assertEq(data, uint160(NEW_MEMBER_3));
        assertEq(author, OWNER);
        assertEq(votesFor, 2);
        assertEq(votesAgainst, 1);
        assertEq(
            uint256(status),
            uint256(SharedWalletVoting.VoteStatus.PASSED)
        );
    }

    function test_voteWillFailIfMajorityVotesAgains()
        public
        withNewMember(NEW_MEMBER)
        withNewMember(NEW_MEMBER_2)
        withCreatedVote(
            uint160(NEW_MEMBER_3),
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER)
        )
    {
        uint256 voteId = _generateVoteId(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_3)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, false, NEW_MEMBER);
        _vote(voteId, false, NEW_MEMBER_2);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        (
            SharedWalletVoting.TypeOfVote typeOfVote,
            uint160 data,
            address author,
            uint256 votesFor,
            uint256 votesAgainst,
            SharedWalletVoting.VoteStatus status
        ) = sharedWallet.getVote(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER_3
        );

        uint256 expectedTypeOfVote = uint256(
            SharedWalletVoting.TypeOfVote.ADD_MEMBER
        );

        //// NEW MEMBER ASSERTS
        assertEq(isMember, false);
        assertEq(amountDeposited, 0);

        //// VOTE ASSERTS
        assertEq(uint256(typeOfVote), expectedTypeOfVote);
        assertEq(data, uint160(NEW_MEMBER_3));
        assertEq(author, OWNER);
        assertEq(votesFor, 1);
        assertEq(votesAgainst, 2);
        assertEq(
            uint256(status),
            uint256(SharedWalletVoting.VoteStatus.FAILED)
        );
    }

    /////////////////////////////////////////////
    ///////  REMOVE MEMBER TESTS ///////////////

    function test_cantRemoveUserIfHeIsNotAMember() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWallet.SharedWallet__ShouldBeAMember.selector,
                NEW_MEMBER
            )
        );
        vm.prank(OWNER);
        sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.REMOVE_MEMBER),
            uint160(NEW_MEMBER)
        );
    }

    function test_canRemoveUser() public withNewMember(NEW_MEMBER) {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.REMOVE_MEMBER),
            uint160(NEW_MEMBER)
        );

        (bool beforeIsMember, ) = sharedWallet.getMember(NEW_MEMBER);

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        (bool afterIsMember, ) = sharedWallet.getMember(NEW_MEMBER);

        assertEq(afterIsMember, false);
        assertEq(beforeIsMember, true);
    }

    function test_whenRemovingUserHisFundsWillBeRefunded()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;

        hoax(NEW_MEMBER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.REMOVE_MEMBER),
            uint160(NEW_MEMBER)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        uint256 expectedBalance = 100 ether;

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        assertEq(NEW_MEMBER.balance, expectedBalance);
        assertEq(sharedWallet.getTotalAmountDeposited(), 0);
    }

    /////////////////////////////////////////////
    ///////  WITHDRAW FUNDS TESTS ///////////////

    function test_memberCanWithdrawFundsOnVote()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;

        hoax(NEW_MEMBER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        vm.prank(NEW_MEMBER);
        uint256 voteId = sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.WITHDRAW_FUNDS),
            uint160(amountToDeposit)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        uint256 expectedBalance = 100 ether;

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        (bool isMember, uint256 amountDeposited) = sharedWallet.getMember(
            NEW_MEMBER
        );

        assertEq(isMember, true);
        assertEq(amountDeposited, 0);
        assertEq(NEW_MEMBER.balance, expectedBalance);
        assertEq(sharedWallet.getTotalAmountDeposited(), 0);
    }

    function test_revertsWhenUserTriesToWithdrawFundsHeDoesnthave()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;
        hoax(OWNER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWallet.SharedWallet__MemberInsufficientFunds.selector
            )
        );
        vm.prank(NEW_MEMBER);
        sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.WITHDRAW_FUNDS),
            uint160(amountToDeposit)
        );
    }

    function test_MemberCantWithdrawMoreThanTheWalletBalance()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;
        hoax(NEW_MEMBER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        vm.expectRevert(
            abi.encodeWithSelector(
                SharedWallet.SharedWallet__MemberInsufficientFunds.selector
            )
        );
        vm.prank(NEW_MEMBER);
        sharedWallet.createVote(
            uint256(SharedWalletVoting.TypeOfVote.WITHDRAW_FUNDS),
            uint160(6 ether)
        );
    }

    //////////////////////////////////////////
    ///////  DESTROY WALLET TESTS ///////////

    function test_whenDestroyingWalletMembersGetRefund()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;

        hoax(NEW_MEMBER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        hoax(OWNER, 100 ether);
        sharedWallet.depositIntoWallet{value: amountToDeposit + 5 ether}();

        assertEq(sharedWallet.getNumberOfMembers(), 2);
        assertEq(sharedWallet.getTotalAmountDeposited(), 15 ether);

        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.DESTROY),
            uint160(0)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        assertEq(sharedWallet.getNumberOfMembers(), 0);
        assertEq(sharedWallet.getTotalAmountDeposited(), 0);
    }

    /////////////////////////////////////////
    ///////  INVITATION TESTS ///////////////

    function test_SharedWalletStorageSavesInvitation()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.prank(NEW_MEMBER_2);
        SharedWalletStorage.Invitation[] memory invitations = storageContract
            .userInvitations();

        SharedWalletStorage.Invitation memory currentInvitation = invitations[
            0
        ];

        assertEq(currentInvitation.voteId, voteId);
        assertEq(currentInvitation.user, NEW_MEMBER_2);
        assertEq(currentInvitation.wallet, address(sharedWallet));
    }

    function test_sharedWalletStorageSavesUserWhenInviteIsAccepted()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.prank(NEW_MEMBER_2);
        sharedWallet.acceptInvitation(voteId);

        vm.prank(NEW_MEMBER_2);
        SharedWalletStorage.Invitation[] memory invitations = storageContract
            .userInvitations();

        uint256 expectedStatus = uint256(
            SharedWalletStorage.InvitationStatus.ACCEPTED
        );

        assertEq(uint256(invitations[0].status), expectedStatus);
        assertEq(invitations.length, 1);

        vm.prank(NEW_MEMBER_2);
        address[] memory wallets = storageContract.userWallets();

        assertEq(wallets.length, 1);
        assertEq(wallets[0], address(sharedWallet));
    }

    function test_revertsIfOtherThanTheUserInvitedTriesToAcceptTheInvitation()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );

        _vote(voteId, true, OWNER);
        _vote(voteId, true, NEW_MEMBER);

        vm.prank(OWNER);
        sharedWallet.tryToExecute(voteId);

        vm.expectRevert(
            SharedWallet.SharedWallet__OnlyInviteeCanAcceptInvitation.selector
        );
        vm.prank(NEW_MEMBER);
        sharedWallet.acceptInvitation(voteId);
    }

    function test_revertsIfOtherThanWalletCreatesInvitation()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 voteId = _createVote(
            uint256(SharedWalletVoting.TypeOfVote.ADD_MEMBER),
            uint160(NEW_MEMBER_2)
        );
        vm.expectRevert(
            SharedWalletStorage
                .SharedWalletStorage__OnlyWalletCanCallThis
                .selector
        );
        vm.prank(NEW_MEMBER);
        storageContract.sendUserInvitation(NEW_MEMBER_2, voteId);
    }

    function test_onlyWalletCanRemoveInvitations()
        public
        withNewMember(NEW_MEMBER)
    {
        vm.expectRevert(
            SharedWalletStorage
                .SharedWalletStorage__OnlyWalletCanCallThis
                .selector
        );
        vm.prank(NEW_MEMBER);
        storageContract.updateInvitation(NEW_MEMBER_2, 1);
    }

    /////////////////////////////////////////
    /////// Leaving Wallet TESTS ///////////

    function test_userCanLeaveAndWillgetAllDepositedFundsBack()
        public
        withNewMember(NEW_MEMBER)
    {
        uint256 amountToDeposit = 5 ether;
        vm.deal(NEW_MEMBER, 100 ether);
        vm.startPrank(NEW_MEMBER);

        sharedWallet.depositIntoWallet{value: amountToDeposit}();

        sharedWallet.leave();

        vm.stopPrank();

        assertEq(NEW_MEMBER.balance, 100 ether);
        assertEq(sharedWallet.getTotalAmountDeposited(), 0);
        assertEq(sharedWallet.getNumberOfMembers(), 1);
    }
}
