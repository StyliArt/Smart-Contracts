pragma solidity ^0.7.0;
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract Vault {
    uint256 public unlockTime;
    uint256 public maxWithdrawalLimit = 1000000000 ether;
    uint256 public withdrawalTimeout = 1 days;
    uint256 public latestWithdrawal;

    mapping(address => bool) public ownerMap;
    mapping(uint256 => address) public idToOwner;

    mapping(uint256 => WithdrawReq) public requests;
    mapping(address => mapping(uint256 => bool)) public approvals;
    mapping(uint256 => bool) requestCompleted;

    uint256 public requestCount;
    uint256 public ownerCount;
    address public admin;

    event Approval(address owner, uint256 requestId);
    event NewRequest(
        uint256 requestId,
        address bep20,
        uint256 amount,
        address requester
    );
    event Withdraw(
        uint256 requestId,
        address bep20,
        uint256 amount,
        address requester
    );
    event OwnerAdded(address newOwner);

    struct WithdrawReq {
        uint256 requestId;
        address bep20;
        uint256 amount;
        address requester;
    }

    modifier isUnlocked {
        require(block.timestamp > unlockTime, "LCKD");
        _;
    }

    modifier isOwner {
        require(ownerMap[msg.sender], "NOWN");
        _;
    }

    modifier isApproved(uint256 _requestId) {
        require(requestCompleted[_requestId] != true, "CMPLTD");
        bool _approved = true;
        for (uint256 i = 0; i < ownerCount; i++) {
            if (
                approvals[idToOwner[i]][_requestId] != true &&
                idToOwner[i] != address(0)
            ) _approved = false;
        }
        require(_approved, "NAPPRVD");
        _;
    }

    constructor() {
        admin = msg.sender;
        _addOwner(msg.sender);
        unlockTime = block.timestamp + 180 days;
    }

    function addOwner(address newOwner) external isOwner {
        require(msg.sender == admin);
        _addOwner(newOwner);
    }

    function _addOwner(address newOwner) internal {
        ownerMap[newOwner] = true;
        idToOwner[ownerCount] = newOwner;
        ownerCount++;
        emit OwnerAdded(newOwner);
    }

    function getConfirmations(uint256 requestId)
        external
        view
        returns (address[] memory owners, bool[] memory approved)
    {
        owners = new address[](ownerCount);
        approved = new bool[](ownerCount);

        for (uint256 i = 0; i < ownerCount; i++) {
            owners[i] = idToOwner[i];
            approved[i] = approvals[owners[i]][requestId];
        }

        return (owners, approved);
    }

    function getRequests(uint256[] calldata requestIds)
        external
        view
        returns (
            uint256[] memory requestIdArray,
            address[] memory bep20Array,
            uint256[] memory amountArray,
            address[] memory requesterArray
        )
    {
        requestIdArray = new uint256[](requestIds.length);
        bep20Array = new address[](requestIds.length);
        amountArray = new uint256[](requestIds.length);
        requesterArray = new address[](requestIds.length);

        for (uint256 i = 0; i < requestIds.length; i++) {
            requestIdArray[i] = requests[i].requestId;
            bep20Array[i] = requests[i].bep20;
            amountArray[i] = requests[i].amount;
            requesterArray[i] = requests[i].requester;
        }

        return (requestIdArray, bep20Array, amountArray, requesterArray);
    }

    function withdrawRequest(address bep20, uint256 amount)
        external
        isOwner
        isUnlocked
    {
        require(amount <= maxWithdrawalLimit, "OVERLIMIT");
        require(bep20 != address(0));
        WithdrawReq memory withdrawReq = WithdrawReq(
            requestCount,
            bep20,
            amount,
            msg.sender
        );
        emit NewRequest(requestCount, bep20, amount, msg.sender);
        requests[requestCount] = withdrawReq;
        approvals[msg.sender][requestCount] = true;
        requestCount++;
    }

    function approveRequest(uint256 requestId) external isOwner {
        require(requestId < requestCount, "NO");
        approvals[msg.sender][requestId] = true;
        emit Approval(msg.sender, requestId);
    }

    function processWithdraw(uint256 requestId)
        external
        isOwner
        isUnlocked
        isApproved(requestId)
    {
        require(block.timestamp > latestWithdrawal + withdrawalTimeout, "NTM");
        latestWithdrawal = block.timestamp;
        requestCompleted[requestId] = true;
        WithdrawReq memory withdrawReq = requests[requestId];
        IBEP20 iart = IBEP20(withdrawReq.bep20);
        uint256 amount = withdrawReq.amount;
        require(iart.transfer(withdrawReq.requester, amount));
        emit Withdraw(
            requestId,
            withdrawReq.bep20,
            amount,
            withdrawReq.requester
        );
    }
}
