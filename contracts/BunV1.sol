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
        require(_donor != address(0), "Locked: donor is zero address");
        require(_beneficiary != address(0), "Locked: beneficiary is zero address");
        require(_system != address(0), "Locked: system is zero address");
        require(_releaseTime > block.timestamp, "Locked: invalid release time");

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
        require(revocable, "Locked: not revocable");
        require((msg.sender == donor) || (msg.sender == system), "Locked: donor or system required");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "Locked: no tokens to revoke");

        _token.safeTransfer(donor, amount);
        emit Revoke(donor, amount);
    }

    function claim() public {
        require(block.timestamp >= releaseTime, "Locked: time is not yet");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "Locked: no tokens to claim");

        _token.safeTransfer(beneficiary, amount);
        emit Claim(beneficiary, amount, releaseTime);
    }
}

contract BunV1 is ERC20, ERC20Burnable, ERC20Pausable, AccessControl, Ownable, ERC20Permit {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SYSTEM_ROLE = keccak256("SYSTEM_ROLE");

    constructor()
    ERC20("BUNetwork", "BUN")
    Ownable(_msgSender())
    ERC20Permit("BUNetwork")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender()); // Admin
        _grantRole(SYSTEM_ROLE, _msgSender()); // System

        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    function transferOwnership(address _account) public override onlyOwner {
        addAdmin(_account);
        Ownable.transferOwnership(_account);
    }

    function renounceOwnership() public view override onlyOwner {
        revert("BUN: disabled");
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    //
    function multiTransfers(address[] memory recipients, uint256[] memory amount) public returns (bool) {
        require(recipients.length == amount.length, "BUN: Input arrays are not valid");
        for (uint256 i = 0; i < recipients.length; i++) {
            require(transfer(recipients[i], amount[i]), "BUN: failed transfer");
        }
        return true;
    }

    function multiTransferFroms(address[] memory senders, address[] memory recipients, uint256[] memory amount) public returns (bool) {
        require(senders.length == recipients.length && recipients.length == amount.length, "BUN: Input arrays are not valid");
        for (uint256 i = 0; i < senders.length; i++) {
            require(transferFrom(senders[i], recipients[i], amount[i]), "BUN: failed transfer");
        }
        return true;
    }

    // token lock and claim
    function _utilDiffTime(uint256 _checkTs) public view returns (uint256, uint256) {
        require(_checkTs > block.timestamp, "BUN: not yet");
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

    function lockToken(address _donor, address _beneficiary, uint256 _amount, uint256 _duration, uint256 _durationUnit, bool _revocable) public onlyRole(SYSTEM_ROLE) returns (LockedToken) {
        uint256 releaseTime = block.timestamp + (_duration * _durationUnit);
        LockedToken lockedToken = new LockedToken(address(this), _donor, _beneficiary, releaseTime, _revocable, address(this));
        _transfer(_msgSender(), address(lockedToken), _amount);
        emit TokenLock(address(lockedToken), _donor, _beneficiary, lockedToken.balanceOf(), releaseTime, _revocable, address(this), block.timestamp);
        return lockedToken;
    }

    function claimLockedToken(LockedToken _lockToken) public {
        _lockToken.claim();
    }

    function multiClaimLockedToken(LockedToken[] memory _lockToken) external {
        for (uint256 i = 0; i < _lockToken.length; i++) {
            claimLockedToken(_lockToken[i]);
        }
    }

    function revokeLockedToken(LockedToken _lockToken) public onlyRole(SYSTEM_ROLE) {
        _lockToken.revoke();
    }

    function multiTokenLockRevoke(LockedToken[] memory _lockToken) external onlyRole(SYSTEM_ROLE) {
        for (uint256 i = 0; i < _lockToken.length; i++) {
            revokeLockedToken(_lockToken[i]);
        }
    }

    // admin operations
    function addAdmin(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(_account != address(0), "BUN: zero address");
        grantRole(DEFAULT_ADMIN_ROLE, _account); // Admin
        grantRole(PAUSER_ROLE, _account); // Admin
        grantRole(SYSTEM_ROLE, _account); // System
        emit RoleChanged("addAdmin", _msgSender(), _account, block.timestamp);
        return true;
    }

    function renounceAdmin() public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        return revokeAdmin(_msgSender());
    }

    function revokeAdmin(address _account) public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        require(_account != owner(), "BUN: Owner can't revoke himself");
        revokeRole(PAUSER_ROLE, _account); // Admin
        revokeRole(SYSTEM_ROLE, _account); // System
        revokeRole(DEFAULT_ADMIN_ROLE, _account); // Admin
        emit RoleChanged("revokeAdmin", _msgSender(), _account, block.timestamp);
        return true;
    }

    /* events */
    event TokenLock(address indexed lockedToken, address indexed donor, address indexed beneficiary, uint256 amount, uint256 releaseTime, bool revocable, address system, uint256 logTime);
    event RoleChanged(string indexed role, address indexed granter, address indexed grantee, uint256 logTime);
}
