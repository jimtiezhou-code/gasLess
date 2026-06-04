// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title AirdropMerkleNFTMarket
/// @notice 组合 Multicall + Merkle Tree + ERC20 Permit 的优惠价 NFT 购买合约。
/// @dev 用户通过一次 multicall 交易完成 permit 预授权 + 白名单验证 + 代币支付 + NFT 铸造。
///
/// 流程：
///   1. 用户离线签名 ERC-20 permit（授权合约划转 100 Token）
///   2. 用户调用 multicall([permitPrePay, claimNFT])
///   3. 合约内部先执行 permit 预授权，再验证默克尔白名单并划转 + 铸币
contract AirdropMerkleNFTMarket {
    // ============================
    // STATE
    // ============================

    /// @notice 默克尔树根（链下脚本生成）。
    bytes32 public merkleRoot;

    /// @notice 支付代币合约（需支持 EIP-2612 permit）。
    address public paymentToken;

    /// @notice NFT 合约地址。
    address public nftContract;

    /// @notice 优惠价格（代币最小单位）。
    uint256 public constant DISCOUNT_PRICE = 100 * 10**18; // 100 Token

    /// @notice 合约所有者。
    address public owner;

    /// @notice 已领取过的地址（防双花）。
    mapping(address => bool) public hasClaimed;

    // ============================
    // EVENTS
    // ============================

    event Claimed(address indexed user, uint256 tokenId, uint256 price);
    event RootUpdated(bytes32 oldRoot, bytes32 newRoot);

    // ============================
    // MODIFIERS
    // ============================

    modifier onlyOwner() {
        require(msg.sender == owner, "Market: not owner");
        _;
    }

    // ============================
    // CONSTRUCTOR
    // ============================

    constructor(bytes32 _merkleRoot, address _paymentToken, address _nftContract) {
        owner = msg.sender;
        merkleRoot = _merkleRoot;
        paymentToken = _paymentToken;
        nftContract = _nftContract;
    }

    // ============================
    // OWNER
    // ============================

    /// @notice 更新白名单（更换默克尔根）。
    function setMerkleRoot(bytes32 _newRoot) external onlyOwner {
        emit RootUpdated(merkleRoot, _newRoot);
        merkleRoot = _newRoot;
    }

    // ============================
    // STEP 1 — PERMIT PRE-PAY
    // ============================

    /// @notice 执行 ERC-20 permit，授权合约划转 DISCOUNT_PRICE 代币。
    /// @dev 供 multicall 第一个调用，也可独立使用。
    function permitPrePay(
        address owner_,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // 调用 token.permit(owner, spender=this, value=100, deadline, v, r, s)
        (bool ok, ) = paymentToken.call(
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                owner_,
                address(this),
                DISCOUNT_PRICE,
                deadline,
                v,
                r,
                s
            )
        );
        require(ok, "Market: permit failed");
    }

    // ============================
    // STEP 2 — CLAIM NFT
    // ============================

    /// @notice 白名单验证 + 代币划转 + NFT 铸造。
    /// @dev 需要 permitPrePay 已完成授权，否则 transferFrom 会失败。
    function claimNFT(bytes32[] calldata proof) external returns (uint256) {
        require(!hasClaimed[msg.sender], "Market: already claimed");
        require(_verifyMerkle(proof, msg.sender), "Market: not in whitelist");

        hasClaimed[msg.sender] = true;

        // 使用 permit 授权从用户转 100 Token 到合约
        (bool transferOk, ) = paymentToken.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                msg.sender,
                address(this),
                DISCOUNT_PRICE
            )
        );
        require(transferOk, "Market: transferFrom failed");

        // 铸造 NFT 给用户
        (bool mintOk, bytes memory mintData) = nftContract.call(
            abi.encodeWithSignature("mint(address,string)", msg.sender, "")
        );
        require(mintOk, "Market: mint failed");
        uint256 tokenId = abi.decode(mintData, (uint256));

        emit Claimed(msg.sender, tokenId, DISCOUNT_PRICE);
        return tokenId;
    }

    // ============================
    // MULTICALL (delegateCall)
    // ============================

    /// @notice 批量调用（使用 delegateCall 保持 msg.sender 上下文一致）。
    /// @dev 每条 data[i] 对应 abi.encodeWithSignature("functionName(...)", ...)
    ///      典型的调用序列：
    ///         data[0] = permitPrePay(owner, deadline, v, r, s)
    ///         data[1] = claimNFT(proof)
    function multicall(bytes[] calldata data) external returns (bytes[] memory) {
        bytes[] memory results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool ok, bytes memory result) = address(this).delegatecall(data[i]);
            if (!ok) {
                // 提取 revert reason
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
            results[i] = result;
        }
        return results;
    }

    // ============================
    // MERKLE VERIFICATION
    // ============================

    /// @dev 验证地址是否在白名单默克尔树中。
    function _verifyMerkle(bytes32[] calldata proof, address user) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(user));
        bytes32 current = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            current = _hashPair(current, proof[i]);
        }
        return current == merkleRoot;
    }

    /// @dev 排序后哈希，防止 second-preimage 攻击。
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        if (a < b) {
            return keccak256(abi.encodePacked(a, b));
        } else {
            return keccak256(abi.encodePacked(b, a));
        }
    }
}
