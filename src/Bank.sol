// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Bank
/// @notice 去中心化存款合约，支持直接转账存款、余额记录、存款前 10 名排行榜。
/// @dev 排行榜通过存款金额降序的双向链表维护，插入/移除均为 O(n)，n ≤ 10。
contract Bank {
    // ============================
    // STATE VARIABLES
    // ============================

    /// @notice 每个用户的累计存款金额。
    mapping(address => uint256) public deposits;

    /// @notice 排行榜链表头节点（存款金额最高者），address(0) 表示空。
    address public head;

    /// @notice 当前排行榜人数（0 ~ 10）。
    uint256 public topCount;

    /// @notice 链表中下一个节点（存款更少者），address(0) 表示末尾。
    mapping(address => address) private _next;

    /// @notice 链表中上一个节点（存款更多者），address(0) 表示头部。
    mapping(address => address) private _prev;

    // ============================
    // EVENTS
    // ============================

    event Deposited(address indexed user, uint256 amount, uint256 totalDeposit);
    event Withdrawn(address indexed user, uint256 amount, uint256 remaining);
    event Top10Entered(address indexed user);
    event Top10Left(address indexed user);

    // ============================
    // DEPOSIT (via receive)
    // ============================

    /// @notice 直接向合约地址转账即可存款（MetaMask 等钱包均支持）。
    /// @dev 每次存款后自动更新排行榜。
    receive() external payable {
        require(msg.value > 0, "Bank: zero deposit");

        _deposit(msg.sender, msg.value);
    }

    /// @dev 存款核心逻辑，提取为内部函数供扩展调用。
    function _deposit(address user, uint256 amount) private {
        uint256 newTotal = deposits[user] + amount;
        deposits[user] = newTotal;

        emit Deposited(user, amount, newTotal);

        // 用户当前是否在排行榜中
        bool inTop = _isInTopList(user);
        if (inTop) {
            _removeNode(user);
        }

        // 判断是否应进入排行榜
        if (_qualifies(user)) {
            _insertSorted(user);

            // 超过 10 人时踢出存款最低者
            if (topCount > 10) {
                address tail = _getTail();
                _removeNode(tail);
                emit Top10Left(tail);
            }

            emit Top10Entered(user);
        }
    }

    // ============================
    // WITHDRAW
    // ============================

    /// @notice 提取存款。
    /// @param amount 提取金额（wei）。
    function withdraw(uint256 amount) external {
        require(amount > 0, "Bank: zero withdraw");
        require(deposits[msg.sender] >= amount, "Bank: insufficient balance");

        // 先退出排行榜（余额变了，排名需重算）
        bool inTop = _isInTopList(msg.sender);
        if (inTop) {
            _removeNode(msg.sender);
        }

        deposits[msg.sender] -= amount;
        uint256 remaining = deposits[msg.sender];

        // 余额 > 0 且符合条件则重新入榜
        if (remaining > 0 && _qualifies(msg.sender)) {
            _insertSorted(msg.sender);
        } else if (inTop) {
            emit Top10Left(msg.sender);
        }

        emit Withdrawn(msg.sender, amount, remaining);

        // 转账 ETH 给用户（使用 call 而非 transfer，避免 2300 gas 限制）
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "Bank: transfer failed");
    }

    // ============================
    // READ
    // ============================

    /// @notice 获取当前排行榜前 10 名（按存款金额降序）。
    /// @return addrs   用户地址数组。
    /// @return amounts 对应存款金额数组。
    function getTop10()
        external
        view
        returns (address[] memory addrs, uint256[] memory amounts)
    {
        uint256 count = topCount;
        addrs = new address[](count);
        amounts = new uint256[](count);

        address current = head;
        uint256 i = 0;
        while (current != address(0)) {
            addrs[i] = current;
            amounts[i] = deposits[current];
            current = _next[current];
            unchecked {
                ++i;
            }
        }
    }

    /// @notice 查询用户当前是否在排行榜中。
    function isInTop10(address user) external view returns (bool) {
        return _isInTopList(user);
    }

    // ============================
    // INTERNAL HELPERS
    // ============================

    /// @dev 判断地址是否在链表中。
    function _isInTopList(address user) private view returns (bool) {
        if (head == address(0)) return false;
        if (user == head) return true;
        // 非头节点则有前驱或后继（头插后删过的节点两者均为 0）
        return _prev[user] != address(0) || _next[user] != address(0);
    }

    /// @dev 判断用户是否应进入排行榜（名额未满 或 余额高于榜尾）。
    function _qualifies(address user) private view returns (bool) {
        if (topCount < 10) return true;
        address tail = _getTail();
        // 存款额持平且为同一人（withdraw 重新插入时）也允许进入
        return deposits[user] > deposits[tail];
    }

    /// @dev 按存款金额降序插入节点。
    function _insertSorted(address user) private {
        uint256 userDeposit = deposits[user];

        address prevNode;
        address current = head;

        // 找到第一个存款额 < userDeposit 的节点，插入其前方
        while (current != address(0) && deposits[current] >= userDeposit) {
            prevNode = current;
            current = _next[current];
        }

        _next[user] = current;
        _prev[user] = prevNode;

        if (prevNode == address(0)) {
            head = user; // 新头部
        } else {
            _next[prevNode] = user;
        }

        if (current != address(0)) {
            _prev[current] = user;
        }

        unchecked {
            ++topCount;
        }
    }

    /// @dev 从链表中摘除节点。
    function _removeNode(address user) private {
        address prevNode = _prev[user];
        address nextNode = _next[user];

        if (prevNode == address(0)) {
            head = nextNode;
        } else {
            _next[prevNode] = nextNode;
        }

        if (nextNode != address(0)) {
            _prev[nextNode] = prevNode;
        }

        delete _next[user];
        delete _prev[user];

        unchecked {
            --topCount;
        }
    }

    /// @dev 获取链表尾部节点（存款最低者）。
    function _getTail() private view returns (address) {
        address current = head;
        if (current == address(0)) return address(0);
        while (_next[current] != address(0)) {
            current = _next[current];
        }
        return current;
    }
}
