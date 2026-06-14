// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library Create2Utils {
    error DeterministicDeployerUnavailable(address deployer);
    error DeterministicDeployFailed(address expected);

    address internal constant DETERMINISTIC_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function getAddress(bytes memory initCode, bytes32 salt) internal pure returns (address expected) {
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 rawAddress = keccak256(abi.encodePacked(bytes1(0xff), DETERMINISTIC_DEPLOYER, salt, initCodeHash));
        expected = address(uint160(uint256(rawAddress)));
    }

    function getAddressExists(bytes memory initCode, bytes32 salt) internal view returns (address expected, bool exists) {
        expected = getAddress(initCode, salt);
        exists = expected.code.length > 0;
    }

    function getOrDeploy(bytes memory initCode, bytes32 salt) internal returns (address deployed, bool existed) {
        (deployed, existed) = getAddressExists(initCode, salt);
        if (existed) return (deployed, true);
        if (DETERMINISTIC_DEPLOYER.code.length == 0) revert DeterministicDeployerUnavailable(DETERMINISTIC_DEPLOYER);

        (bool success,) = DETERMINISTIC_DEPLOYER.call(abi.encodePacked(salt, initCode));
        if (!success || deployed.code.length == 0) revert DeterministicDeployFailed(deployed);
    }
}
