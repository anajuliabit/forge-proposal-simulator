pragma solidity ^0.8.0;

import "@forge-std/console.sol";

import {Proposal} from "./Proposal.sol";
import {Address} from "@utils/Address.sol";
import {Constants} from "@utils/Constants.sol";

abstract contract MultisigProposal is Proposal {
    using Address for address;

    bytes32 public constant MULTISIG_BYTECODE_HASH = bytes32(
        0xb89c1b3bdf2cf8827818646bce9a8f6e372885f8c55e5c07acbd307cb133b000
    );

    struct Call3Value {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    /// @notice get operations for each action, override this to provide custom operations
    function getOperations()
        public
        view
        virtual
        returns (uint8[] memory operations)
    {
        uint256 actionsLength = actions.length;
        operations = new uint8[](actionsLength);

        // Default all operations to 0 (Call operation)
        for (uint256 i = 0; i < actionsLength; i++) {
            operations[i] = 0;
        }
    }

    /// @notice return calldata, log if debug is set to true
    function getCalldata() public view override returns (bytes memory) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory arguments
        ) = getProposalActions();
        uint8[] memory operations = getOperations();

        require(
            targets.length == values.length && values.length == arguments.length
                && arguments.length == operations.length,
            "Array lengths mismatch"
        );

        bytes memory encodedTxs;

        for (uint256 i = 0; i < targets.length; i++) {
            uint8 operation = operations[i];
            address to = targets[i];
            uint256 value = values[i];
            bytes memory data = arguments[i];

            encodedTxs = bytes.concat(
                encodedTxs,
                abi.encodePacked(
                    operation, to, value, uint256(data.length), data
                )
            );
        }

        // The final calldata to send to the MultiSend contract
        return abi.encodeWithSignature("multiSend(bytes)", encodedTxs);
    }

    /// @notice Check if there are any on-chain proposal that matches the
    /// proposal calldata
    function getProposalId() public pure override returns (uint256) {
        revert("Not implemented");
    }

    function _simulateActions(address multisig) internal {
        vm.startPrank(multisig);

        /// this is a hack because multisig execTransaction requires owners signatures
        /// so we cannot simulate it exactly as it will be executed on mainnet
        vm.etch(multisig, Constants.MULTISEND_BYTECODE);

        bytes memory data = getCalldata();

        multisig.functionCall(data);

        /// revert contract code to original safe bytecode
        vm.etch(multisig, Constants.SAFE_BYTECODE);

        vm.stopPrank();
    }
}
