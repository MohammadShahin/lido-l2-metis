// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/**
 * @title iOVM_SequencerFeeVaultMetis
 * @dev Simple holding contract for fees paid to the Sequencer. Likely to be replaced in the future
 * but "good enough for now".
 */
interface iOVM_SequencerFeeVaultMetis {
    /*************
     * Constants *
     *************/

    event ChainSwitch(address l1Wallet, address l2Manager);
    event ConfigChange(bytes config);

    /********************
     * Public Functions *
     ********************/

    function withdraw(uint256 amount) external payable;

    function finalizeChainSwitch(
        address _FeeWallet,
        address _L2Manager
    ) external;

    function finalizeChainConfig(bytes calldata config) external;

    function send(address payable to, uint256 amount) external;

    function sendBatch(
        address payable[] calldata tos,
        uint256[] calldata amounts
    ) external;

    function getL2Manager() external view returns (address);
}
