// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IL1ERC20BridgeMetis} from "./interfaces/IL1ERC20Bridge.sol";
import {IL2ERC20BridgeMetis} from "./interfaces/IL2ERC20Bridge.sol";
import {IMessageNonceHandler} from "./interfaces/IMessageNonceHandler.sol";
import {IERC20Bridged} from "../token/interfaces/IERC20Bridged.sol";

import {BridgingManagerEnumerable} from "../BridgingManagerEnumerable.sol";
import {BridgeableTokens} from "../BridgeableTokens.sol";
import {CrossDomainEnabledMetis} from "./CrossDomainEnabled.sol";

import {OVM_GasPriceOracleMetis} from "./predeploys/OVM_GasPriceOracle.sol";
import {Lib_PredeployAddresses} from "./libraries/Lib_PredeployAddresses.sol";
import { Lib_CrossDomainUtils } from "./libraries/Lib_CrossDomainUtils.sol";
import {Lib_Uint} from "./utils/Lib_Uint.sol";

/// @notice The L2 token bridge works with the L1 token bridge to enable ERC20 token bridging
///     between L1 and L2. It acts as a minter for new tokens when it hears about
///     deposits into the L1 token bridge. It also acts as a burner of the tokens
///     intended for withdrawal, informing the L1 bridge to release L1 funds. Additionally, adds
///     the methods for bridging management: enabling and disabling withdrawals/deposits
contract L2ERC20TokenBridgeMetis is
    IL2ERC20BridgeMetis,
    BridgingManagerEnumerable,
    BridgeableTokens,
    CrossDomainEnabledMetis
{
    /// @inheritdoc IL2ERC20BridgeMetis
    address public immutable l1TokenBridge;

    uint256 public constant MAX_ROLLUP_TX_SIZE = 50000;

    /// @param messenger_ L2 messenger address being used for cross-chain communications
    /// @param l1TokenBridge_  Address of the corresponding L1 bridge
    /// @param l1Token_ Address of the bridged token in the L1 chain
    /// @param l2Token_ Address of the token minted on the L2 chain when token bridged
    constructor(
        address messenger_,
        address l1TokenBridge_,
        address l1Token_,
        address l2Token_
    ) CrossDomainEnabledMetis(messenger_) BridgeableTokens(l1Token_, l2Token_) {
        l1TokenBridge = l1TokenBridge_;
    }

    /// @inheritdoc IL2ERC20BridgeMetis
    function withdraw(
        address l2Token_,
        uint256 amount_,
        uint32 l1Gas_,
        bytes calldata data_
    ) external payable whenWithdrawalsEnabled onlySupportedL2Token(l2Token_) {
        if (Address.isContract(msg.sender)) {
            revert ErrorSenderNotEOA();
        }
        _initiateWithdrawal(msg.sender, msg.sender, amount_, l1Gas_, data_);
    }

    function withdrawMetis(
        uint256,
        uint32,
        bytes calldata
    ) external payable virtual {
        revert ErrorNotImplemented();
    }

    /// @inheritdoc IL2ERC20BridgeMetis
    function withdrawTo(
        address l2Token_,
        address to_,
        uint256 amount_,
        uint32 l1Gas_,
        bytes calldata data_
    ) external payable whenWithdrawalsEnabled onlySupportedL2Token(l2Token_) onlyNonZeroAccount(to_) {
        _initiateWithdrawal(msg.sender, to_, amount_, l1Gas_, data_);
    }

    function withdrawMetisTo(
        address,
        uint256,
        uint32,
        bytes calldata
    ) external payable virtual {
        revert ErrorNotImplemented();
    }

    /// @inheritdoc IL2ERC20BridgeMetis
    function finalizeDeposit(
        address l1Token_,
        address l2Token_,
        address from_,
        address to_,
        uint256 amount_,
        bytes calldata data_
    )
        external
        whenDepositsEnabled
        onlySupportedL1Token(l1Token_)
        onlySupportedL2Token(l2Token_)
        onlyFromCrossDomainAccount(l1TokenBridge)
    {
        // Theses check were removed because after running the modifiers, the L1 and L2 token
        // addresses are already checked
        // 
        // Check the target token is compliant and
        // verify the deposited token on L1 matches the L2 deposited token representation here
        // if (
        //     ERC165Checker.supportsInterface(_l2Token, 0x1d1d8b63) &&
        //     _l1Token == IL2StandardERC20(_l2Token).l1Token()
        // ) {
        //     // When a deposit is finalized, we credit the account on L2 with the same amount of
        //     // tokens.
        //     IERC20Bridged(l2Token_).bridgeMint(to_, amount_);
        //     emit DepositFinalized(l1Token_, l2Token_, from_, to_, amount_, data_);
        // } else {
        //     emit DepositFailed(l1Token_, l2Token_, from_, to_, amount_, data_);
        // }

        IERC20Bridged(l2Token_).bridgeMint(to_, amount_);
        emit DepositFinalized(l1Token_, l2Token_, from_, to_, amount_, data_);
    }

    /**
     * @dev Performs the logic for deposits by storing the token and informing the L2 token Gateway
     * of the deposit.
     * @param from_ Account to pull the deposit from on L2.
     * @param to_ Account to give the withdrawal to on L1.
     * @param amount_ Amount of the token to withdraw.
     * param l1Gas_ Unused, but included for potential forward compatibility considerations.
     * @param data_ Optional data to forward to L1. This data is provided
     *        solely as a convenience for external contracts. Aside from enforcing a maximum
     *        length, these contracts provide no guarantees about its content.
     */
    function _initiateWithdrawal(
        address from_,
        address to_,
        uint256 amount_,
        uint32 l1Gas_,
        bytes calldata data_
    ) internal {

        if (amount_ == 0) {
            revert ErrorZeroAmount();
        }

        uint256 minErc20BridgeCost = OVM_GasPriceOracleMetis(
            Lib_PredeployAddresses.OVM_GASPRICE_ORACLE
        ).minErc20BridgeCost();

        // require minimum gas
        require(
            msg.value >= minErc20BridgeCost,
            string(
                abi.encodePacked(
                    "insufficient withdrawal fee supplied. need at least ",
                    Lib_Uint.uint2str(minErc20BridgeCost)
                )
            )
        );

        // Construct calldata for l1TokenBridge.finalizeERC20Withdrawal(to_, amount_)
        bytes memory message = abi.encodeWithSelector(
            IL1ERC20BridgeMetis.finalizeERC20Withdrawal.selector,
            l1Token,
            l2Token,
            from_,
            to_,
            amount_,
            data_
        );

        // build the xDomain calldata and check if it exceeds the maximum rollup tx size to prevent gas griefing attacks
        // this should be done in l2 xDomainMessenger and it will be added in a future release

        uint256 messageNonce = IMessageNonceHandler(address(messenger)).messageNonce();
        bytes memory xDomainCalldata = Lib_CrossDomainUtils.encodeXDomainCalldata(
            l1TokenBridge,
            address(this),
            message,
            messageNonce
        );

        require(
            xDomainCalldata.length <= MAX_ROLLUP_TX_SIZE, 
            "Transaction data size exceeds maximum for rollup transaction."
        );

        // When a withdrawal is initiated, we burn the withdrawer's funds to prevent subsequent L2
        // usage
        IERC20Bridged(l2Token).bridgeBurn(from_, amount_);

        // Send message up to L1 bridge
        sendCrossDomainMessage(
            l1TokenBridge,
            l1Gas_,
            message,
            msg.value // send all value as fees to cover relayer cost
        );

        emit WithdrawalInitiated(
            l1Token,
            l2Token,
            msg.sender,
            to_,
            amount_,
            data_
        );
    }

    error ErrorSenderNotEOA();
    error ErrorNotImplemented();
    error ErrorZeroAmount();
}
