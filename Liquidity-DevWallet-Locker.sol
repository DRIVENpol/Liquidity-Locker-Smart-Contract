// DRIVENlock (Version 1.0.0) - Built by DRIVENecosystem Team on Binance Smart Chain
// Read more about us: www.drivenecosystem.com

// FEATURES
// - LOCK THE DEVELOPMENT WALLET;
// - LOCK THE MARKETING WALLET (STABLE COINS CAN BE LOCKED TOO);
// - LOCK THE LIQUIDITY OF YOUR PROJECT (LP TOKENS);
// - VESTING OPTION FOR DEVELOPMENT / MARKETING WALLET LOCK
// - EASY RENEWAL FOR EXPIRED LOCKS

// DRIVENlock Support Group: https://t.me/DRIVENlockSupport



// =========



// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

// IMPORT LIBRARIES
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IBEP20.sol";

// THE START OF THE SMART CONTRACT
contract DVXLocker is Ownable {
    using SafeMath for uint256;

    // STRUCT FOR PROJECTS
    struct Items {
        address tokenAddress;
        address withdrawalAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
    }

    // VARIABLES
    uint256 public bnbFee = 1000000000000000;
    uint256 public bnbSubFee = 100000000000000;
    uint256 public totalBnbFees = 0;
    uint256 public remainingBnbFees = 0;
    uint256 public depositId;
    uint256[] public allDepositIds;
    address[] tokenAddressesWithFees;

    // MAPPINGS
    mapping(uint256 => Items) public lockedToken;
    mapping(address => uint256) public tokensFees;
    mapping(address => uint256[]) public depositsByWithdrawalAddress;
    mapping(address => uint256[]) public depositsByTokenAddress;
    mapping(address => mapping(address => uint256)) public walletTokenBalance;

    // EVENTS
    event TokensLocked(address indexed tokenAddress, address indexed sender, uint256 amount, uint256 unlockTime, uint256 depositId);
    event TokensWithdrawn(address indexed tokenAddress, address indexed receiver, uint256 amount);
    event EmergencyTokensWithdrawn(address indexed tokenAddress, address indexed receiver, uint256 amount); 
    event WithdrawSpecificToken(address indexed token, address indexed receiver, uint256 amount);
    event Renewed(uint256 indexed id, uint256  unlockeTime);

    // LOCK TOKENS
    function lockTokens(
        address _tokenAddress,
        uint256 _amount,
        uint256 _unlockTime
    ) external payable{
        require( msg.value >= bnbFee, 'BNB fee not provided');
        totalBnbFees = totalBnbFees.add(msg.value);
        remainingBnbFees = remainingBnbFees.add(msg.value);
        _lockTokens(_tokenAddress, _amount, _unlockTime);
    }

    // LOCK TOKENS WITH VESTING
    function lockTokenMultiple(
        address _tokenAddress,
        uint256[] memory _amount,
        uint256[] memory _unlockTime
    ) external payable {
        uint256 requiredFee = (_amount.length - 1) * (bnbSubFee) + bnbFee;
        require( msg.value >= requiredFee, 'BNB fee not provided');
        totalBnbFees = totalBnbFees.add(msg.value);
        remainingBnbFees = remainingBnbFees.add(msg.value);
        for(uint8 i = 0; i < _amount.length; i++) {
            _lockTokens(_tokenAddress, _amount[i], _unlockTime[i]);
        }
    }

    // LOCK TOKENS - INTERNAL FUNCTION
    function _lockTokens(
        address _tokenAddress,
        uint256 _amount,
        uint256 _unlockTime
    ) internal returns (uint256 _id) {
        require(_amount > 0, 'Tokens amount must be greater than 0');
        require(_unlockTime < 10000000000, 'Unix timestamp must be in seconds, not milliseconds');
        require(_unlockTime > block.timestamp, 'Unlock time must be in future');
        require(IBEP20(_tokenAddress).transferFrom(msg.sender, address(this), _amount), 'Failed to transfer tokens to locker');
        uint256 lockAmount = _amount;       
        walletTokenBalance[_tokenAddress][msg.sender] = walletTokenBalance[_tokenAddress][msg.sender].add(_amount);
        address _withdrawalAddress = msg.sender;
        _id = ++depositId;
        lockedToken[_id].tokenAddress = _tokenAddress;
        lockedToken[_id].withdrawalAddress = _withdrawalAddress;
        lockedToken[_id].tokenAmount = lockAmount;
        lockedToken[_id].unlockTime = _unlockTime;
        lockedToken[_id].withdrawn = false;
        allDepositIds.push(_id);
        depositsByWithdrawalAddress[_withdrawalAddress].push(_id);
        depositsByTokenAddress[_tokenAddress].push(_id);
        emit TokensLocked(_tokenAddress, msg.sender, _amount, _unlockTime, depositId);
    }
    
    // EMERGENCY WITHDRAW TOKENS
    function emergencyWithdrawTokens(uint256 _id, address _receiver) external onlyOwner{ //ONLY OWNER MODIFIER
        require(!lockedToken[_id].withdrawn, 'Tokens already withdrawn');
        require(address(0) != _receiver, "Invalid receiver address");
        address tokenAddress = lockedToken[_id].tokenAddress;
        address withdrawalAddress = lockedToken[_id].withdrawalAddress;
        uint256 amount = lockedToken[_id].tokenAmount;
        require(IBEP20(tokenAddress).transfer(_receiver, amount), 'Failed to transfer tokens');
        lockedToken[_id].withdrawn = true;
        uint256 previousBalance = walletTokenBalance[tokenAddress][msg.sender];
        walletTokenBalance[tokenAddress][msg.sender] = previousBalance.sub(amount);
        uint256 i;
        uint256 j;
        uint256 byWLength = depositsByWithdrawalAddress[withdrawalAddress].length;
        uint256[] memory newDepositsByWithdrawal = new uint256[](byWLength - 1);
        for (j = 0; j < byWLength; j++) {
            if (depositsByWithdrawalAddress[withdrawalAddress][j] == _id) {
                for (i = j; i < byWLength - 1; i++) {
                    newDepositsByWithdrawal[i] = depositsByWithdrawalAddress[withdrawalAddress][i + 1];
                }
                break;
            } else {
                newDepositsByWithdrawal[j] = depositsByWithdrawalAddress[withdrawalAddress][j];
            }
        }
        depositsByWithdrawalAddress[withdrawalAddress] = newDepositsByWithdrawal;
        uint256 byTLength = depositsByTokenAddress[tokenAddress].length;
        uint256[] memory newDepositsByToken = new uint256[](byTLength - 1);
        for (j = 0; j < byTLength; j++) {
            if (depositsByTokenAddress[tokenAddress][j] == _id) {
                for (i = j; i < byTLength - 1; i++) {
                    newDepositsByToken[i] = depositsByTokenAddress[tokenAddress][i + 1];
                }
                break;
            } else {
                newDepositsByToken[j] = depositsByTokenAddress[tokenAddress][j];
            }
        }
        depositsByTokenAddress[tokenAddress] = newDepositsByToken;
        emit EmergencyTokensWithdrawn(tokenAddress, withdrawalAddress, amount);
    }

    // RENEW THE LOCK
    function renewToken(uint256 _id, uint256 _unlockTime) external {
        require(block.timestamp >= lockedToken[_id].unlockTime, 'Tokens are locked');
        require(!lockedToken[_id].withdrawn, 'Tokens already withdrawn');
        require(msg.sender == lockedToken[_id].withdrawalAddress, 'Can withdraw from the address used for locking');
        require(_unlockTime > block.timestamp, 'Unlock time must be in future');
        lockedToken[_id].unlockTime = _unlockTime;
        emit Renewed(_id, _unlockTime);
    }

    // WITHDRAW TOKENS FROM EXPIRED LOCKS
    function withdrawTokens(uint256 _id) external {
        require(block.timestamp >= lockedToken[_id].unlockTime, 'Tokens are locked');
        require(!lockedToken[_id].withdrawn, 'Tokens already withdrawn');
        require(msg.sender == lockedToken[_id].withdrawalAddress, 'Can withdraw from the address used for locking');
        address tokenAddress = lockedToken[_id].tokenAddress;
        address withdrawalAddress = lockedToken[_id].withdrawalAddress;
        uint256 amount = lockedToken[_id].tokenAmount;
        require(IBEP20(tokenAddress).transfer(withdrawalAddress, amount), 'Failed to transfer tokens');
        lockedToken[_id].withdrawn = true;
        uint256 previousBalance = walletTokenBalance[tokenAddress][msg.sender];
        walletTokenBalance[tokenAddress][msg.sender] = previousBalance.sub(amount);
        uint256 i;
        uint256 j;
        uint256 byWLength = depositsByWithdrawalAddress[withdrawalAddress].length;
        uint256[] memory newDepositsByWithdrawal = new uint256[](byWLength - 1);
        for (j = 0; j < byWLength; j++) {
            if (depositsByWithdrawalAddress[withdrawalAddress][j] == _id) {
                for (i = j; i < byWLength - 1; i++) {
                    newDepositsByWithdrawal[i] = depositsByWithdrawalAddress[withdrawalAddress][i + 1];
                }
                break;
            } else {
                newDepositsByWithdrawal[j] = depositsByWithdrawalAddress[withdrawalAddress][j];
            }
        }
        depositsByWithdrawalAddress[withdrawalAddress] = newDepositsByWithdrawal;
        uint256 byTLength = depositsByTokenAddress[tokenAddress].length;
        uint256[] memory newDepositsByToken = new uint256[](byTLength - 1);
        for (j = 0; j < byTLength; j++) {
            if (depositsByTokenAddress[tokenAddress][j] == _id) {
                for (i = j; i < byTLength - 1; i++) {
                    newDepositsByToken[i] = depositsByTokenAddress[tokenAddress][i + 1];
                }
                break;
            } else {
                newDepositsByToken[j] = depositsByTokenAddress[tokenAddress][j];
            }
        }
        depositsByTokenAddress[tokenAddress] = newDepositsByToken;
        emit TokensWithdrawn(tokenAddress, withdrawalAddress, amount);
    }

    // WITHDRAW SPECIFIC DEPOSIT
    function withdrawSpecificToken(address token, address receiver,uint256 amount) external onlyOwner {
        require(address(0) != receiver, "Invalid receiver address");
        require(address(0) != token, "Invalid receiver address");
        require(amount >= 0, "Invaild amount");
        require(IBEP20(token).transfer(receiver, amount));
        emit WithdrawSpecificToken(token ,receiver, amount);
    }

    // RECEIVE THE FEES
    function withdrawFees(address payable withdrawalAddress) external onlyOwner {
        if (remainingBnbFees > 0) {
            withdrawalAddress.transfer(remainingBnbFees);
            remainingBnbFees = 0;
        }
        for (uint i = 1; i <= tokenAddressesWithFees.length; i++) {
            address tokenAddress = tokenAddressesWithFees[tokenAddressesWithFees.length - i];
            uint256 amount = tokensFees[tokenAddress];
            if (amount > 0) {
                IBEP20(tokenAddress).transfer(withdrawalAddress, amount);
            }
            delete tokensFees[tokenAddress];
            tokenAddressesWithFees.pop();
        }
        tokenAddressesWithFees = new address[](0);
    }

    // GETTERS
    function getTotalTokenBalance(address _tokenAddress) view public returns (uint256)
    {
        return IBEP20(_tokenAddress).balanceOf(address(this));
    }

    function getTokenBalanceByAddress(address _tokenAddress, address _walletAddress) view public returns (uint256)
    {
        return walletTokenBalance[_tokenAddress][_walletAddress];
    }

    function getAllDepositIds() view public returns (uint256[] memory)
    {
        return allDepositIds;
    }

    function getDepositDetails(uint256 _id) view public returns (address, address, uint256, uint256, bool)
    {
        return (lockedToken[_id].tokenAddress, lockedToken[_id].withdrawalAddress, lockedToken[_id].tokenAmount,
        lockedToken[_id].unlockTime, lockedToken[_id].withdrawn);
    }

    function getDepositsByWithdrawalAddress(address _withdrawalAddress) view public returns (uint256[] memory)
    {
        return depositsByWithdrawalAddress[_withdrawalAddress];
    }

    function getDepositsByTokenAddress(address _tokenAddress) view public returns (uint256[] memory)
    {
        return depositsByTokenAddress[_tokenAddress];
    }

    // SETTERS
    function setBnbFee(uint256 fee) external onlyOwner {
        require(fee > 0, 'Fee is too small');
        bnbFee = fee;
    }

    function setBnbSubFee(uint256 fee) external onlyOwner {
        require(fee > 0, 'Fee is too small');
        bnbSubFee = fee;
    }
}
// THE END OF THE SMART CONTRACT
