pragma solidity ^0.7.0;

import "./TokenFactory.sol";
import "./Auction.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

contract AuctionManager {
    uint256 public auctionCounter;
    mapping(uint256 => Auction) public idToAuction;
    mapping(address => bool) public paymentAvailable;
    uint256 public auctionCost = 0.001 ether;
    TokenFactory tokenFactory;
    using SafeMath for uint256;
    address owner;
    address StyliArtTokenAddress;
    bool auctionsEnabled;

    // Withdraws current balance
    function withdraw() external {
        require(msg.sender == owner, "NOWN");
        address payable _owner = address(uint160(owner));
        _owner.transfer(address(this).balance);
    }

    function withdrawBep20Token(address erc20) external {
        require(msg.sender == owner, "NOWN");
        IBEP20 bep20 = IBEP20(erc20);
        bep20.transfer(owner, bep20.balanceOf(address(this)));
    }

    function setStyliArtTokenAddress(address styliArtTokenAddress) external {
        require(msg.sender == owner, "NOWN");
        StyliArtTokenAddress = styliArtTokenAddress;
    }

    function setEnabled(bool _enabled) external {
        require(msg.sender == owner, "NAWN");
        auctionsEnabled = _enabled;
    }

    function setAuctionFeeCost(uint256 _cost) external {
        require(msg.sender == owner, "NAWN");
        auctionCost = _cost;
    }

    // EVENTS
    event AuctionCreatedEvent(
        address indexed sender,
        uint256 auctionId,
        uint256 tokenId
    );

    event OwnerWithdrawal(
        address withdrawer,
        uint256 amount,
        uint256 auctionId,
        uint256 coinType
    );

    event TokenWithdrawal(
        address withdrawer,
        uint256 tokenId,
        uint256 auctionId
    );

    event AuctionCancelled(address owner, uint256 auctionId, uint256 tokenId);
    event NewBid(
        address bidder,
        uint256 bid,
        address auction,
        uint256 coinType
    );

    modifier requireOwnership(uint256 id) {
        require(
            tokenFactory.ownerOf(id) == msg.sender,
            "You are not the owner"
        );
        _;
    }

    modifier requireValue(uint256 cost) {
        require(msg.value >= cost, "Not enough balance"); // Check if balance is enough
        _;
    }

    constructor(address _tokenFactory) {
        tokenFactory = TokenFactory(_tokenFactory);
        owner = msg.sender;
        auctionsEnabled = true;
    }

    function setPaymentAvailable(address erc, bool res)
        external
        returns (bool)
    {
        require(msg.sender == owner, "NOWN");
        paymentAvailable[erc] = res;
        return true;
    }

    function newBid(
        uint256 auctionId,
        uint256 bid,
        address bidder,
        uint256 coinType
    ) external {
        Auction auction = Auction(idToAuction[auctionId]);
        require(msg.sender == address(auction), "whoru");
        emit NewBid(bidder, bid, msg.sender, coinType);
    }

    function ownerWithdrawalEvent(
        uint256 auctionId,
        uint256 amount,
        address withDrawer,
        uint256 coinType
    ) external {
        Auction auction = Auction(idToAuction[auctionId]);
        require(msg.sender == address(auction), "whoru");

        emit OwnerWithdrawal(withDrawer, amount, auctionId, coinType);
    }

    function getAuctionAddr(uint256 id) external view returns (address) {
        return address(idToAuction[id]);
    }

    function startAuction(
        uint256 tokenId,
        uint256 directBuy,
        uint256 startPrice,
        uint256 duration,
        uint256 coinType,
        address coinAddress,
        uint256 minIncrease
    ) external payable requireOwnership(tokenId) requireValue(auctionCost) {
        require(auctionsEnabled, "NABLED");
        require(directBuy > startPrice, "TDE5");
        require(
            duration == 7 days || duration == 14 days || duration == 30 days,
            "INVDR"
        );
        require(tokenFactory.isSuper(tokenId), "NSPR");
        if (coinType != 1) {
            require(paymentAvailable[coinAddress], "NAWB");
            if (coinAddress == StyliArtTokenAddress) {
                coinType = 2;
            } else {
                coinType = 3;
            }
        }

        idToAuction[auctionCounter] = new Auction(
            msg.sender,
            startPrice,
            duration,
            tokenId,
            directBuy,
            auctionCounter,
            coinType,
            coinAddress,
            owner,
            minIncrease
        );

        emit AuctionCreatedEvent(msg.sender, auctionCounter, tokenId);
        auctionCounter = auctionCounter + 1;
        tokenFactory.safeTransferFrom(msg.sender, address(this), tokenId);
    }

    function getAllAuctions() external view returns (address[] memory) {
        address[] memory auctions = new address[](auctionCounter);
        for (uint256 i = 0; i < auctionCounter; i++) {
            auctions[i] = address(idToAuction[i]);
        }
        return auctions;
    }

    function getAuctionsBy(address auctionOwner)
        external
        view
        returns (address[] memory)
    {
        address[] memory auctions = new address[](auctionCounter);
        uint256 counter = 0;
        for (uint256 i = 0; i < auctionCounter; i++) {
            if (idToAuction[i].owner() == auctionOwner) {
                auctions[counter] = address(idToAuction[i]);
                counter++;
            }
        }
        return auctions;
    }

    function withDrawToken(uint256 auctionId) external returns (bool) {
        Auction auction = Auction(idToAuction[auctionId]);
        require(msg.sender == address(auction), "whoru"); // Sender must be the auction contract

        tokenFactory.safeTransferFrom(
            address(this),
            auction.highestBidder(),
            auction.tokenId()
        );
        emit TokenWithdrawal(
            auction.highestBidder(),
            auction.tokenId(),
            auctionId
        );
        return true;
    }

    function cancelAuction(uint256 auctionId) external returns (bool) {
        Auction auction = Auction(idToAuction[auctionId]);
        require(msg.sender == address(auction), "whoru"); // Sender must be the auction contract
        require(auction.highestBid() == 0, "Na");

        tokenFactory.safeTransferFrom(
            address(this),
            auction.owner(),
            auction.tokenId()
        );
        emit AuctionCancelled(auction.owner(), auctionId, auction.tokenId());
        return true;
    }
}
