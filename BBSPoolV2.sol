pragma solidity 0.6.12;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./BitberrySwap.sol";
import "./BBSLevel.sol";
import "./BBSReferral.sol";

interface IMigratorPool {
    function migrate(IERC20 token) external returns (IERC20);
}


contract BBSPoolV2 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accTokenPerShare;
        uint256 level;
    }

    BitberrySwap public token;
    address public teamAddr;
    uint256 public tokenPerBlock;
    uint256 public BONUS_MULTIPLIER = 1;
    IMigratorPool public migrator;
    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint;
    uint256 public startBlock;

    uint256 public endBlock;

    BBSLevel public levelContract;
    BBSReferral public referralContract;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        BitberrySwap _token,
        address _teamAddr,
        uint256 _tokenPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        token = _token;
        teamAddr = _teamAddr;
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function setLevelContract(BBSLevel _levelContract) public onlyOwner {
        levelContract = _levelContract;
    }

    function setReferralContract(BBSReferral _referralContract) public onlyOwner {
        referralContract = _referralContract;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function userMining(address _addr, bool _levelPool) external view returns (bool) {
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_addr];

            if(_levelPool && pool.level > 0 && user.amount > 0)
                return true;
            else if (!_levelPool && user.amount > 0)
                return true;
        }
        return false;
    }

    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, uint256 _level) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accTokenPerShare: 0,
            level: _level
        }));
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setMigrator(IMigratorPool _migrator) public onlyOwner {
        migrator = _migrator;
    }

    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function pendingToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        uint256 blockNumber = 0;
        if(block.number > endBlock)
            blockNumber = endBlock;
        else
            blockNumber = block.number;
        
        if (blockNumber > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockNumber);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            if (block.number > endBlock)
                pool.lastRewardBlock = endBlock;
            else
                pool.lastRewardBlock = block.number;
            return;
        }
        if (pool.lastRewardBlock == endBlock){
            return;
        }

        if (block.number > endBlock){
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, endBlock);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            //token.mint(teamAddr, tokenReward.div(10));
            //token.mint(address(this), tokenReward);
            pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
            pool.lastRewardBlock = endBlock;
            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        //token.mint(teamAddr, tokenReward.div(10));
        //token.mint(address(this), tokenReward);
        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
        
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //풀 레벨 보다 사용자 레벨이 높거나 같아야 함
        require(levelContract.getLevel(msg.sender) >= pool.level, "deposit : user level");
        //레벨 풀 일 경우 사용자는 레퍼럴에 등록되어 있어야 함
        if(pool.level > 0)
            require(referralContract.getGrade(msg.sender) > 0, "deposit : user referral");

        //(address parent, address[] children, uint256 grade) = referralContract.users(msg.sender);
        //require(grade > 0, "deposit : user referral");

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(msg.sender, pending, pool.level);
        }
        if(_amount > 0) { //kevin
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }
    
    function depositFor(address _beneficiary, uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_beneficiary];

        //풀 레벨 보다 사용자 레벨이 높거나 같아야 함
        require(levelContract.getLevel(_beneficiary) >= pool.level, "depositFor : user level");
        //레벨 풀 일 경우 사용자는 레퍼럴에 등록되어 있어야 함
        if(pool.level > 0)
            require(referralContract.getGrade(_beneficiary) > 0, "depositFor : user referral");

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
            safeTokenTransfer(_beneficiary, pending, pool.level);
        }
        if(_amount > 0) { //kevin
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(_beneficiary, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        safeTokenTransfer(msg.sender, pending, pool.level);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeTokenTransfer(address _to, uint256 _amount, uint256 poolLevel) internal {
        uint256 tokenBal = token.balanceOf(address(this));

        if (_amount > tokenBal) {
            //grade == 2(레퍼럴)일때 상위 master에게 수수료 2%
            if( poolLevel > 0 && referralContract.getGrade(_to) == 2 ){
                address master = referralContract.getParent(_to);
                uint256 masterFee = tokenBal.mul(10).div(500); //2%
                token.transfer(master, masterFee);
                token.transfer(_to, tokenBal.sub(masterFee));
            //grade == 3(일반)일때 수수료 상위 parent 8%, master 2%
            } else if ( poolLevel > 0 && referralContract.getGrade(_to) == 3 ){
                address parent = referralContract.getParent(_to);
                address master = referralContract.getParent(parent);
                uint256 parentFee = tokenBal.mul(10).div(125); //8%
                uint256 masterFee = tokenBal.mul(10).div(500); //2%
                token.transfer(parent, parentFee);
                token.transfer(master, masterFee);
                token.transfer(_to, tokenBal.sub(parentFee).sub(masterFee));
            } else
                token.transfer(_to, tokenBal);

        } else {
            //grade == 2(레퍼럴)일때 상위 master에게 수수료 2%
            if( poolLevel > 0 && referralContract.getGrade(_to) == 2 ){
                address master = referralContract.getParent(_to);
                uint256 masterFee = _amount.mul(10).div(500); //2%
                token.transfer(master, masterFee);
                token.transfer(_to, _amount.sub(masterFee));
            //grade == 3(일반)일때 수수료 상위 parent 8%, master 2%
            } else if ( poolLevel > 0 && referralContract.getGrade(_to) == 3 ){
                address parent = referralContract.getParent(_to);
                address master = referralContract.getParent(parent);
                uint256 parentFee = _amount.mul(10).div(125); //8%
                uint256 masterFee = _amount.mul(10).div(500); //2%
                token.transfer(parent, parentFee);
                token.transfer(master, masterFee);
                token.transfer(_to, _amount.sub(parentFee).sub(masterFee));
            } else
                token.transfer(_to, _amount);
        }
    }

    // Update team address by the previous team.
    function team(address _teamAddr) public {
        require(msg.sender == teamAddr, "dev: wut?");
        teamAddr = _teamAddr;
    }

    function setEndBlock(uint256 _block) public onlyOwner {
        require(block.number < _block, "setEndBlock: err _block");
        endBlock = _block;
    }

}