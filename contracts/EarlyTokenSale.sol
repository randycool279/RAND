pragma solidity ^0.4.15;

import "./DataBrokerDaoToken.sol";
import "./SafeMath.sol";
import "./interfaces/Controlled.sol";


contract EarlyTokenSale is TokenController, Controlled {

    using SafeMath for uint256;

    // In UNIX time format - http://www.unixtimestamp.com/
    uint256 public startFundingTime;       
    uint256 public endFundingTime;
    
    // 15% of tokens hard cap, at 1200 tokens per ETH
    // 225,000,000*0.15 => 33,750,000 / 1200 => 28,125 ETH => 28,125,000,000,000,000,000,000 wei
    uint256 public maximumFunding = 28125000000000000000000;

    uint256 tokensPerEther = 1200; 

    // total amount raised in wei
    uint256 public totalCollected;

    // the tokencontract for the DataBrokerDAO
    DataBrokerDaoToken public tokenContract;

    // the funds end up in this address
    address public vaultAddress;

    /// @param _startFundingTime The UNIX time that the EarlyTokenSale will be able to start receiving funds
    /// @param _endFundingTime   The UNIX time that the EarlyTokenSale will stop being able to receive funds
    /// @param _vaultAddress     The address that will store the donated funds
    /// @param _tokenAddress     Address of the token contract this contract controls
    function EarlyTokenSale(
        uint _startFundingTime, 
        uint _endFundingTime, 
        address _vaultAddress, 
        address _tokenAddress
    ) {
        require(_endFundingTime > now);
        require(_endFundingTime >= _startFundingTime);
        require(_vaultAddress != 0);
        require(_tokenAddress != 0);

        startFundingTime = _startFundingTime;
        endFundingTime = _endFundingTime;
        tokenContract = DataBrokerDaoToken(_tokenAddress);
        vaultAddress = _vaultAddress;
    }

    /// @dev The fallback function is called when ether is sent to the contract, it
    /// simply calls `doPayment()` with the address that sent the ether as the
    /// `_owner`. Payable is a required solidity modifier for functions to receive
    /// ether, without this modifier functions will throw if ether is sent to them
    function () payable {
        doPayment(msg.sender);
    }

    /// @notice `proxyPayment()` allows the caller to send ether to the EarlyTokenSale and
    /// have the tokens created in an address of their choosing
    /// @param _owner The address that will hold the newly created tokens
    function proxyPayment(address _owner) payable returns(bool success) {
        return doPayment(_owner);
    }

    /// @notice Notifies the controller about a transfer, for this EarlyTokenSale all
    /// transfers are allowed by default and no extra notifications are needed
    /// @param _from The origin of the transfer
    /// @param _to The destination of the transfer
    /// @param _amount The amount of the transfer
    /// @return False if the controller does not authorize the transfer
    function onTransfer(address _from, address _to, uint _amount) returns(bool success) {
        return true;
    }

    /// @notice Notifies the controller about an approval, for this EarlyTokenSale all
    /// approvals are allowed by default and no extra notifications are needed
    /// @param _owner The address that calls `approve()`
    /// @param _spender The spender in the `approve()` call
    /// @param _amount The amount in the `approve()` call
    /// @return False if the controller does not authorize the approval
    function onApprove(address _owner, address _spender, uint _amount) returns(bool success) {
        return true;
    }

    /// @dev `doPayment()` is an internal function that sends the ether that this
    ///  contract receives to the `vault` and creates tokens in the address of the
    ///  `_owner` assuming the EarlyTokenSale is still accepting funds
    /// @param _owner The address that will hold the newly created tokens
    function doPayment(address _owner) internal returns(bool success) {
        // First check that the EarlyTokenSale is allowed to receive this donation
        require(startFundingTime <= now);
        require(endFundingTime > now);
        require(tokenContract.controller() != 0);
        require(msg.value > 0);
        require(totalCollected.add(msg.value) <= maximumFunding);
        // Track how much the EarlyTokenSale has collected
        totalCollected = totalCollected.add(msg.value);
        //Send the ether to the vault
        require(vaultAddress.send(msg.value));
        // Creates an equal amount of tokens as ether sent. The new tokens are created in the `_owner` address
        require(tokenContract.generateTokens(_owner, tokensPerEther.mul(msg.value)));
        return true;
    }

    /// @notice `finalizeSale()` ends the EarlyTokenSale. It will generate the platform and team tokens
    ///  and set the controller to the referral fee contract.
    /// @dev `finalizeSale()` can only be called after the end of the funding period or if the maximum amount is raised.
    function finalizeSale() {
        require(now > endFundingTime || totalCollected >= maximumFunding);
        uint256 platformTokens = 56250000000000000000000000;      
        if (!tokenContract.generateTokens(vaultAddress, platformTokens)) {
            revert();
        } 
        uint256 teamTokens = 22500000000000000000000000;
        if (!tokenContract.generateTokens(vaultAddress, teamTokens)) { 
            revert();
        }
    }

//////////
// Safety Methods
//////////

  /// @notice This method can be used by the controller to extract mistakenly
  ///  sent tokens to this contract.
  /// @param _token The address of the token contract that you want to recover
  ///  set to 0 in case you want to extract ether.
  function claimTokens(address _token) onlyController {
    if (_token == 0x0) {
      controller.transfer(this.balance);
      return;
    }

    ERC20Token token = ERC20Token(_token);
    uint balance = token.balanceOf(this);
    token.transfer(controller, balance);
    ClaimedTokens(_token, controller, balance);
  }

  event ClaimedTokens(address indexed _token, address indexed _controller, uint _amount);
}
