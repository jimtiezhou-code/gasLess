# Bank 合约链表原理

## 一、为什么用链表？

排行榜需要按存款金额**降序排列**，且支持**动态插入和删除**。Solidity 中 `mapping` 不可遍历，`array` 的中间插入/删除是 O(n) 且 gas 高。

双向链表用两个 `mapping` 串联节点，插入和删除只需修改相邻节点的指针，均为 O(1)（不含遍历找位置）。由于排行榜仅维护前 10 名，遍历成本极低。

## 二、数据结构

```
_head → A(30 ETH) ⇄ B(25) ⇄ C(15) ⇄ D(10) → 0
         ▲ 最高                            ▲ 榜尾（最低）
```

### 存储变量

| 变量 | 类型 | 含义 |
|------|------|------|
| `head` | `address` | 链表头节点（金额最高者），`address(0)` 表示空 |
| `_next[a]` | `mapping` | 节点 a 的下一个节点（金额更少者），`0` 表示末尾 |
| `_prev[a]` | `mapping` | 节点 a 的上一个节点（金额更多者），`0` 表示头部 |
| `topCount` | `uint256` | 当前节点数（0~10） |

### 空链表判断

```
head == address(0)  →  链表为空
```

### 节点是否在链表中

```
user == head                          → 是头节点
_prev[user] != address(0)             → 非头节点，有前驱
_next[user] != address(0)             → 非尾节点，有后继
三者满足其一即说明在链表中
```

## 三、插入操作（头插 + 排序插）

### 3.1 遍历找插入点

```solidity
address prevNode;
address current = head;

// 从头开始，找到第一个存款额 < userDeposit 的节点
while (current != address(0) && deposits[current] >= userDeposit) {
    prevNode = current;
    current = _next[current];
}
// 此时 prevNode 是最后一个 >= user 的节点
// current 是第一个 < user 的节点（或 address(0)）
// 插入位置：prevNode 和 current 之间
```

### 3.2 链接新节点

```solidity
_next[user] = current;    // 新节点 → 后面的节点
_prev[user] = prevNode;   // 新节点 ← 前面的节点

if (prevNode == address(0)) {
    head = user;           // 插入到头部
} else {
    _next[prevNode] = user;// 前面的节点 → 新节点
}

if (current != address(0)) {
    _prev[current] = user; // 后面的节点 ← 新节点
}
```

### 3.3 可视化示例

链表现状：`A(30) → C(15) → D(10) → 0`

插入 B(20 ETH)：

```
步骤 1：遍历
  current=A(30)  deposits[A]=30 >= 20  → prevNode=A, current=C
  current=C(15)  deposits[C]=15 <  20  → 停止
  插入点：A 和 C 之间

步骤 2：链接
  _next[B] = C          # B → C
  _prev[B] = A          # B ← A
  _next[A] = B          # A → B
  _prev[C] = B          # C ← B

结果：A(30) → B(20) → C(15) → D(10) → 0
```

## 四、删除操作

### 4.1 摘除节点

```solidity
address prevNode = _prev[user];  // 前驱
address nextNode = _next[user];  // 后继

// 修复前驱的 next 指针
if (prevNode == address(0)) {
    head = nextNode;            // 删除的是头节点
} else {
    _next[prevNode] = nextNode; // 跳过 user
}

// 修复后继的 prev 指针
if (nextNode != address(0)) {
    _prev[nextNode] = prevNode; // 跳过 user
}

// 清理 user 的指针（可获得 gas 退款）
delete _next[user];
delete _prev[user];
```

### 4.2 可视化示例

链表现状：`A(30) → B(20) → C(15) → D(10) → 0`

删除 B：

```
步骤 1：读取邻居
  prevNode = _prev[B] = A
  nextNode = _next[B] = C

步骤 2：跳过 B
  _next[A] = C           # A → C
  _prev[C] = A           # C ← A

步骤 3：清理
  delete _next[B]
  delete _prev[B]

结果：A(30) → C(15) → D(10) → 0
```

## 五、完整存款流程

```
用户向合约转 ETH
        │
        ▼
  deposits[user] += msg.value
        │
        ▼
  用户当前在排行榜中？
    ├─ Yes → _removeNode(user)，topCount--
    │
    ▼
  用户符合入榜条件？
  （topCount < 10 或 余额 > 榜尾余额）
    │
    ├─ Yes → _insertSorted(user)，topCount++
    │         │
    │         ▼
    │       topCount > 10？
    │         ├─ Yes → 找榜尾 _getTail() → _removeNode(tail)
    │         │         emit Top10Left(tail)
    │         │
    │         ▼
    │       emit Top10Entered(user)
    │
    └─ No  → 不入榜，仅记录余额
```

## 六、榜尾查找（O(n)，n≤10）

```solidity
function _getTail() private view returns (address) {
    address current = head;
    if (current == address(0)) return address(0);
    while (_next[current] != address(0)) {
        current = _next[current];
    }
    return current;
}
```

从头节点出发，沿 `_next` 一直走到 `address(0)`，最后一个节点即是榜尾（存款最低者）。

## 七、查询全部前 10 名

```solidity
function getTop10() external view returns (address[] memory, uint256[] memory) {
    uint256 count = topCount;
    address[] memory addrs = new address[](count);
    uint256[] memory amounts = new uint256[](count);

    address current = head;
    uint256 i = 0;
    while (current != address(0)) {
        addrs[i] = current;
        amounts[i] = deposits[current];
        current = _next[current];
        unchecked { ++i; }
    }
}
```

从头遍历到尾，依次收集地址和金额，返回两个并行数组。前端可直接渲染为排行榜。

## 八、与 SchoolV2 链表的对比

| 特性 | SchoolV2 | Bank |
|------|----------|------|
| 排序方式 | 按添加时间（头插，无序） | 按存款金额（降序） |
| 插入策略 | 固定插在头部 O(1) | 遍历找位置 O(n)，n≤10 |
| 容量限制 | 无 | 最多 10 人 |
| 相同值处理 | 后添加在前 | 先到者在前（≥ 运算符） |
| 节点按值变化 | 不存在（地址不变） | 存款增加后需摘除 + 重插 |
| 踢出机制 | 无 | 超 10 人自动踢出榜尾 |

## 九、Gas 分析

| 操作 | 存储写入次数 | 说明 |
|------|:--:|------|
| 用户首次存款入榜 | ~4 SSTORE | `deposits`, `_next`, `_prev`, `head`（如首位） |
| 用户在榜中追加存款 | ~6 SSTORE | remove(2) + insert(4)，含 delete 退款 |
| 榜外用户存款超榜尾 | ~7 SSTORE | insert(4) + removeTail(3) |
| 提款后重排 | ~6 SSTORE | remove(2) + insert(4) |
| 遍历查询 | 0 SSTORE | 纯 `view` 函数，不消耗 gas |
