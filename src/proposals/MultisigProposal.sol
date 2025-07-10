pragma solidity ^0.8.0;

import "@forge-std/console.sol";

import {Proposal} from "./Proposal.sol";
import {Address} from "@utils/Address.sol";
import {Constants} from "@utils/Constants.sol";

abstract contract MultisigProposal is Proposal {
    using Address for address;

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
                && arguments.length == operations.length
                && operations.length == actions.length,
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

        bytes memory data = getCalldata();

        // this is a hack because multisig execTransaction requires owners signatures
        // so the SAFE_CREATION_BYTECODE override the checkNSignatures function
        bytes memory bytecode = Constants.SAFE_CREATION_BYTECODE;
        address addr;
        /// @solidity memory-safe-assembly
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        vm.etch(multisig, address(addr).code);

        bytes memory safeCalldata = abi.encodeWithSignature(
            "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)",
            Constants.SAFE_MULTISEND_COTNRACT,
            0,
            data,
            1,
            0,
            0,
            0,
            address(0),
            address(0),
            ""
        );

        multisig.functionCall(safeCalldata);

        vm.stopPrank();
    }
}
