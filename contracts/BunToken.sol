// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LockedToken {
    using SafeERC20 for IERC20;
    IERC20 private _token;
    address public immutable donor;
    address public immutable beneficiary;
    uint256 public immutable releaseTime;
    bool public immutable revocable;
    address public immutable system;

    event Claim(address beneficiary, uint256 amount, uint256 releaseTime);
    event Revoke(address donor, uint256 amount);

    constructor(address pToken, address _donor, address _beneficiary, uint256 _releaseTime, bool _revocable, address _system) {
        require(_donor != address(0), "L: donor");
        require(_beneficiary != address(0), "L: beneficiary");
        require(_system != address(0), "L: system");
        require(_releaseTime > block.timestamp, "L: invalid release time");

        _token = IERC20(pToken);
        donor = _donor;
        beneficiary = _beneficiary;
        releaseTime = _releaseTime;
        revocable = _revocable;
        system = _system;
    }

    function token() public view returns (IERC20) {
        return _token;
    }

    function balanceOf() public view returns (uint256) {
        return _token.balanceOf(address(this));
    }

    function getInfo() external view returns (address, address, uint256, bool, uint256, address) {
        return (donor, beneficiary, releaseTime, revocable, _token.balanceOf(address(this)), system);
    }

    function revoke() public {
        require(revocable, "L: not revocable");
        require((msg.sender == donor) || (msg.sender == system), "L: no permission");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "L: no tokens");

        _token.safeTransfer(donor, amount);
        emit Revoke(donor, amount);
    }

    function claim() public {
        require(block.timestamp >= releaseTime, "L: not yet");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "L: no tokens");

        _token.safeTransfer(beneficiary, amount);
        emit Claim(beneficiary, amount, releaseTime);
    }
}

contract BunToken is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, Ownable, ERC20Permit {
    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM_ROLE");

    constructor(address initialOwner)
    ERC20("Boundless Network", "BUN")
    Ownable(_msgSender())
    ERC20Permit("Boundless Network")
    {
        _mint(initialOwner, 1e9 * 10 ** decimals()); // 1,000,000,000 BUN
        transferOwnership(initialOwner);
    }

    function transferOwnership(address _account) public override onlyOwner {
        addAdmin(_account);
        Ownable.transferOwnership(_account);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("BN: disabled");
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    // This required to check balance in off-chain before run tx
    function batchTransfer(address[] calldata recipients, uint256[] calldata amount) public returns (bool) {
        require(recipients.length == amount.length, "BN: invalid array");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(transfer(recipients[i], amount[i]), "BN: failed transfer");
        }
        return true;
    }

    // This required to check balance and allowance in off-chain before run tx
    function batchTransferFrom(address[] calldata senders, address[] calldata recipients, uint256[] calldata amount) public returns (bool) {
        require(senders.length == recipients.length && recipients.length == amount.length, "BN: invalid array");
        for (uint256 i = 0; i < senders.length; i++) {
            require(transferFrom(senders[i], recipients[i], amount[i]), "BN: failed transferFrom");
        }
        return true;
    }

    /* token lock and claim */
    function _utilDiffTime(uint256 _checkTs) private view returns (uint256, uint256) {
        require(_checkTs > block.timestamp, "BN: not yet");
        uint256 nowDayTime = block.timestamp;
        uint256 chkDayTime = _checkTs;
        uint256 nowDay = nowDayTime / 86400;
        uint256 chkDay = chkDayTime / 86400;
        return (chkDay - nowDay, chkDayTime - nowDayTime);
    }

    function getLockedTokenInfo(LockedToken _lockToken) external view returns (address, address, address, uint256, bool, uint256, uint256) {
        uint256 _diffDay;
        (_diffDay,) = _utilDiffTime(_lockToken.releaseTime());
        return (address(_lockToken.token()), _lockToken.donor(), _lockToken.beneficiary(), _lockToken.releaseTime(), _lockToken.revocable(), _lockToken.balanceOf(), _diffDay);
    }

    function lockToken(address _donor, address _beneficiary, uint256 _amount, uint256 _duration, uint256 _durationUnitInSec, bool _revocable) public onlyRole(SYSTEM_ROLE) returns (LockedToken) {
        uint256 releaseTime = block.timestamp + (_duration * _durationUnitInSec);
        LockedToken lockedToken = new LockedToken(address(this), _donor, _beneficiary, releaseTime, _revocable, address(this));
        _transfer(_msgSender(), address(lockedToken), _amount);
        emit TokenLock(address(lockedToken), _donor, _beneficiary, lockedToken.balanceOf(), releaseTime, _revocable, address(this), block.timestamp);
        return lockedToken;
    }

    function claimLockedToken(LockedToken _lockToken) public {
        _lockToken.claim();
    }

    function revokeLockedToken(LockedToken _lockToken) public onlyRole(SYSTEM_ROLE) {
        _lockToken.revoke();
    }


    // addAdmin can be performed by only owner
    function addAdmin(address _account) public onlyOwner returns (bool) {
        require(_account != address(0), "BN: zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, _account);
        _grantRole(SYSTEM_ROLE, _account);
        emit RoleChanged("addAdmin", _msgSender(), _account, block.timestamp);
        return true;
    }

    function renounceAdmin() public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        return revokeAdmin(_msgSender());
    }

    function revokeAdmin(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(_account != owner(), "BN: can't revoke owner's role");
        revokeRole(SYSTEM_ROLE, _account);
        revokeRole(DEFAULT_ADMIN_ROLE, _account);
        emit RoleChanged("revokeAdmin", _msgSender(), _account, block.timestamp);
        return true;
    }

    /* events */
    event TokenLock(address indexed lockedToken, address indexed donor, address indexed beneficiary, uint256 amount, uint256 releaseTime, bool revocable, address system, uint256 logTime);
    event RoleChanged(string indexed role, address indexed granter, address indexed grantee, uint256 logTime);
}
