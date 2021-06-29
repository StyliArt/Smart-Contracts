pragma solidity ^0.7.0;

import "./ERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "./StockManager.sol";

contract TokenFactory is IERC721, ERC165, IERC721Enumerable {
    // Safe math implementation
    using SafeMath for uint256;

    // Helpful modifiers
    modifier onlyOwner {
        require(msg.sender == _contractOwner);
        _;
    }

    modifier requireValue(uint256 cost) {
        require(msg.value >= cost, "Not enough balance"); // Check if balance is enough
        _;
    }

    modifier packStock(uint256 packId) {
        require(stockManager.availableStock(packId), "Out of stock");
        _;
    }
    // Events
    event MergeEvent(
        address indexed owner,
        uint256 indexed imageId,
        uint256 indexed styleId,
        uint256 tokenId
    );
    event SplitEvent(
        address indexed sender,
        uint256 id,
        uint256 indexed imageId,
        uint256 indexed styleId,
        uint256 tokenId
    );
    event BuyEvent(address indexed sender, uint256 packId);

    address private _contractOwner;
    uint256 public tokenCounter;
    StockManager stockManager;

    // Important
    uint256 constant SEPERATION_COST = 0.001 ether; // Style-Image seperation cost

    enum TokenType {
        IMAGE_TOKEN,
        STYLE_TOKEN,
        SUPER_TOKEN
    }

    // Token structs
    struct SuperTkn {
        uint256 counterId;
        uint256 imageId;
        uint256 styleId;
        TokenType tokenType;
        uint256 root;
        uint256 value;
    }

    struct SuperData {
        uint256 icid;
        uint256 scid;
        uint256 iroot;
        uint256 sroot;
    }

    mapping(uint256 => address) public counterToAddress;
    mapping(address => uint256) public numberOfTokensOwned; // Number of tokens owned by user, for loop purposes
    mapping(uint256 => SuperTkn) public counterToToken;
    mapping(uint256 => SuperData) public superToRoot;
    mapping(uint256 => uint256) public painterIdToPrice;
    mapping(uint256 => uint256) public counterToPainter;

    // ERC721
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => address) private styliApprovals;

    // Constructor
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;
    string private _baseURI;

    constructor() {
        _contractOwner = msg.sender;
        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }

    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    function _setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */

    modifier requireOwnership(uint256 tokenId) {
        require(
            counterToAddress[tokenId] == msg.sender,
            "You are not the owner"
        );
        _;
    }

    function _isApprovedOrOwner(uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(tokenCounter > tokenId, "NXN");
        address owner = counterToAddress[tokenId];
        return (msg.sender == owner ||
            styliApprovals[tokenId] == msg.sender ||
            isApprovedForAll(owner, msg.sender));
    }

    function getApproved(uint256 tokenId)
        external
        view
        virtual
        override
        returns (address operator)
    {
        require(tokenCounter > tokenId, "NONEXST");
        return styliApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved)
        external
        virtual
        override
    {
        require(operator != msg.sender, "ERC721:ATC");

        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }

    function tokenURI(uint256 tokenId)
        external
        view
        virtual
        returns (string memory)
    {
        require(tokenCounter > tokenId, "NONEXST");
        string memory base = baseURI();
        return string(abi.encodePacked(base, uint2str(tokenId)));
    }

    function setPainter(uint256 index, uint256 price) external onlyOwner {
        painterIdToPrice[index] = price;
    }

    function name() external view returns (string memory _name) {
        return "StyliArt";
    }

    function symbol() external view returns (string memory _symbol) {
        return "STYLIART";
    }

    function totalSupply() external view override returns (uint256) {
        return tokenCounter;
    }

    function tokenByIndex(uint256 index)
        external
        view
        override
        returns (uint256)
    {
        require(tokenCounter > index, "NXN");
        return index;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        override
        returns (uint256 tokenId)
    {
        uint256[] memory owned = getPacksByOwner(owner);
        return owned[index];
    }

    function setAddress(address _stockManager) external onlyOwner {
        if (_stockManager != address(0)) {
            stockManager = StockManager(_stockManager);
        }
    }

    function getAddrStockManager() external view returns (address) {
        return address(stockManager);
    }

    function _transferInternal(
        address _from,
        address _to,
        uint256 tokenId
    ) internal {
        counterToAddress[tokenId] = _to;
        numberOfTokensOwned[_from] = numberOfTokensOwned[_from].sub(1);
        numberOfTokensOwned[_to] = numberOfTokensOwned[_to].add(1);
        emit Transfer(_from, _to, tokenId);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 tokenId
    ) external virtual override {
        require(_isApprovedOrOwner(tokenId), "NBN");
        _transferInternal(_from, _to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) external virtual override {
        require(_isApprovedOrOwner(tokenId), "NBN");
        _transferInternal(from, to, tokenId);
        require(counterToAddress[tokenId] == to);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external override {
        require(_isApprovedOrOwner(tokenId), "NBN");
        _transferInternal(from, to, tokenId);
        require(counterToAddress[tokenId] == to);
    }

    function approve(address _approved, uint256 _tokenId)
        external
        override
        requireOwnership(_tokenId)
    {
        styliApprovals[_tokenId] = _approved;
        emit Approval(msg.sender, _approved, _tokenId);
    }

    function getPacksByOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory owned = new uint256[](numberOfTokensOwned[_owner]);
        uint256 counter = 0;
        for (uint256 i = 0; i < tokenCounter; i++) {
            if (counterToAddress[i] == _owner) {
                owned[counter] = i;
                counter += 1;
            }
        }
        return owned;
    }

    function middleRand(uint256 max, uint256 salt)
        internal
        view
        returns (uint256)
    {
        uint256 number = 0;
        for (uint256 i = 0; i < 10; i++) {
            number += ((rand(salt) % 100000001) * max) / 10;
        }
        return number / 100000000;
    }

    function rand(uint256 salt) internal view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    salt +
                        block.timestamp +
                        block.difficulty +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (block.timestamp)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (block.timestamp)) +
                        block.number
                )
            )
        );

        return seed;
    }

    function getPayment(uint256 packId) internal returns (bool) {
        address paymentType = stockManager.paymentType(packId);
        uint256 cost = stockManager.getPriceOf(packId);

        if (paymentType == address(0)) {
            require(msg.value >= cost, "Not enough balance"); // Check if balance is enough
            if (msg.value > cost) {
                msg.sender.transfer(msg.value.sub(cost)); // Refund extra
            }
        } else {
            IBEP20 bep20token = IBEP20(paymentType);
            require(
                bep20token.allowance(msg.sender, address(this)) >= cost,
                "NALW"
            );
            require(bep20token.transferFrom(msg.sender, address(this), cost));
        }
        return true;
    }

    function buyPack(uint256 packId) external payable packStock(packId) {
        uint256 typeOfToken = stockManager.getTypeOf(packId);
        TokenType matokentype;

        for (uint8 i = 0; i < stockManager.getNumberOfOut(packId); i++) {
            uint256 styleId = 0;
            uint256 imageId = 0;
            uint256 currentIdOfType = stockManager.getCurrentCounterOf(packId);

            if (typeOfToken == 0) {
                imageId = currentIdOfType;
                matokentype = TokenType.IMAGE_TOKEN;
            } else {
                styleId = currentIdOfType;
                matokentype = TokenType.STYLE_TOKEN;
            }

            (uint256 min, uint256 max) = stockManager.packToBoundaries(packId);

            uint256 value = middleRand(max - min, i) + min;

            SuperTkn memory tkn = SuperTkn(
                tokenCounter,
                imageId,
                styleId,
                matokentype,
                packId,
                value
            );

            _mintToken(msg.sender, tkn);
            require(stockManager.increaseCounter(packId));
        }

        emit BuyEvent(msg.sender, packId);
        bool done = getPayment(packId);
        require(done, "NPN");
    }

    // @ Seperate
    // Seperates Supertoken => ImageToken, StyleToken
    function separate(uint256 id)
        external
        payable
        requireOwnership(id)
        requireValue(SEPERATION_COST)
        returns (uint256, uint256)
    {
        SuperTkn memory token = counterToToken[id];
        require(token.tokenType == TokenType.SUPER_TOKEN);

        SuperData memory data = superToRoot[id];

        numberOfTokensOwned[msg.sender] = numberOfTokensOwned[msg.sender].add(
            2
        );
        counterToAddress[data.icid] = msg.sender;
        counterToAddress[data.scid] = msg.sender;

        emit Transfer(address(0), msg.sender, data.icid);
        emit Transfer(address(0), msg.sender, data.scid);

        _burnToken(msg.sender, id);

        emit SplitEvent(msg.sender, id, data.icid, data.scid, id);

        return (data.icid, data.scid);
    }

    // Mint Token
    function _mintToken(address _from, SuperTkn memory token)
        internal
        returns (uint256)
    {
        uint256 _tokenId = tokenCounter;
        token.counterId = _tokenId;
        require(counterToAddress[_tokenId] == address(0)); // Address 0 check
        counterToAddress[_tokenId] = _from;
        counterToToken[_tokenId] = token;
        numberOfTokensOwned[_from] = numberOfTokensOwned[_from].add(1);
        tokenCounter = tokenCounter.add(1);
        emit Transfer(address(0), _from, _tokenId);
        return _tokenId;
    }

    // Burn Token
    function _burnToken(address _from, uint256 _tokenId) internal {
        numberOfTokensOwned[_from] = numberOfTokensOwned[_from].sub(1);
        delete counterToAddress[_tokenId];
    }

    // @ Merge
    // Merges ImageToken, StyleToken => Supertoken
    function merge(
        uint256 imageId,
        uint256 styleId,
        uint256 painterId
    )
        external
        payable
        requireOwnership(imageId)
        requireOwnership(styleId)
        requireValue(painterIdToPrice[painterId])
        returns (uint256)
    {
        // Generate new merged token
        require(painterIdToPrice[painterId] != 0, "HMNS");
        SuperTkn memory _imageToken = counterToToken[imageId];
        SuperTkn memory _styleToken = counterToToken[styleId];
        require(_imageToken.imageId != 0, "0X1");
        require(_styleToken.styleId != 0, "0X2");
        // Mint new token
        uint256 value = _imageToken.value + _styleToken.value;
        SuperTkn memory _merged = SuperTkn(
            0,
            _imageToken.imageId,
            _styleToken.styleId,
            TokenType.SUPER_TOKEN,
            0,
            value
        );

        uint256 _id = _mintToken(msg.sender, _merged);
        superToRoot[_id] = SuperData(
            imageId,
            styleId,
            _imageToken.root,
            _styleToken.root
        );
        counterToPainter[_id] = painterId;

        // update imagetoken and styletoken
        _burnToken(msg.sender, imageId);
        _burnToken(msg.sender, styleId);

        emit MergeEvent(msg.sender, imageId, styleId, _id);
        return _id;
    }

    // Withdraws current balance
    function withdraw() external onlyOwner {
        address payable _owner = address(uint160(_contractOwner));
        _owner.transfer(address(this).balance);
    }

    // Withdraws any bep-20 balance
    function withdrawToken(address erc20) external onlyOwner {
        IBEP20 bep20 = IBEP20(erc20);
        bep20.transfer(_contractOwner, bep20.balanceOf(address(this)));
    }

    // Balance of
    function balanceOf(address _owner)
        external
        view
        override
        returns (uint256)
    {
        return numberOfTokensOwned[_owner];
    }

    function isSuper(uint256 token) external view returns (bool) {
        if (counterToToken[token].tokenType == TokenType.SUPER_TOKEN) {
            return true;
        } else {
            return false;
        }
    }

    function ownerOf(uint256 _tokenId)
        external
        view
        virtual
        override
        returns (address)
    {
        return counterToAddress[_tokenId];
    }
}
