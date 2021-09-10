pragma solidity ^0.7.0;
import "./AuctionManager.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract Auction {
    // Static
    IBEP20 bep20Token;
    using SafeMath for uint256;
    address public owner;
    uint256 public directBuy;
    uint256 public startPrice;
    uint256 public tokenId;
    uint256 public auctionId;
    address fatherAddress;

    uint256 public coinType;
    address public bepAddress;
    uint256 public minIncrease;

    AuctionManager auctionContract;

    enum ReasonCancel {
        TIMED_OUT,
        DIRECT_BUY,
        CANCELLED,
        NOTHING
    }

    // State
    address public highestBidder;
    address contractOwner;
    uint256 public highestBid;
    uint256 public endTime;
    ReasonCancel reasonCancel;
    bool public ownerHasWithdrawn;
    bool public fundsWithdrawn;

    struct Bid {
        address sender;
        uint256 bid;
    }

    Bid[] public bids;

    // Helpful modifiers
    modifier notFinished {
        require(
            reasonCancel == ReasonCancel.NOTHING,
            "This Auction has been cancelled"
        );
        require(block.number <= endTime, "This Auction has been ended");
        _;
    }

    modifier finished {
        require(
            block.number > endTime || reasonCancel != ReasonCancel.NOTHING,
            "This Auction is still active"
        );
        _;
    }

    function getReasonCancel() external view returns (uint256) {
        if (block.number > endTime) {
            return uint256(ReasonCancel.TIMED_OUT);
        }
        return uint256(reasonCancel);
    }

    modifier onlyAuctionOwner(address sender) {
        require(owner == sender, "NBOWN");
        _;
    }

    modifier onlyNotOwner {
        require(owner != msg.sender, "OWNCANT");
        _;
    }

    modifier hasHighestBid(address sender) {
        require(highestBidder == sender, "NOTHIGH");
        _;
    }
    event NewBid(address bidder, uint256 bid);

    constructor(
        address _owner,
        uint256 _startPrice,
        uint256 _duration,
        uint256 _tokenId,
        uint256 _directBuy,
        uint256 _auctionId,
        uint256 _coinType,
        address _bep20TokenAddress,
        address _contractOwner,
        uint256 _minIncrease
    ) {
        owner = _owner; // Auction owner
        highestBidder = _owner;

        endTime = block.number + _duration;
        tokenId = _tokenId;
        startPrice = _startPrice;
        directBuy = _directBuy;
        highestBid = 0;
        fatherAddress = msg.sender;
        auctionContract = AuctionManager(msg.sender);
        auctionId = _auctionId;
        reasonCancel = ReasonCancel.NOTHING;
        bepAddress = _bep20TokenAddress;

        coinType = _coinType;
        bep20Token = IBEP20(_bep20TokenAddress);
        contractOwner = _contractOwner;
        minIncrease = _minIncrease;
    }

    /**
     * @dev Returns a list of all bids and addresses
     */
    function allBids()
        external
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addrs = new address[](bids.length);
        uint256[] memory bidPrice = new uint256[](bids.length);
        for (uint256 i = 0; i < bids.length; i++) {
            addrs[i] = bids[i].sender;
            bidPrice[i] = bids[i].bid;
        }
        return (addrs, bidPrice);
    }

    /**
     * @dev Function to place a bid on auction
     *
     * In case the cointype is a bep20 token, amount must be used to set bid value.
     */
    function placeBid(uint256 amount)
        external
        payable
        notFinished
        onlyNotOwner
        returns (bool success)
    {
        uint256 value = 0;

        if (coinType != 1) {
            require(amount > highestBid && amount > startPrice, "Low bet");
            require(bep20Token.balanceOf(msg.sender) >= amount, "NAOH");
            uint256 allowance = bep20Token.allowance(msg.sender, address(this));
            require(allowance >= amount, "CALW");
            require(
                bep20Token.transferFrom(msg.sender, address(this), amount),
                "SMGTWNG"
            );
            value = amount;
        } else {
            require(
                msg.value > highestBid && msg.value > startPrice,
                "Low bet"
            );
            value = msg.value;
        }

        require(
            value >= directBuy || (value - highestBid >= minIncrease),
            "NMIN"
        );

        address lastHightestBidder = highestBidder;
        uint256 lastHighestBid = highestBid;

        if (value >= directBuy) {
            highestBid = directBuy;
            highestBidder = msg.sender;
            reasonCancel = ReasonCancel.DIRECT_BUY;
            if (value > directBuy) {
                // refund extra coins
                if (coinType == 1) {
                    msg.sender.transfer(value.sub(directBuy)); // refunds extra bnb
                    value = directBuy;
                } else {
                    require(
                        bep20Token.transfer(msg.sender, value.sub(directBuy))
                    ); // refunds extra bep20
                    value = directBuy;
                }
            }
        } else {
            highestBidder = msg.sender;
            highestBid = value;
        }

        bids.push(Bid(msg.sender, value));
        emit NewBid(msg.sender, value);
        auctionContract.newBid(auctionId, value, msg.sender, coinType); // Triggers event
        if (bids.length > 1) {
            if (coinType == 1) {
                address(uint160(lastHightestBidder)).transfer(lastHighestBid); // refund bnb
            } else {
                require(
                    bep20Token.transfer(lastHightestBidder, lastHighestBid)
                ); // refund other bep20 token
            }
        }

        return true;
    }

    /**
     * @dev  Owner can take the auction fee after auction ends
     */
    function withdrawContract() external finished {
        require(msg.sender == contractOwner);
        address payable _owner = address(uint160(contractOwner));
        _owner.transfer(address(this).balance);
    }

    /**
     * @dev  Owner can take the fee after auction ends
     */
    function withdrawToken(address erc20) external finished {
        require(msg.sender == contractOwner);
        IBEP20 bep20 = IBEP20(erc20);
        bep20.transfer(contractOwner, bep20.balanceOf(address(this)));
    }

    /**
     * @dev Let's the auction creator withdraw funds if the auction has completed.
     *
     * Requirements
     *
     * - `msg.sender` must be the owner
     * - Auction must be finished.
     */
    function withdraw()
        external
        onlyAuctionOwner(msg.sender)
        finished
        returns (bool success)
    {
        require(fundsWithdrawn == false, "AWDWN");
        fundsWithdrawn = true; // Set fundswithdrawn to true
        uint256 gonnaWithdraw = 0;
        uint256 withDrawFee = 0;

        if (coinType == 2) {
            gonnaWithdraw = highestBid;
            withDrawFee = 0; // There is no fee if $IART used.
        } else {
            withDrawFee = (highestBid * 3) / 100; // 3% percent fee.
            gonnaWithdraw = highestBid - withDrawFee;
        }

        if (coinType == 1) {
            address(uint160(msg.sender)).transfer(gonnaWithdraw); // Transfer BNB to owner.
        } else {
            require(bep20Token.transfer(msg.sender, gonnaWithdraw)); // Transfer any BEP20 token to owner.
        }
        auctionContract.ownerWithdrawalEvent(
            auctionId,
            gonnaWithdraw,
            msg.sender,
            coinType
        );
        return true;
    }

    /**
     * @dev Let's the highestBidder withdraw the token if the auction has completed.
     *
     * Requirements
     *
     * - `msg.sender` must be the highestBidder
     * - Auction must be finished.
     */
    function ownerWithdrawn() external finished hasHighestBid(msg.sender) {
        require(ownerHasWithdrawn == false, "AWDN");
        ownerHasWithdrawn = true;
        bool done = auctionContract.withDrawToken(auctionId);
        require(done, "DD");
    }

    function cancelAuction() external notFinished returns (bool success) {
        require(owner == msg.sender, "Not creator");
        require(highestBid == 0, "UCANT"); // Do not let cancel if there is a bidder.
        reasonCancel = ReasonCancel.CANCELLED; // Set cancel reason to ReasonCancel.CANCELLED
        ownerHasWithdrawn = true;
        fundsWithdrawn = true;
        highestBid = 0;
        bool done = auctionContract.cancelAuction(auctionId); // Cancel auction on AuctionManager contract.
        require(done, "smmts");
        return true;
    }
}
