pragma solidity 0.6.12;
/////////////////////////////////////////////////////////////////////////////////////
//
//  Level
//
/////////////////////////////////////////////////////////////////////////////////////
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./BBSPoolV2.sol";

contract BBSLevel is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct LevelInfo {
        uint256 level;
        uint256 amount;
    }

    BBSPoolV2 pool;
    IERC20 public token;

    LevelInfo[] public info;
    mapping(address => LevelInfo) public users;
    
    event LevelUp(address indexed user, uint256 amount);
    event LevelDown(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(BBSPoolV2 _pool, IERC20 _token) public {
        pool = _pool;
        token = _token;
    }

    function infoLength() public view returns (uint256) {
        return info.length;
    }

    function getLevel(address _addr) public view returns (uint256) {
        return users[_addr].level;
    }

    function getAmount(address _addr) public view returns (uint256) {
        return users[_addr].amount;
    }

    function setPoolContract(BBSPoolV2 _pool) public onlyOwner {
        pool = _pool;
    }
    
    function add(uint256 _level, uint256 _amount) public onlyOwner {
        info.push(LevelInfo({level: _level, amount: _amount}));
    }

    function set(uint256 id, uint256 _level, uint256 _amount) public onlyOwner {
        info[id].level = _level;
        info[id].amount = _amount;
    }

    function levelUp(uint256 _amount) public {
        require(_amount > 0, "levelUp: amount 0");

        LevelInfo storage user = users[msg.sender];
        user.amount = user.amount.add(_amount);

        uint256 length = info.length;
        for (uint256 i = 0; i < length; i++) {
            if (info[i].amount <= user.amount && user.level < info[i].level) {
                user.level = info[i].level;
            }
        }
        token.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit LevelUp(msg.sender, _amount);
    }

    function levelDown(uint256 _amount) public {
        require(_amount > 0, "levelDown: amount 0");
        require(users[msg.sender].amount >= _amount, "levelDown: not good");
        require(!pool.userMining(msg.sender, true), "levelDown: mining ture");
        
        LevelInfo storage user = users[msg.sender];
        user.amount = user.amount.sub(_amount);
        user.level = 0;

        uint256 length = info.length;
        for (uint256 i = 0; i < length; i++) {
            if (info[i].amount <= user.amount && user.level < info[i].level) {
                user.level = info[i].level;
            }
        }

        token.safeTransfer(address(msg.sender), _amount);
        emit LevelDown(msg.sender, _amount);
    }

    function emergencyWithdraw(address _addr) public onlyOwner {
        LevelInfo storage user = users[_addr];

        token.safeTransfer(address(_addr), user.amount);
        emit EmergencyWithdraw(_addr, user.amount);
        user.level = 0;
        user.amount = 0;
    }
}
