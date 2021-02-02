// SPDX-License-Identifier: None
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract CryptoZoo is ERC721, Ownable {
    using SafeMath for uint256;
    
    uint256 private tokenIndex;
    uint256 public eggPrice;
    address public devAddress;
    uint256 public devFeeRate;
    
    struct Seller {
        address seller;
        uint256 tokenID;
        uint256 price;
    }
    
    struct Buyer {
        address buyer;
        uint256 price;
    }
    
    struct Animal {
        uint256 tokenID;
        uint8 animalLevel;
        uint8 animalType;
        uint256 price;
    }
    
    //一个动物需要有的属性
    // mapping (uint256 => uint8) public animalsType;
    // mapping (uint256 => uint8) public animalsLevel;
    // mapping (uint256 => uint256) public animalPrice;
    
    mapping (uint256 => Animal) public animalInfo;
    mapping (uint256 => bool) public isTokenExist;
    
    mapping (address => mapping(uint8 => uint256[])) public userInfo;

    // 奖金池 level => bonus
    mapping (uint8 => uint256) public bonusPool;
    // 级别奖金比例 level => rate
    mapping (uint8 => uint256) public levelBonusRate;
    // 动物奖金比例 animal => rate
    mapping (uint8 => uint256) public animalBonusRate;

    // 拍卖订单 level => type => tokenID
    mapping (uint8 => mapping (uint8 => Seller)) private sellOrder;
    mapping (uint8 => mapping (uint8 => Buyer)) private buyOrder;

    event Creat(address user, uint8 animal, uint256 tokenID);
    event Upgrade(address user, uint256 token1, uint256 token2);
    event Redeem(address user, uint256 tokenID, uint8 animal, uint8 level);
    event Sell(address seller, address buyer, uint256 tokenID, uint256 price);
    event Buy(address buyer, address seller, uint256 tokenID, uint256 price);
    event CancleSell(address seller, uint256 tokenID);
    event CancleBuy(address buyer, uint8 level, uint8 animal);

    constructor() public ERC721("CryptoZoo", "CZ") {
        tokenIndex = 1;
        eggPrice = 1e16;
        devAddress = msg.sender;
    }
    
    function setDevFee(uint256 _FeeRate) public onlyOwner {
        devFeeRate = _FeeRate;
    }

    function setEggPrice(uint256 _price) public onlyOwner {
        eggPrice = _price;
    }

    function setLevelRate(uint256[] memory _rates) public onlyOwner {
        for (uint8 i = 1; i <= _rates.length; i++) {
            levelBonusRate[i] = _rates[1];
        }
    }

    function setAnimalRate(uint256[] memory _rates) public onlyOwner {
        for (uint8 i = 1; i <= _rates.length; i++) {
            animalBonusRate[i] = _rates[1];
        }
    }
    
    function create() public payable returns (uint8) {
        require(msg.value == eggPrice, "Error: invalid price");
        _feeToPool(msg.value);

        _safeMint(msg.sender, tokenIndex);
        
        uint8 _type = _randomAnimal(msg.sender);
       
        animalInfo[tokenIndex] = Animal(tokenIndex, 1, _type, 0);
        isTokenExist[tokenIndex] = true;
        userInfo[msg.sender][1].push(tokenIndex);
    
        emit Creat(msg.sender, _type, tokenIndex);
        
        tokenIndex = tokenIndex.add(1);

        return _type;
    }

    function upgrade(uint256 _token1, uint256 _token2) public returns (bool) {
        require(ownerOf(_token1) == msg.sender && ownerOf(_token2) == msg.sender, "Error: no right");
        
        require(animalInfo[_token1].animalLevel == animalInfo[_token2].animalLevel && animalInfo[_token1].animalLevel < 5, "Error: different levels");
        require(animalInfo[_token1].animalType  == animalInfo[_token2].animalType, "Error: different animals");
        require(animalInfo[_token1].price == 0 && animalInfo[_token2].price == 0, "Error: in sell");

        _burn(_token1);
        isTokenExist[_token1] = false;
        
        _burn(_token2);
        isTokenExist[_token2] = false;

        _safeMint(msg.sender, tokenIndex);
        
        animalInfo[tokenIndex] = Animal(tokenIndex, animalInfo[_token1].animalLevel + 1, animalInfo[_token1].animalType, 0);
        isTokenExist[tokenIndex] = true;
        userInfo[msg.sender][animalInfo[_token1].animalLevel+1].push(tokenIndex);
  
        tokenIndex = tokenIndex.add(1);

        emit Upgrade(msg.sender, _token1, _token1);

        return true;
    }
    
    // 给系统赎回
    function redeem(uint256 _tokenID) public returns (bool) {
        require(ownerOf(_tokenID) == msg.sender, "Error: no right");

        require(animalInfo[_tokenID].price == 0, "Error: in sell");
        require(animalInfo[_tokenID].animalLevel >= 3, "Error: invalid level");

        uint8 _type = animalInfo[_tokenID].animalType;
        uint8 _level = animalInfo[_tokenID].animalLevel;
        uint256 bonus = bonusPool[_level].mul(animalBonusRate[_type]).div(100);
        
        _burn(_tokenID);
        isTokenExist[_tokenID] = false;
        
        msg.sender.transfer(bonus);
        
        emit Redeem(msg.sender, _tokenID, _type, _level);

        return true;
    }

    // 竞拍出售
    function sellBids(uint256 _tokenID, uint256 _price) public returns (bool) {
        require(ownerOf(_tokenID) == msg.sender, "Error: no right");
        require(animalInfo[_tokenID].animalLevel >= 2, "Error: invalid level");
        require(sellOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].price == 0 || _price < sellOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].price, "Error: price is too high");
        
        // animalPrice[sellOrder[animalsLevel[_tokenID]][animalsType[_tokenID]].tokenID] = 0;
        animalInfo[sellOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].tokenID].price = 0;
        
        sellOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType] = Seller(msg.sender, _tokenID, _price);
        animalInfo[_tokenID].price = _price;
        
        return true;
    }

    // function cancleSell(uint256 _tokenID) public returns (bool) {
    //     require(ownerOf(_tokenID) == msg.sender, "Error: no right");
    //     require(sellOrder[animalsLevel[_tokenID]][animalsType[_tokenID]].tokenID == _tokenID, "Error: invalid token id");

    //     sellOrder[animalsLevel[_tokenID]][animalsType[_tokenID]] = Seller(address(0), 0, 0);
    //     animalInfo[_tokenID].price = 0;
        
    //     emit CancleSell(msg.sender, _tokenID);
    //     return true;
    // }

    // 竞拍购买
    function buyBids(uint8 _level, uint8 _type, uint256 _price) public payable returns (bool) {
        require(_level >= 2 && _level <= 5, "Error: invalid level");
        require(_type >= 1 && _level <= 12, "Error: invalid animal");
        require(_price > buyOrder[_level][_type].price, "Error: price is too low");
        require(msg.value == _price, "Error: invalid value");

        payable(buyOrder[_level][_type].buyer).transfer(buyOrder[_level][_type].price);
        buyOrder[_level][_type] = Buyer(msg.sender, _price);
        return true;
    }

    // function cancleBuy(uint8 _level, uint8 _type) public returns (bool) {
    //     require(msg.sender == buyOrder[_level][_type].buyer, "Error: invalid buyer");
    //     msg.sender.transfer(buyOrder[_level][_type].price);
    //     buyOrder[_level][_type] = Buyer(address(0), 0);

    //     emit CancleBuy(msg.sender, _level, _type);

    //     return true;
    // }

    // 主动购买
    function buy(uint8 _level, uint8 _type, uint256 _MaxPrice) public payable returns (bool) {
        require(sellOrder[_level][_type].price <= _MaxPrice, "Error: price is too low");
        require(msg.value == _MaxPrice, "Error: invalid value");
        
        payable(sellOrder[_level][_type].seller).transfer(sellOrder[_level][_type].price);
        msg.sender.transfer(_MaxPrice.sub(sellOrder[_level][_type].price));
    
        _safeTransfer(sellOrder[_level][_type].seller, msg.sender, sellOrder[_level][_type].tokenID, "");

        emit Buy(msg.sender, sellOrder[_level][_type].seller, sellOrder[_level][_type].tokenID, sellOrder[_level][_type].price);
        
        animalInfo[sellOrder[_level][_type].tokenID].price = 0;
        
        userInfo[msg.sender][_level].push(sellOrder[_level][_type].tokenID);
        
        sellOrder[_level][_type] = Seller(address(0), 0, 0);
        
        return true;
    }

    // 出动出售
    function sell(uint256 _tokenID, uint256 _MinPrice) public returns (bool) {
        require(ownerOf(_tokenID) == msg.sender, "Error: no right");
        require(animalInfo[_tokenID].animalLevel >= 2, "Error: invalid level");
        require(buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].price >= _MinPrice, "Error: price is too high");

        _safeTransfer(msg.sender,buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].buyer, _tokenID,  "");
        msg.sender.transfer(buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].price);
        
        emit Sell(msg.sender,buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].buyer, _tokenID, buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].price);
        
        userInfo[buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType].buyer][animalInfo[_tokenID].animalLevel].push(_tokenID);
        
        buyOrder[animalInfo[_tokenID].animalLevel][animalInfo[_tokenID].animalType] = Buyer(address(0), 0);
        
        return true;
    }
    
    // 赠送
    function send(address _to, uint256 _tokenID) public returns (bool) {
        require(_to != msg.sender, "Error: send to yourself");
        _safeTransfer(msg.sender, _to, _tokenID, "");
        userInfo[_to][animalInfo[_tokenID].animalLevel].push(_tokenID);
    }

    // 查询动物信息
    function getAnimalInfo(uint256 _tokenID) public view returns (Animal memory) {
        return animalInfo[_tokenID];
    }

    function getUserInfo(address _user, uint8 _level, uint256 _index) public view returns (Animal[] memory ret, bool end) {
        
        uint256 endIndex = _index + 100;
        
        if(endIndex >= userInfo[_user][_level].length) {
            endIndex = userInfo[_user][_level].length;
            end = true;
        }
        
        if (_index >= endIndex) {
            return (ret, end);
        }
        
        uint256 realCount = 0;
        uint256 retIndex = 0;
        for (uint256 i = _index; i < endIndex; i++) {
            uint256 tokenID = userInfo[_user][_level][i];
            if (isTokenExist[tokenID] && ownerOf(tokenID) == _user) {
                realCount = realCount + 1;
                retIndex = retIndex + 1;
            }
        }
        
        ret = new Animal[](realCount);
        
        retIndex = 0;
        for (uint256 i = _index; i < endIndex; i++) {
            uint256 tokenID = userInfo[_user][_level][i];
            if (isTokenExist[tokenID] && ownerOf(tokenID) == _user) {
                ret[retIndex] = animalInfo[tokenID];
                retIndex = retIndex + 1;
            }
        }
        
        return (ret, end);
    
    }
    
    function onSale(uint8 _level) public view returns (bool[] memory) {

        bool[] memory ret = new bool[](12);
        
        if (_level >= 2 && _level <= 5) {
            for(uint8 i = 0; i < 12; i++){
                ret[i] = (sellOrder[_level][i+1].seller != address(0));
            
            }
        } 
        
        return ret;
        
    }
    
    function onPurchase(uint8 _level) public view returns (bool[] memory ret) {
        
        bool[] memory ret = new bool[](12);
        
        if (_level >= 2 && _level <= 5) {
            for(uint8 i = 0; i < 12; i++){
                ret[i] = (buyOrder[_level][i+1].buyer != address(0));
                
            }
        }
        
        return ret;
    }

    function _randomAnimal(address _user) internal view returns (uint8) {
        require(_user != block.coinbase, "Error: minner forbidden");
        return uint8(
            uint256(keccak256(abi.encodePacked(_user, tokenIndex, block.difficulty))) % 12
        ) + 1;
    }

    function _feeToPool(uint256 _fee) internal {
        
        uint256 devFee = _fee.mul(devFeeRate).div(100);
        payable(devAddress).transfer(devFee);
        
        _fee = _fee.sub(devFee);
        bonusPool[3] = bonusPool[3].add(_fee.mul(levelBonusRate[3]).div(100));
        bonusPool[4] = bonusPool[4].add(_fee.mul(levelBonusRate[3]).div(100));
        bonusPool[5] = bonusPool[5].add(_fee.mul(levelBonusRate[3]).div(100));
    }
}