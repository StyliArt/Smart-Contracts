pragma solidity ^0.7.0;

import "../AuctionManager.sol";
import "../StockManager.sol";
import "../Auction.sol";
import "../TokenFactory.sol";

contract StyliOracle {
    TokenFactory tokenFactory;
    AuctionManager auctionManager;
    StockManager stockManager;

    constructor(
        address _tokenFactory,
        address _auctionManager,
        address _stockManager
    ) {
        tokenFactory = TokenFactory(_tokenFactory);
        auctionManager = AuctionManager(_auctionManager);
        stockManager = StockManager(_stockManager);
    }

    enum TokenType {
        IMAGE_TOKEN,
        STYLE_TOKEN,
        SUPER_TOKEN
    }

    struct SuperTkn {
        uint256 counterId;
        uint256 imageId;
        uint256 styleId;
        TokenType tokenType;
        bool listed;
        uint256 root;
        uint256 value;
    }

    function getPacksByOwnerV2(uint256[] calldata tokenIds)
        external
        view
        returns (
            uint256[] memory counterId_list,
            uint256[] memory imageId_list,
            uint256[] memory styleId_list,
            TokenFactory.TokenType[] memory tokenType_list,
            uint256[] memory root_list,
            uint256[] memory rank
        )
    {
        counterId_list = new uint256[](tokenIds.length);
        imageId_list = new uint256[](tokenIds.length);
        styleId_list = new uint256[](tokenIds.length);
        tokenType_list = new TokenFactory.TokenType[](tokenIds.length);
        root_list = new uint256[](tokenIds.length);
        rank = new uint256[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            (
                counterId_list[i],
                imageId_list[i],
                styleId_list[i],
                tokenType_list[i],
                root_list[i],
                rank[i]
            ) = tokenFactory.counterToToken(tokenIds[i]);
        }
        return (
            counterId_list,
            imageId_list,
            styleId_list,
            tokenType_list,
            root_list,
            rank
        );
    }

    function countersToPainters(uint256[] calldata tokenIds)
        external
        view
        returns (uint256[] memory counterToPainter)
    {
        counterToPainter = new uint256[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            counterToPainter[i] = tokenFactory.counterToPainter(i);
        }
        return (counterToPainter);
    }

    function getAuctionInfo(address[] calldata auctions)
        external
        view
        returns (
            uint256[] memory directBuy,
            uint256[] memory auctionId,
            address[] memory owner,
            uint256[] memory highestBid,
            uint256[] memory reasonCancel,
            uint256[] memory tokenIds,
            uint256[] memory endTime
        )
    {
        directBuy = new uint256[](auctions.length);
        auctionId = new uint256[](auctions.length);
        owner = new address[](auctions.length);
        highestBid = new uint256[](auctions.length);
        reasonCancel = new uint256[](auctions.length);
        tokenIds = new uint256[](auctions.length);
        endTime = new uint256[](auctions.length);

        for (uint256 i = 0; i < auctions.length; i++) {
            directBuy[i] = Auction(auctions[i]).directBuy();
            auctionId[i] = Auction(auctions[i]).auctionId();
            owner[i] = Auction(auctions[i]).owner();
            highestBid[i] = Auction(auctions[i]).highestBid();
            reasonCancel[i] = Auction(auctions[i]).getReasonCancel();
            tokenIds[i] = Auction(auctions[i]).tokenId();
            endTime[i] = Auction(auctions[i]).endTime();
        }
        return (
            directBuy,
            auctionId,
            owner,
            highestBid,
            reasonCancel,
            tokenIds,
            endTime
        );
    }

    function getAuctionInfoV2(address[] calldata auctions)
        external
        view
        returns (
            uint256[] memory coinType,
            address[] memory bepAddress,
            uint256[] memory startPrice,
            bool[] memory ownerHasWithdrawn,
            bool[] memory fundsWithdrawn,
            uint256[] memory minIncrease
        )
    {
        coinType = new uint256[](auctions.length);
        bepAddress = new address[](auctions.length);
        startPrice = new uint256[](auctions.length);
        ownerHasWithdrawn = new bool[](auctions.length);
        fundsWithdrawn = new bool[](auctions.length);
        minIncrease = new uint256[](auctions.length);

        for (uint256 i = 0; i < auctions.length; i++) {
            coinType[i] = Auction(auctions[i]).coinType();
            bepAddress[i] = Auction(auctions[i]).bepAddress();
            startPrice[i] = Auction(auctions[i]).startPrice();

            ownerHasWithdrawn[i] = Auction(auctions[i]).ownerHasWithdrawn();
            fundsWithdrawn[i] = Auction(auctions[i]).fundsWithdrawn();
            minIncrease[i] = Auction(auctions[i]).minIncrease();
        }
        return (
            coinType,
            bepAddress,
            startPrice,
            ownerHasWithdrawn,
            fundsWithdrawn,
            minIncrease
        );
    }
}
