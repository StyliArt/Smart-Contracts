pragma solidity ^0.7.0;
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";

// ICO
contract TokenSale {
    address owner;
    IBEP20 public tokenContract;
    uint256 public tokenPrice = 10000;
    uint256 public tokensSold;

    event Sell(address _buyer, uint256 _amount);

    constructor(address _tokenContract) public {
        owner = msg.sender;
        tokenContract = IBEP20(_tokenContract);
    }

    function multiply(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function endSale() public {
        require(msg.sender == owner);
        require(
            tokenContract.transfer(
                owner,
                tokenContract.balanceOf(address(this))
            )
        );

        address(uint160(owner)).transfer(address(this).balance);
    }

    fallback() external payable {
        require(msg.value > 0);
        uint256 amount = msg.value * tokenPrice;
        tokensSold += amount;
        require(tokenContract.balanceOf(address(this)) > amount, "FUND");
        require(tokenContract.transfer(msg.sender, amount));
        emit Sell(msg.sender, amount);
    }
}
