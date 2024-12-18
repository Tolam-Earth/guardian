// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;

import "./RetireImplementation.sol";
import "./retire-single-token/RetireSingleToken.sol";
import "./retire-double-token/RetireDoubleToken.sol";
import "../version/Version.sol";
import "../wipe/interfaces/Wipe_1_0_0.sol";

contract Retire is Version, RetireCommon {
    event PoolAdded(RetireTokenPool[], bool);
    event PoolRemoved(address[]);
    event RetireRequestAdded(address, RetireTokenRequest[]);
    event RetireRequestRemoved(address, address[]);
    event PoolsCleared(uint8);
    event RequestsCleared(uint8);

    function ver() override public pure returns (uint256[3] memory) {
        return [uint256(1),0,1];
    }

    mapping(uint8 => RetireImplementation) implementations;

    constructor() {
        implementations[1] = new RetireSingleToken();
        implementations[2] = new RetireDoubleToken();
    }

    function clearPools(uint8 tc) public override role(OWNER) {
        implementations[tc].clearPools(tc);
        emit PoolsCleared(tc);
    }

    function clearRequests(uint8 tc) public override role(OWNER) {
        implementations[tc].clearRequests(tc);
        emit RequestsCleared(tc);
    }

    function hasImplementation(uint8 tc) external view returns (bool) {
        return implementations[tc] != RetireImplementation(address(0));
    }

    function retire(RetireTokenRequest[] calldata tokens) public override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokenAvailable(tokens[i].token), "PAIR_NOT_AVAILABLE");
            for (uint256 j = 0; j < tokens[i].serials.length; j++) {
                for (uint256 k = j + 1; k < tokens[i].serials.length; k++) {
                    require(
                        tokens[i].serials[j] != tokens[i].serials[k],
                        "NOT_UNIQUE_SERIALS"
                    );
                }
            }
        }
        (bool success, ) = address(implementations[uint8(tokens.length)])
            .delegatecall(
                abi.encodeWithSelector(
                    RetireImplementation.retire.selector,
                    tokens
                )
            );
        require(success);
    }

    function approveRetire(address usr, RetireTokenRequest[] calldata tokens)
        public
        override
        role(ADMIN)
    {
        (bool success, ) = address(implementations[uint8(tokens.length)])
            .delegatecall(
                abi.encodeWithSelector(
                    RetireImplementation.approveRetire.selector,
                    usr,
                    tokens
                )
            );
        require(success);
        address[] memory tIds = _getTokenIds(tokens);
        emit RetireRequestRemoved(usr, tIds);
    }

    function cancelRetire(address[] calldata tokens) public {
        implementations[uint8(tokens.length)].unsetRequest(msg.sender, tokens);
        emit RetireRequestRemoved(msg.sender, tokens);
    }

    function retireCheck(RetireTokenRequest[] calldata tokens)
        public
        override
        returns (bool)
    {
        return implementations[uint8(tokens.length)].retireCheck(tokens);
    }

    function getRequest(address usr, address[] calldata tokens)
        public
        view
        override
        returns (RetireTokenRequest[] memory)
    {
        return implementations[uint8(tokens.length)].getRequest(usr, tokens);
    }

    function setRequest(address usr, RetireTokenRequest[] calldata tokens)
        public
        override
        role(OWNER)
    {
        implementations[uint8(tokens.length)].setRequest(usr, tokens);
        emit RetireRequestAdded(usr, tokens);
    }

    function unsetRequest(address usr, address[] memory tokens)
        public
        override
        role(ADMIN)
    {
        implementations[uint8(tokens.length)].unsetRequest(usr, tokens);
        emit RetireRequestRemoved(usr, tokens);
    }

    function getRequests(uint8 tc) public view override returns (bytes memory) {
        return implementations[tc].getRequests(tc);
    }

    function getPool(address[] memory tokens)
        public
        view
        override
        returns (RetireTokenPool[] memory, bool)
    {
        return implementations[uint8(tokens.length)].getPool(tokens);
    }

    function setPool(RetireTokenPool[] memory tokens, bool immediately)
        public
        override
        role(ADMIN)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            (Wipe tokenContract, uint256[3] memory ver) = wipeContract(tokens[i].token);
            if (ver[0] == 1 && ver[1] == 0 && ver[2] == 0) {
                try Wipe_1_0_0(address(tokenContract)).requestWiper() {} catch {}
            } else {
                try tokenContract.requestWiper(tokens[i].token) {} catch {}
            }
        }
        implementations[uint8(tokens.length)].setPool(tokens, immediately);
        emit PoolAdded(tokens, immediately);
    }

    function unsetPool(address[] memory tokens) public override role(ADMIN) {
        implementations[uint8(tokens.length)].unsetPool(tokens);
        emit PoolRemoved(tokens);
    }

    function getPools(uint8 tc) public view override returns (bytes memory) {
        return implementations[tc].getPools(tc);
    }

    function tokenAvailable(address token) public returns (bool) {
        (Wipe tokenContract, uint256[3] memory ver) = wipeContract(token);
        if (ver[0] == 1 && ver[1] == 0 && ver[2] == 0) {
            return Wipe_1_0_0(address(tokenContract)).isWiper();
        } else {
            return tokenContract.isWiper(token);
        }
    }
}
