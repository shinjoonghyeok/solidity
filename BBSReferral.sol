pragma solidity 0.6.12;

/////////////////////////////////////////////////////////////////////////////////////
//
//  Referral
//
/////////////////////////////////////////////////////////////////////////////////////
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract BBSReferral is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public token;

    uint256 public fee;

    struct User {
        address parent;
        address[] children;
        uint256 grade;
    }

    mapping(address => User) public users;

    event AddReferral(address indexed user, address _addr);
    event Register(address indexed user, address _addr);

    constructor(IERC20 _token, uint256 _fee) public {
        token = _token;
        fee = _fee;
    }

    function getParent(address _addr) public view returns (address) {
        return users[_addr].parent;
    }

    function getChildren(address _addr) public view returns (address[] memory) {
        return users[_addr].children;
    }

    function getGrade(address _addr) public view returns (uint256) {
        return users[_addr].grade;
    }

    function setFee(IERC20 _token, uint256 _amount) public onlyOwner {
        token = _token;
        fee = _amount;
    }

    function withdraw(uint256 _amount) public onlyOwner {
        require(
            token.balanceOf(address(this)) >= _amount,
            "withdraw: not good"
        );
        token.safeTransfer(address(msg.sender), _amount);
    }

    // 마스터 등록 (온리 오너계정)
    function addMaster(address _addr) public onlyOwner {
        // _addr 이 등록 되어있으면 에러
        require(users[_addr].grade < 1, "addMaster: used address");
        User storage user = users[_addr];
        user.grade = 1;
        users[_addr] = user;
    }

    // 레퍼럴 계정
    // 상위는 마스터, 토큰으로 구매 (fee)
    // _addr : master address
    function addReferral(address _addr) public {
        // _addr 이 master 계정이 아니면 에러
        require(users[_addr].grade == 1, "addReferral: not address");

        //내 address가 등록 되어있으면 에러
        require(users[msg.sender].grade < 1, "addReferral: used address");

        //레퍼럴 유저 등록
        User storage user = users[msg.sender];
        user.grade = 2;
        user.parent = _addr;
        users[msg.sender] = user;

        //마스터 children 추가
        User storage master = users[_addr];
        master.children.push(msg.sender);

        token.safeTransferFrom(address(msg.sender), address(this), fee);
        emit AddReferral(msg.sender, _addr);
    }

    //레퍼럴 등록
    // _addr = referral
    function register(address _addr) public {
        // msg.sender 와 _addr 이 같으면 에러
        require(msg.sender != _addr, "register: error address");

        //내 address가 등록 되어있으면 에러
        require(users[msg.sender].grade < 1, "register: used address");

        // _addr이 referral이 아니면 에러
        require(users[_addr].grade == 2, "register: not referral address");

        // 상위레퍼럴에 children 추가
        User storage parent = users[_addr];
        parent.children.push(msg.sender);

        // msg.sender로 구조체 생성
        User storage user = users[msg.sender];
        user.parent = _addr;
        user.grade = 3;
        emit Register(msg.sender, _addr);
    }
}
