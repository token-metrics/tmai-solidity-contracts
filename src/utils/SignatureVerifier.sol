// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
    @title SignatureVerifier
    @notice This contract provides signature verification functionalities to ensure that messages are authorized.
    It supports both governance and payment verification.
 */
contract SignatureVerifier is Initializable {
    using ECDSA for bytes32;

    // Struct to store signature data
    struct Signature {
        bytes encodedMessage;
        bytes32 messageHash;
        bytes signature;
    }

    // Struct to store the decoded governance message
    struct GovernanceMessage {
        address userAddress;
        uint256 proposalId;
        uint256 averageBalance;
        bool support;
        uint256 totalTokenHolders;
        uint256 validity;
    }

    // Struct to store the decoded payment message
    struct PaymentMessage {
        address userAddress;
        uint8 product;
        uint8 planType;
        uint256 expiryDate;
        address token;
        uint256 tokenAmount;
        uint256 validity;
        uint256 nonce;
    }

    address public signerAddress; // The address corresponding to the private key that signs the messages

    /**
        @notice Initializes the contract with the address of the signer.
        @param _signerAddress The address of the signer.
     */
    function initialize(address _signerAddress) public initializer {
        require(
            _signerAddress != address(0),
            "Signer address cannot be zero address"
        );
        signerAddress = _signerAddress;
    }

    /**
        @notice Retrieves the hash of the original message.
        @param _data The original encoded message.
        @return The keccak256 hash of the message.
     */
    function getMessageHash(
        bytes memory _data
    ) internal pure returns (bytes32) {
        return keccak256(_data);
    }

    /**
        @notice Converts the message hash to the Ethereum signed message hash.
        @param _messageHash The original message hash.
        @return The Ethereum signed message hash.
     */
    function getEthSignedMessageHash(
        bytes32 _messageHash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    _messageHash
                )
            );
    }

    /**
        @notice Verifies the governance message signature.
        @param _signature The signature data containing the message, hash, and signature.
        @return The decoded GovernanceMessage struct if the signature is valid.
     */
    function verifyGovernanceSignature(
        Signature memory _signature
    ) public view returns (GovernanceMessage memory) {
        // Verify the message hash and signature
        verifySigner(_signature);

        // Decode and validate the governance message
        (
            address userAddress,
            uint256 proposalId,
            uint256 averageBalance,
            bool support,
            uint256 totalTokenHolders,
            uint256 validity
        ) = abi.decode(
                _signature.encodedMessage,
                (address, uint256, uint256, bool, uint256, uint256)
            );

        // Check message validity
        checkMessageValidity(validity);

        return
            GovernanceMessage(
                userAddress,
                proposalId,
                averageBalance,
                support,
                totalTokenHolders,
                validity
            );
    }

    /**
        @notice Verifies the payment message signature.
        @param _signature The signature data containing the message, hash, and signature.
        @return The decoded PaymentMessage struct if the signature is valid.
     */
    function verifyPaymentSignature(
        Signature memory _signature
    ) public view returns (PaymentMessage memory) {
        // Verify the message hash and signature
        verifySigner(_signature);

        // Decode and validate the payment message
        (
            address userAddress,
            uint8 product,
            uint8 planType,
            uint256 expiryDate,
            address token,
            uint256 tokenAmount,
            uint256 validity,
            uint256 nonce
        ) = abi.decode(
                _signature.encodedMessage,
                (
                    address,
                    uint8,
                    uint8,
                    uint256,
                    address,
                    uint256,
                    uint256,
                    uint256
                )
            );

        // Check message validity
        checkMessageValidity(validity);

        return
            PaymentMessage(
                userAddress,
                product,
                planType,
                expiryDate,
                token,
                tokenAmount,
                validity,
                nonce
            );
    }

    /**
        @notice Verifies the signer of the message by recovering the signer's address from the signature.
        @param _signature The signature data containing the message, hash, and signature.
     */
    function verifySigner(Signature memory _signature) internal view {
        // Recreate the message hash from the encoded message
        require(
            getMessageHash(_signature.encodedMessage) == _signature.messageHash,
            "Message hash does not match the original!"
        );

        // Get the Ethereum signed message hash
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(
            _signature.messageHash
        );

        // Recover the signer's address from the signature
        address recoveredSigner = ethSignedMessageHash.recover(
            _signature.signature
        );
        require(recoveredSigner == signerAddress, "Invalid signer");
    }

    /**
        @notice Checks the validity of the decoded message, ensuring it hasn't expired.
        @param _validity The block number indicating the validity of the message.
     */
    function checkMessageValidity(uint256 _validity) internal view {
        require(_validity >= block.number, "Message is expired");
    }
}
