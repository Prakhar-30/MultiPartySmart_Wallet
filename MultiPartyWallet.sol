// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
//BobBanana
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


//100000000000000000

contract MultiPartyWallet is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMathUpgradeable for uint256;

    uint256 public creationTime;
    uint256 public totalContributions;
    bool public walletClosed;
    uint256 public minimumContribution;
    uint256 public closureTime;

    struct Shareholder {
        uint256 contribution;
        uint256 share;
        uint256 unclaimedFunds;
    }

    mapping(address => Shareholder) public shareholders;
    address[] public shareholderAddresses;


    IERC20 public memeCoin;
    uint256 public memeCoinsPerEth;

    event MemeCoinsDistributed(address indexed shareholder, uint256 amount);

    event ContributionReceived(address indexed contributor, uint256 amount);
    event WalletClosed();
    event FundsDistributed(uint256 amount);
    event ShareCalculated(address indexed shareholder, uint256 share);
    event MinimumContributionUpdated(uint256 newMinimum);
    event SharesUpdated();
    event FallbackCalled(address sender, uint256 amount);
    event FundsWithdrawn(address indexed shareholder, uint256 amount);
    event ClosureTimeUpdated(uint256 newClosureTime);

    error WalletClosedError();
    error ContributionTooLowError();
    error NotClosedError();
    error InsufficientFundsError();

    modifier onlyOpen() {
        if (walletClosed) revert WalletClosedError();
        _;
    }

    modifier onlyClosed() {
        if (!walletClosed) revert NotClosedError();
        _;
    }

    function initialize(uint256 _minimumContribution, uint256 _closureTime, address _memeCoinAddress, uint256 _memeCoinsPerEth) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        creationTime = block.timestamp;
        walletClosed = false;
        minimumContribution = _minimumContribution;
        closureTime = _closureTime;
        memeCoin = IERC20(_memeCoinAddress);
        memeCoinsPerEth = _memeCoinsPerEth;
    }

     function setMemeCoin(address _memeCoinAddress, uint256 _memeCoinsPerEth) external onlyOwner {
        memeCoin = IERC20(_memeCoinAddress);
        memeCoinsPerEth = _memeCoinsPerEth;
    }

    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value);
        if (walletClosed) {
            _distributeFunds(msg.value);
        } else {
            contribute();
        }
    }

    function setMinimumContribution(uint256 _newMinimum) external onlyOwner onlyOpen {
        require(_newMinimum > 0, "Minimum contribution must be greater than 0");
        minimumContribution = _newMinimum;
        emit MinimumContributionUpdated(_newMinimum);
    }

    function setClosureTime(uint256 _newClosureTime) external onlyOwner onlyOpen {
        require(_newClosureTime > block.timestamp, "Closure time must be in the future");
        closureTime = _newClosureTime;
        emit ClosureTimeUpdated(_newClosureTime);
    }

    function contribute() public payable onlyOpen whenNotPaused {
        if (msg.value < minimumContribution) revert ContributionTooLowError();

        if (shareholders[msg.sender].contribution == 0) {
            shareholderAddresses.push(msg.sender);
        }

        shareholders[msg.sender].contribution = shareholders[msg.sender].contribution.add(msg.value);
        totalContributions = totalContributions.add(msg.value);

        emit ContributionReceived(msg.sender, msg.value);
    }

    function closeWallet() external onlyOpen {
        require(block.timestamp >= closureTime, "Cannot close wallet yet");

        walletClosed = true;
        _calculateShares();
        emit WalletClosed();
    }

    function _calculateShares() internal {
        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            address shareholderAddress = shareholderAddresses[i];
            shareholders[shareholderAddress].share = shareholders[shareholderAddress].contribution.mul(1e18).div(totalContributions);
            emit ShareCalculated(shareholderAddress, shareholders[shareholderAddress].share);
        }
    }

    function updateShares() external onlyOwner onlyClosed {
        _calculateShares();
        emit SharesUpdated();
    }

    function _distributeFunds(uint256 amount) internal {
        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            address shareholderAddress = shareholderAddresses[i];
            uint256 shareAmount = amount.mul(shareholders[shareholderAddress].share).div(1e18);
            shareholders[shareholderAddress].unclaimedFunds = shareholders[shareholderAddress].unclaimedFunds.add(shareAmount);

            if (address(memeCoin) != address(0) && memeCoinsPerEth > 0) {
                uint256 memeCoinsAmount = shareAmount.mul(memeCoinsPerEth);
                require(memeCoin.transfer(shareholderAddress, memeCoinsAmount), "MemeCoin transfer failed");
                emit MemeCoinsDistributed(shareholderAddress, memeCoinsAmount);
            }

        }

        emit FundsDistributed(amount);
    }

    function withdrawFunds() external nonReentrant whenNotPaused {
        uint256 amount = shareholders[msg.sender].unclaimedFunds;
        if (amount == 0) revert InsufficientFundsError();

        shareholders[msg.sender].unclaimedFunds = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable onlyClosed {
        _distributeFunds(msg.value);
    }
}

