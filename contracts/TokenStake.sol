pragma solidity ^0.7.0;
import "./TokenFactory.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract TokenStake {
    using SafeMath for uint256;

    TokenFactory tokenFactory;
    IBEP20 iart;
    mapping(address => uint256) numberOfStaked;
    mapping(uint256 => address) stakeToAddress;
    mapping(uint256 => TokenStake) stakeIdToStake;
    mapping(uint256 => uint256) accumulatedRewards;

    uint256 stakeCounter;
    uint256 public rewardCof = 10**16 * 3 * 10 * 50; // 15 IART per second
    uint256 public totalDistributed;
    address owner;
    bool stakingEnabled;
    uint256 public totalStakedValue;
    uint256 stakeUpdateCounter;

    event Harvest(address sender, uint256 amount);
    event AddedStake(address sender, uint256 stakeId);
    event RemovedStake(address sender, uint256 stakeId, uint256 rewardAmount);
    event RewardRateChanged(uint256 newRate);

    struct TokenStake {
        uint256 tokenId;
        uint256 startTime;
        uint256 stakeId;
        uint256 rewardCof;
        uint256 initialStartTime;
        uint256 tokenValue;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "ROWN");
        _;
    }

    constructor(
        address _owner,
        address styliart,
        address _tokenFactory
    ) {
        tokenFactory = TokenFactory(_tokenFactory);
        iart = IBEP20(styliart);
        stakingEnabled = true;
        owner = _owner;
    }

    function setBepAddress(address bep) external onlyOwner {
        iart = IBEP20(bep);
    }

    function withDraw() external onlyOwner {
        msg.sender.transfer(address(this).balance);
    }

    function setRewardCof(uint256 cof) external onlyOwner {
        rewardCof = cof;
        emit RewardRateChanged(cof);
    }

    function withdrawToken(address bep20) external onlyOwner {
        IBEP20 bep20 = IBEP20(bep20);
        bep20.transfer(owner, bep20.balanceOf(address(this)));
    }

    function addStake(uint256 tokenId) external {
        require(stakingEnabled, "NEABLD");
        require(tokenFactory.isSuper(tokenId), "NSPR");
        tokenFactory.safeTransferFrom(msg.sender, address(this), tokenId);

        uint256 _tokenValue = _valueOf(tokenId);
        totalStakedValue = totalStakedValue.add(_tokenValue);
        uint256 _reward = getCurrentInterestRate(_tokenValue);

        TokenStake memory _tokenStake = TokenStake(
            tokenId,
            block.timestamp,
            stakeCounter,
            _reward,
            block.timestamp,
            _tokenValue
        );
        stakeToAddress[stakeCounter] = msg.sender;
        stakeIdToStake[stakeCounter] = _tokenStake;
        emit AddedStake(msg.sender, stakeCounter);
        stakeCounter++;
        numberOfStaked[msg.sender]++;
        updateRates();
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 stakeId) external {
        require(stakeToAddress[stakeId] == msg.sender, "NOWN");

        TokenStake memory _tokenStake = stakeIdToStake[stakeId];
        _tokenStake.startTime = block.timestamp;
        stakeIdToStake[stakeId] = _tokenStake;
        delete stakeToAddress[_tokenStake.stakeId];
        numberOfStaked[msg.sender] = numberOfStaked[msg.sender].sub(1);
        totalStakedValue = totalStakedValue.sub(_tokenStake.tokenValue);

        tokenFactory.safeTransferFrom(
            address(this),
            msg.sender,
            _tokenStake.tokenId
        );
        emit RemovedStake(msg.sender, stakeId, 0);
    }

    function _valueOf(uint256 tokenId) internal view returns (uint256) {
        (, , , , , uint256 value) = tokenFactory.counterToToken(tokenId);
        return value;
    }

    function removeStake(uint256 stakeId) external {
        require(stakeToAddress[stakeId] == msg.sender, "NOWN");

        TokenStake memory _tokenStake = stakeIdToStake[stakeId];

        uint256 reward = calculateReward(
            _tokenStake.startTime,
            _tokenStake.rewardCof,
            stakeId
        );
        accumulatedRewards[stakeId] = 0;

        emit Harvest(msg.sender, reward);
        totalDistributed += reward;
        _tokenStake.startTime = block.timestamp;
        stakeIdToStake[stakeId] = _tokenStake;
        delete stakeToAddress[_tokenStake.stakeId];
        totalStakedValue = totalStakedValue.sub(_tokenStake.tokenValue);
        numberOfStaked[msg.sender] = numberOfStaked[msg.sender].sub(1);

        updateRates();
        require(iart.balanceOf(address(this)) >= reward, "FUND");
        require(iart.transfer(msg.sender, reward));
        tokenFactory.safeTransferFrom(
            address(this),
            msg.sender,
            _tokenStake.tokenId
        );

        emit RemovedStake(msg.sender, stakeId, reward);
        emit Harvest(msg.sender, reward);
    }

    function setStakingEnabled(bool _enabled) external onlyOwner {
        stakingEnabled = _enabled;
    }

    function getStakes(address stakeOwner)
        public
        view
        returns (
            uint256[] memory tokenId,
            uint256[] memory startTime,
            uint256[] memory stakeId,
            uint256[] memory currentReward
        )
    {
        uint256 count = numberOfStaked[stakeOwner];
        tokenId = new uint256[](count);
        startTime = new uint256[](count);
        stakeId = new uint256[](count);
        currentReward = new uint256[](count);

        uint256 _counter = 0;

        for (uint256 i = 0; i < stakeCounter; i++) {
            if (stakeToAddress[i] == stakeOwner) {
                tokenId[_counter] = stakeIdToStake[i].tokenId;
                startTime[_counter] = stakeIdToStake[i].startTime;
                stakeId[_counter] = stakeIdToStake[i].stakeId;
                currentReward[_counter] = calculateReward(
                    stakeIdToStake[i].startTime,
                    stakeIdToStake[i].rewardCof,
                    i
                );

                _counter++;
            }
        }

        return (tokenId, startTime, stakeId, currentReward);
    }

    function getCurrentInterestRate(uint256 value)
        public
        view
        returns (uint256)
    {
        if (totalStakedValue == 0) return rewardCof.mul(value);
        return rewardCof.mul(value).div(totalStakedValue);
        // (0.03 * 100 / 1000) * seconds
    }

    function calculateReward(
        uint256 startTime,
        uint256 _reward,
        uint256 stakeId
    ) public view returns (uint256) {
        uint256 time = block.timestamp - startTime;
        if (time > 30 days) {
            time = 30 days;
        }
        return time.mul(_reward).add(accumulatedRewards[stakeId]); // time *  (0.03 * 100 / 1000)
    }

    function updateAllRates() public {
        // VERY HIGH TRANSACTION COST
        for (uint256 i = 0; i < stakeCounter; i++) {
            if (stakeToAddress[i] != address(0)) {
                TokenStake memory stake = stakeIdToStake[i];
                accumulatedRewards[i] = calculateReward(
                    stake.startTime,
                    stake.rewardCof,
                    i
                );

                stake.rewardCof = getCurrentInterestRate(stake.tokenValue);
                stake.startTime = block.timestamp;
                stakeIdToStake[i] = stake;
            }
        }
    }

    function updateRates() public {
        uint256 startingValue = stakeUpdateCounter;
        uint256 interestRate = getCurrentInterestRate(1);
        for (uint256 i = 0; i < 30; i++) {
            if (stakeToAddress[stakeUpdateCounter] != address(0)) {
                TokenStake memory stake = stakeIdToStake[stakeUpdateCounter];
                accumulatedRewards[stakeUpdateCounter] = calculateReward(
                    stake.startTime,
                    stake.rewardCof,
                    stakeUpdateCounter
                );
                stake.rewardCof = interestRate.mul(stake.tokenValue);
                stake.startTime = block.timestamp;
                stakeIdToStake[stakeUpdateCounter] = stake;
            }

            stakeUpdateCounter += 1;
            if (stakeUpdateCounter == stakeCounter) stakeUpdateCounter = 0;
            if (stakeUpdateCounter == startingValue && i != 0) break;
        }
    }

    function claimRewards() external returns (bool) {
        (
            ,
            ,
            uint256[] memory stakeId,
            uint256[] memory currentReward
        ) = getStakes(msg.sender);

        uint256 reward = 0;
        for (uint256 i = 0; i < stakeId.length; i++) {
            accumulatedRewards[stakeId[i]] = 0;
            stakeIdToStake[stakeId[i]].startTime = block.timestamp;
            stakeIdToStake[stakeId[i]].rewardCof = getCurrentInterestRate(
                stakeIdToStake[stakeId[i]].tokenValue
            );
            reward = reward.add(currentReward[i]);
        }
        totalDistributed += reward;
        updateRates();

        require(iart.balanceOf(address(this)) >= reward, "FUND");
        require(iart.transfer(msg.sender, reward));

        emit Harvest(msg.sender, reward);
        return true;
    }
}
