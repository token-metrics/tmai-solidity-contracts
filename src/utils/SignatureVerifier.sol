// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
    @title SignatureVerifier
    @notice This contract provides signature verification functionalities to ensure that messages are authorized.
 */
contract SignatureVerifier is Initializable {
    using ECDSA for bytes32;

    // Struct to store signature data
    struct Signature {
        bytes encodedMessage;
        bytes32 messageHash;
        bytes signature;
    }

    // Struct to store the decoded message
    struct EncodedMessage {
        address userAddress;
        string section;
        string planType;
        uint256 expiryDate;
        address token;
        uint256 tokenAmount;
        uint256 validity;
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
        @notice Verifies that the signature matches the signed message.
        @param _signature The signature data containing the message, hash, and signature.
        @return The decoded message if the signature is valid.
     */
    function verifySignature(
        Signature memory _signature
    ) public view returns (EncodedMessage memory) {
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

        // Decode the message and validate its integrity
        address userAddress;
        string memory section;
        string memory planType;
        uint256 expiryDate;
        address token;
        uint256 tokenAmount;
        uint256 validity;

        // Decode the message with token and token amount embedded
        (
            userAddress,
            section,
            planType,
            expiryDate,
            token,
            tokenAmount,
            validity
        ) = abi.decode(
            _signature.encodedMessage,
            (address, string, string, uint256, address, uint256, uint256)
        );
        EncodedMessage memory decodedMessage = EncodedMessage(
            userAddress,
            section,
            planType,
            expiryDate,
            token,
            tokenAmount,
            validity
        );

        checkMessageValidity(decodedMessage);

        return decodedMessage;
    }

    /**
        @notice Checks the validity of the decoded message, ensuring it hasn't expired.
        @param _decodedMessage The decoded message to validate.
     */
    function checkMessageValidity(
        EncodedMessage memory _decodedMessage
    ) internal view {
        require(_decodedMessage.validity >= block.number, "Message is expired");
    }
}
