// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract YieldZillaLottery is VRFConsumerBaseV2, Ownable, Pausable {
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId = 431;
    address vrfCoordinator = 0x6A2AAd07396B36Fe02a22b33cf443582f682c82f;
    bytes32 keyHash =
        0xd4bb89654db74673a187bd804519e65e3f71a52bc55f11da7601a13dcf505314;
    uint32 callbackGasLimit = 50000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    mapping(uint256 => uint256[]) public s_randomWords;
    uint256 public s_requestId;

    uint256 public lotteryID = 1;
    mapping(uint256 => address) lotteryWinners;
    mapping(uint256 => uint256) potSizes;
    mapping(uint256 => uint256) endTimes;

    address[] public players;

    address public tokenAddress = 0xd9bf3776c5E110e621d1A3Ae43FD59801290e547;
    IERC20 token;

    address public marketingAddress =
        0x9D507b2Da9BB4C15ca90b40721768E2da17d49b6;
    address public blackHoleAddress =
        0x0deaDBEEf00deadBeEf00DEADBEef00DeAdBeEf0;

    uint256 public maxTicketsPerPlayer = 100;
    mapping(uint256 => mapping(address => uint256)) public numTicketsBought;

    uint256 public winnerShare = 500;
    uint256 public marketingShare = 250;
    uint256 public blackHoleShare = 250;
    uint256 public shareDenominator = 1000;

    constructor() VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        token = IERC20(tokenAddress);
        _pause();
    }

    function totalEntries() external view returns (uint256) {
        return players.length;
    }

    function pastEntries(uint256 _id) external view returns (uint256) {
        return potSizes[_id];
    }

    function userEntries(address user) external view returns (uint256) {
        return numTicketsBought[lotteryID][user];
    }

    function previousWinner() external view returns (address) {
        require(lotteryID > 1, "No winners yet");
        return lotteryWinners[lotteryID - 1];
    }

    function pastWinner(uint256 _id) external view returns (address) {
        require(_id < lotteryID, "No winner yet");
        return lotteryWinners[_id];
    }

    function endTime(uint256 _id) external view returns (uint256) {
        return endTimes[_id];
    }

    function isActive() external view returns (bool) {
        return (endTimes[lotteryID] > block.timestamp) && !paused();
    }

    function enter(uint256 tickets) external whenNotPaused {
        require(tickets > 0, "Must make at least one entry");
        require(
            tickets + numTicketsBought[lotteryID][msg.sender] <=
                maxTicketsPerPlayer,
            "Too many tickets for this player"
        );
        require(endTimes[lotteryID] > block.timestamp, "Lottery is over");

        numTicketsBought[lotteryID][msg.sender] += tickets;

        for (uint256 i = 0; i < tickets; i++) {
            players.push(msg.sender);
        }

        token.transferFrom(msg.sender, address(this), tickets * 10**5);
    }

    function start(uint256 _endTime) external onlyOwner {
        require(_endTime > block.timestamp, "End time must be in the future");
        endTimes[lotteryID] = _endTime;
        _unpause();
    }

    function pickWinner() external onlyOwner {
        require(players.length > 0);
        require(block.timestamp >= endTimes[lotteryID], "Lottery is not over");

        _pause();
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        potSizes[lotteryID] = players.length;
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords)
        internal
        override
    {
        s_randomWords[lotteryID] = randomWords;
    }

    function payoutLottery() external onlyOwner {
        require(s_randomWords[lotteryID][0] > 0, "Randomness not set");

        if (players.length > 0) {
            uint256 totalAmount = players.length * 10**5;
            uint256 winnerAmount = (totalAmount * winnerShare) /
                shareDenominator;
            uint256 marketingAmount = (totalAmount * marketingShare) /
                shareDenominator;
            uint256 blackHoleAmount = totalAmount -
                winnerAmount -
                marketingAmount;

            uint256 index = s_randomWords[lotteryID][0] % players.length;
            lotteryWinners[lotteryID] = players[index];

            token.transfer(players[index], winnerAmount);
            token.transfer(marketingAddress, marketingAmount);
            token.transfer(blackHoleAddress, blackHoleAmount);
        }
        lotteryID++;
        players = new address[](0);
    }
}
