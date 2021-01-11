// SPDX-License-Identifier: None
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract CryptoZoo is ERC721, Ownable {
    using SafeMath for uint256;
    
    uint256 private tokenIndex;
    uint256 public eggPrice;
    
    //一个动物需要有的属性
    mapping (uint256 => uint8) private animalsType;
    mapping (uint256 => uint8) private animalsLevel;
    mapping (uint256 => uint256) private animalPrice;

    // 奖金池 level => bonus
    mapping (uint8 => uint256) public bonusPool;
    // 级别奖金比例 level => rate
    mapping (uint8 => uint256) public levelBonusRate;
    // 动物奖金比例 animal => rate
    mapping (uint8 => uint256) public animalBonusRate;

    // 交易市场 level => type => tokenID
    mapping (uint8 => mapping (uint8 => uint256[])) public market;

    constructor() public ERC721("CryptoZoo", "CZ") {
        tokenIndex = 1;
        eggPrice = 1e16;
    }
    
    function setEggPrice(uint256 _price) public onlyOwner {
        eggPrice = _price;
    }

    function setlevelRate(uint256[] memory _rates) public onlyOwner {
        for (uint8 i = 1; i <= _rates.length; i++) {
            levelBonusRate[i] = _rates[1];
        }
    }

    function setanimalRate(uint256[] memory _rates) public onlyOwner {
        for (uint8 i = 1; i <= _rates.length; i++) {
            animalBonusRate[i] = _rates[1];
        }
    }
    
    // 创建
    function create() public payable {
        require(msg.value == eggPrice, "Error: invalid price");
        _feeToPool(msg.value);

        _safeMint(msg.sender, tokenIndex);
        
        uint8 _type = _randomAnimal(msg.sender);
        animalsType[tokenIndex] = _type;
        animalsLevel[tokenIndex] = 1;

        tokenIndex = tokenIndex.add(1);
    }

    // 升级
    function upgrade(uint256 _token1, uint256 _token2) public {
        require(ownerOf(_token1) == msg.sender && ownerOf(_token2) == msg.sender, "Error: no right");
        
        require(animalsType[_token1] == animalsType[_token2], "Error: different animals");
        require(animalsLevel[_token1] == animalsLevel[_token2] && animalsLevel[_token1] < 5, "Error: different levels");
        require(animalPrice[_token1] == 0 && animalPrice[_token2] == 0, "Error: in sell");

        _burn(_token1);
        _burn(_token2);

        _safeMint(msg.sender, tokenIndex);
        animalsType[tokenIndex] = animalsType[_token1];
        animalsLevel[tokenIndex] = animalsLevel[_token1] + 1;

        tokenIndex = tokenIndex.add(1);
    }
    
    // 给系统赎回
    function redeem(uint256 _tokenID) public {
        require(ownerOf(_tokenID) == msg.sender, "Error: no right");

        require(animalPrice[_tokenID] == 0, "Error: in sell");
        require(animalsLevel[_tokenID] >= 3, "Error: invalid level");

        uint8 _type = animalsType[_tokenID];
        uint8 _level = animalsLevel[_tokenID];
        uint256 bonus = bonusPool[_level].mul(animalBonusRate[_type]).div(100);
        
        _burn(_tokenID);
        msg.sender.transfer(bonus);
    }

    // 挂价出售
    function sell(uint256 _tokenID, uint256 _price) public {
        require(ownerOf(_tokenID) == msg.sender, "Error: no right");
        require(animalsLevel[_tokenID] >= 2, "Error: invalid level");

        animalPrice[_tokenID] = _price;
        market[animalsLevel[_tokenID]][animalsType[_tokenID]].push(_tokenID);
    }

    // 购买
    function buy(uint256 _tokenID) public payable {
        require(ownerOf(_tokenID) != msg.sender, "Error: no right");
        require(msg.value > 0 && animalPrice[_tokenID] == msg.value, "Error: invalid price");
        safeTransferFrom(ownerOf(_tokenID), msg.sender, _tokenID);
    }

    // 查询动物信息
    function getAnimalInfo(uint256 _tokenID) public view returns (uint8 _type, uint8 _level, uint256 _price) {
        _type = animalsType[_tokenID];
        _level = animalsLevel[_tokenID];
        _price = animalPrice[_tokenID];
    }

    function _randomAnimal(address _user) internal view returns (uint8) {
        require(_user != block.coinbase, "Error: minner forbidden");
        return uint8(
            uint256(keccak256(abi.encodePacked(_user, block.difficulty, block.timestamp))) % 12
        ) + 1;
    }

    function _feeToPool(uint256 _fee) internal {
        bonusPool[3] = bonusPool[3].add(_fee.mul(levelBonusRate[3]).div(100));
        bonusPool[4] = bonusPool[4].add(_fee.mul(levelBonusRate[3]).div(100));
        bonusPool[5] = bonusPool[5].add(_fee.mul(levelBonusRate[3]).div(100));
    }
}