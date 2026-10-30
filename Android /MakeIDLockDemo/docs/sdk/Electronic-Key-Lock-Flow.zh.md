> SDK接口资料快照，非本Demo已完成全部功能的说明。运行/交付状态以工程根README为准。

# 电子钥匙开关锁逻辑

## 一、总览

电子钥匙支持两种设备类型的开关锁：

| 设备 | 开锁命令 | 流程 | 加密方式 | 密码最短长度 |
|------|----------|------|----------|-------------|
| KY53E | 0xA3 | **两步式**：先读锁SN(0xA1) → 再开锁(0xA3) | 锁芯侧密钥 | 4 字节 |
| KY53N | 0xA5 | **一步式**：直接开锁(0xA5) | 电子钥匙侧密钥 | 1 字节 |

两个入口（`MkdElectronicKeyManager` 直连 / `ReaderElectronicKeyAdapter` 读写器中转）的开关锁逻辑**完全一致**，差异仅在于数据发送通道不同。

---

## 二、KY53E 开关锁（两步式）

### 2.1 整体时序

```
App                        电子钥匙                   锁芯
 │                            │                        │
 │  1. 前置校验                │                        │
 │     - 已连接?               │                        │
 │     - 锁芯已连接? (心跳)      │                        │
 │     - 密码长度 ≥ 4字节       │                        │
 │                            │                        │
 │  2. 保存待处理状态            │                        │
 │     pendingUnlockPassword   │                        │
 │     pendingUnlockIsOpen     │                        │
 │     pendingUnlockSmSecret   │                        │
 │                            │                        │
 │── 0xA1 读锁序列号 ────────→│                        │
 │     (明文 0x71, 21字节)     │── 查询锁芯 ──────────→│
 │                            │←─ SN(12B)+随机数(4B) ─│
 │←── LockInfo ──────────────│                        │
 │                            │                        │
 │  3. 校验 LockInfo           │                        │
 │     - lockRandom 非空       │                        │
 │     - 锁侧 smSecret 有效    │                        │
 │                            │                        │
 │  4. 构建开锁载荷 (16字节)     │                        │
 │     [0-3]   锁随机数(4B)    │                        │
 │     [4-7]   密码(4B)        │                        │
 │     [8]     动作: 0x03=开   │                        │
 │                    0x0C=关   │                        │
 │     [9-10]  阈值(2B, 开锁=0)│                        │
 │     [11-15] 保留(5B)        │                        │
 │     ↓ 锁芯侧密钥加密         │                        │
 │                            │                        │
 │── 0xA3 开锁 ──────────────→│                        │
 │     (加密 0x73, 21字节)     │── 验证 ──────────────→│
 │                            │←── 结果 ──────────────│
 │←── 响应 ──────────────────│                        │
 │                            │                        │
 │  5. 解析响应                │                        │
 │     锁芯侧密钥解密           │                        │
 │     byte[0]: 0x00=成功      │                        │
 │               0xFF=不支持    │                        │
 │               其他=失败      │                        │
 │     byte[7]: 动作回显        │                        │
 │                            │                        │
 │  6. 回调 onUnlock(success, isOpen)                  │
```

### 2.2 入口代码逻辑（MkdElectronicKeyManager.unlock）

```java
public void unlock(String lockKey, boolean isOpen, String explicitSmSecret) {
    // ① 前置校验
    if (!isConnected()) → onUnlockListener.onError(CONNECT_FAIL)
    if (TextUtils.isEmpty(lockKey)) → onUnlockListener.onError(PASSWORD_FORMAT_ERROR)
    byte[] passwordBytes = StringUtils.toByteArray(lockKey, "");
    if (!protocol.isLockPasswordValid(passwordBytes))  // KY53E: length >= 4
        → onUnlockListener.onError(PASSWORD_FORMAT_ERROR)

    // ② KY53E 分支：走两步式流程
    if (currentKeyType == ElectronicKeyType.KY53E) {
        // 必须先有心跳确认锁芯已连接
        if (heartEntity == null || heartEntity.getLockCylinderState() == 0)
            → onUnlockListener.onError(NOT_CONNECT_LOCK)

        // 保存待处理状态
        pendingUnlockPassword = lockKey;
        pendingUnlockIsOpen = isOpen;
        pendingUnlockUid = buildCurrentDeviceId();      // BLE MAC 去冒号补零到16字节
        pendingUnlockSmSecret = sanitizeSmSecret(explicitSmSecret);

        // 发送 0xA1 读取锁序列号
        sendCommand(protocol.getLockSerialNumberCmd(resolvePendingUnlockUid()));
        return;  // 等待 0xA1 响应后继续
    }

    // ③ KY53N 分支：走一步式流程（见第三章）
    ...
}
```

### 2.3 0xA1 响应处理 → 触发 0xA3

```java
// dispatchMakeIdResponse 中 cmd == 0xA1 分支：
case 0xA1:
    LockInfo lockInfo = protocol.dealLockSerialNumber(dataBuffer);
    latestLockInfo = lockInfo;

    // 通知 readSerialNo 监听器
    if (onReadSerialNoListener != null) { ... }

    // KY53E 自动衔接：先检查是否有待处理的关锁阈值配置
    if (lockInfo != null && currentKeyType == ElectronicKeyType.KY53E) {
        if (hasPendingConfigCloseThreshold()) {
            sendPendingKy53EConfigCloseThreshold(lockInfo);  // 阈值配置优先
        } else if (pendingUnlockPassword != null) {
            sendPendingKy53EUnlock(lockInfo);                // 开关锁
        }
    }
    break;
```

### 2.4 sendPendingKy53EUnlock — 构建并发送 0xA3

```java
private void sendPendingKy53EUnlock(LockInfo lockInfo) {
    // ① 校验 lockInfo
    if (lockInfo == null || isEmpty(lockInfo.getLockRandom()) || isEmpty(pendingUnlockPassword))
        → onUnlockListener.onError(DYNAMIC_KEY_ERROR, "A3缺少锁随机码")

    // ② 解析锁芯侧密钥（必须用 smSecret，不用电子钥匙侧密钥）
    ElectronicKeyCryptoResolver.Result cryptoResult =
        resolveLockCryptoResult(pendingUnlockSmSecret);
    // resolveLockCryptoResult 内部调用:
    //   ElectronicKeyCryptoResolver.resolveLock(heartEntity, smSecret)
    //   使用 heartEntity.getLockEncryptMode() 决定 AES128(0x01) 或 GM128(0x02)

    if (!cryptoResult.isValid())
        → onUnlockListener.onError(DYNAMIC_KEY_ERROR, ...)

    // ③ 构建 8 字节请求体: [4字节随机数][4字节密码]
    byte[] requestData = new byte[8];
    byte[] lockRandomBytes = StringUtils.toByteArray(lockInfo.getLockRandom(), "");
    byte[] passwordBytes = StringUtils.toByteArray(pendingUnlockPassword, "");
    System.arraycopy(lockRandomBytes, 0, requestData, 0, Math.min(4, lockRandomBytes.length));
    System.arraycopy(passwordBytes, 0, requestData, 4, Math.min(4, passwordBytes.length));

    // ④ 发送 0xA3
    sendCommand(protocol.getOpenLockCmd(requestData, pendingUnlockIsOpen, cryptoResult));
}
```

### 2.5 0xA3 载荷结构（CmdUtils.buildKy53EOpenLockPayload）

```
字节位   内容                    说明
─────────────────────────────────────────
[0-3]   锁随机数 (lockRandom)    来自 0xA1 响应
[4-7]   密码 (password)         上层传入的口令
[8]     动作码 (action)
         0x03 = 开锁
         0x0C = 关锁
         0x11 = 关锁阈值配置
[9-10]  阈值 (thresholdMv)       Big-endian short
         开锁/关锁时 = 0x0000
         阈值配置时 = 目标电压值
[11-15] 保留                    全 0x00
─────────────────────────────────────────
共 16 字节，用锁芯侧密钥加密后填入 0xA3 帧的 payload
```

### 2.6 0xA3 响应解析

```java
// dispatchMakeIdResponse 中 cmd == 0xA3/case 0xA5 分支：
case 0xA3:
case 0xA5:
    // ① 选择解密密钥
    boolean useElectronicKeyCrypto =
        shouldUseElectronicKeyCryptoForUnlockResponse(cmd, currentKeyType);
    // 规则：cmd==0xA5 或 keyType==KY53N → 用电子钥匙侧
    //       cmd==0xA3 且 keyType==KY53E → 用锁芯侧

    ElectronicKeyCryptoResolver.Result cryptoResult =
        useElectronicKeyCrypto
            ? resolveElectronicKeyCryptoResult(responseSmSecret)
            : resolveLockCryptoResult(responseSmSecret);

    // ② 解析状态
    int openLockStatus = protocol.dealOpenLockStatus(dataBuffer, cryptoResult);
    // 解密后取 byte[0]：0x00=成功, 0xFF=设备不支持, 其他=失败

    // ③ 判断操作类型
    boolean isOpen = useElectronicKeyCrypto
        ? pendingUnlockIsOpen                           // KY53N: 用待处理状态判断
        : protocol.dealLockCmd(dataBuffer, cryptoResult); // KY53E: 解密后 byte[7]==0x03

    // ④ 回调
    clearPendingUnlockState();
    if (openLockStatus == 0xff) → onUnlockListener.onError(UNSUPPORTED_DEVICE)
    else → onUnlockListener.onUnlock(openLockStatus == 0x00, isOpen)
```

---

## 三、KY53N 开关锁（一步式）

### 3.1 整体时序

```
App                        电子钥匙                   锁芯
 │                            │                        │
 │  1. 前置校验                │                        │
 │     - 已连接?               │                        │
 │     - 密码长度 ≥ 1字节       │                        │
 │     - 电子钥匙侧密钥有效     │                        │
 │                            │                        │
 │  2. 构建开锁载荷 (16字节)     │                        │
 │     [0]     动作: 0x00=开   │                        │
 │                   0xFF=关   │                        │
 │     [1-15]  密码(最多15字节) │                        │
 │     ↓ 电子钥匙侧密钥加密     │                        │
 │                            │                        │
 │── 0xA5 开锁 ──────────────→│                        │
 │     (加密 0x73, 21字节)     │── 验证 ──────────────→│
 │                            │←── 结果 ──────────────│
 │←── 响应 ──────────────────│                        │
 │                            │                        │
 │  3. 解析响应                │                        │
 │     电子钥匙侧密钥解密       │                        │
 │     byte[0]: 0x00=成功      │                        │
 │               0xFF=不支持    │                        │
 │     byte[1]: 0x00=开锁      │                        │
 │               0xFF=关锁      │                        │
 │                            │                        │
 │  4. 回调 onUnlock(success, isOpen)                  │
```

### 3.2 入口代码逻辑

```java
// MkdElectronicKeyManager.unlock() 中 KY53N 分支：
// (前置校验通过后，非 KY53E 即走此分支)

// ① 解析电子钥匙侧密钥（不使用 unlock 参数中的 explicitSmSecret）
ElectronicKeyCryptoResolver.Result cryptoResult =
    resolveKy53NOpenCloseCryptoResult();
// 回退链：configuredKey → electronicKeySmSecret → smSecret

if (!cryptoResult.isValid())
    → onUnlockListener.onError(DYNAMIC_KEY_ERROR)

// ② 保存待处理状态
pendingUnlockIsOpen = isOpen;
pendingUnlockSmSecret = sanitizeSmSecret(explicitSmSecret);

// ③ 直接发送 0xA5（一步到位，不需要先读 0xA1）
sendCommand(protocol.getOpenLockCmd(passwordBytes, isOpen, cryptoResult));
```

### 3.3 0xA5 载荷结构（CmdUtils.getKy53NOpenLockCmd）

```
字节位   内容                    说明
─────────────────────────────────────────
[0]     动作标志 (M0)
         0x00 = 开锁
         0xFF = 关锁
[1-15]  密码 (M1-M15)          上层传入的口令
        不足 15 字节时后面补 0
─────────────────────────────────────────
共 16 字节，用电子钥匙侧密钥加密后填入 0xA5 帧的 payload
```

### 3.4 0xA5 响应解析

响应解析与 KY53E 共用同一个 `case 0xA3/case 0xA5` 分支（见 2.6 节）。

关键差异：`shouldUseElectronicKeyCryptoForUnlockResponse(0xA5, KY53N)` 返回 `true`，所以解密使用**电子钥匙侧密钥**，操作类型从 `pendingUnlockIsOpen` 获取而非解析响应。

---

## 四、关锁阈值配置（仅 KY53E）

### 4.1 流程

关锁阈值配置复用 KY53E 的两步式流程：`0xA1 → 0xA3(action=0x11)`。

```
configCloseThreshold(password, thresholdMv, smSecret)
  │
  ├─ 前置校验:
  │   - 设备必须是 KY53E（KY53N 不支持）
  │   - 已连接、锁芯已连接
  │   - 密码有效、阈值范围 0-65535mV
  │
  ├─ 保存待处理状态:
  │   pendingConfigCloseThresholdPassword = password
  │   pendingConfigCloseThresholdMv = thresholdMv
  │   pendingConfigCloseThresholdSmSecret = smSecret
  │
  ├─ 发送 0xA1 (读锁 SN+随机数)
  │
  └─ 0xA1 响应 → sendPendingKy53EConfigCloseThreshold()
       │
       ├─ 构建 8 字节: [4B 随机数][4B 密码]
       ├─ 锁芯侧密钥加密
       ├─ 0xA3 载荷: action=0x11, thresholdMv 填入 bytes[9-10]
       └─ 发送 0xA3
```

### 4.2 响应处理

在 `case 0xA3/0xA5` 中通过 `hasPendingConfigCloseThreshold()` 判断是开锁回调还是阈值配置回调，分别通知不同的 Listener。

---

## 五、加密密钥选择总结

| 场景 | 密钥类型 | 解析来源 | smSecret 要求 |
|------|----------|----------|--------------|
| KY53E 开/关锁 请求 | **锁芯侧** | `resolveLock(heartEntity, smSecret)` → `LockEncryptMode` | **必须**提供 |
| KY53E 开/关锁 响应 | **锁芯侧** | 同上 | **必须**提供 |
| KY53E 阈值配置 请求 | **锁芯侧** | 同上 | **必须**提供 |
| KY53N 开/关锁 请求 | **电子钥匙侧** | `setElectronicKeyCrypto` 优先；否则 `setElectronicKeySmSecret` → `ElectronicKeyEncryptMode` | 需要提前设置钥匙侧 key |
| KY53N 开/关锁 响应 | **电子钥匙侧** | 同上 | 需要提前设置钥匙侧 key |

### 电子钥匙侧密钥回退链（resolveElectronicKeyCryptoResult）

```
configuredElectronicKeyCryptoKey (setElectronicKeyCrypto 配置)
    ↓ 为空时
electronicKeySmSecret (setElectronicKeySmSecret 配置)
    ↓ 为空时
smSecret (setSmSecret 配置的通用 SM 密钥)
```

### 锁芯侧密钥（resolveLockCryptoResult）

```
explicitSmSecret (方法参数传入，必须不为空)
    ↓ 为空时 → 直接返回 error("A3缺少锁侧smSecret")
```

**关键差异**：KY53N `A5` 不使用开关锁方法参数中的 `explicitSmSecret` 作为 key，只使用 `setElectronicKeyCrypto(...)` 或 `setElectronicKeySmSecret(...)` 管理的钥匙侧 key。锁芯侧密钥**必须有 smSecret**，没有回退。

---

## 六、两个入口的代码差异

| 方面 | MkdElectronicKeyManager | ReaderElectronicKeyAdapter |
|------|------------------------|---------------------------|
| 数据发送 | `sendCommand()` → BLE GATT write | `MkdBleHelper.writeData()` → 读写器透传 |
| 数据接收 | `onCharacteristicChanged` → 分包重组 | `onReceive(byte[])` → 0x71/0x73 帧识别 |
| 命令队列 | 自维护 `dataQueue` 串行队列 | 依赖 `MkdBleHelper` 的 QueuedBleWriter |
| 设备类型 | `ElectronicKeyTypeResolver.resolve(deviceName)` + `preferredKeyType` 覆盖 | `ReaderElectronicKeyDeviceResolver.isKy53N(deviceName)` |
| UID 生成 | `bleDevice.getAddress().replace(":", "")` 补零到 16 字节 | `MkdBleHelper.getConnectedDevice()` MAC 补零到 16 字节 |
| 回调适配 | 直接回调 MkdElectronicKeyLib 的 Listener | 适配为 `MkdLockManagerProgressListener`（onSuccess/onFailed/onChargeProgress） |
| 锁芯连接判断 | `heartEntity.getLockCylinderState() == 1` | 同，通过 `isLockCylinderConnected()` |
| 0xA1→0xA3 互斥 | `hasPendingConfigCloseThreshold()` 优先于 `pendingUnlockPassword` | 同 |

核心开关锁逻辑（前置校验 → 待处理状态 → 0xA1 → 0xA3 → 响应解析 → 回调）两个入口**完全一致**。

---

## 七、错误码

| 场景 | 错误码 | 说明 |
|------|--------|------|
| BLE 未连接 | CONNECT_FAIL (2) | 设备未连接 |
| 密码格式无效 | PASSWORD_FORMAT_ERROR (3) | KY53E: <4字节; KY53N: 空 |
| 密钥无效 | DYNAMIC_KEY_ERROR (4) | 加密协商失败 |
| 锁芯未连接 | NOT_CONNECT_LOCK (5) | 心跳中 LockCylinderState != 1 |
| 锁随机码缺失 | DYNAMIC_KEY_ERROR (4) | 0xA1 响应异常 |
| 0xA3 返回 0xFF | UNSUPPORTED_DEVICE (11) | 设备不支持该操作 |
| 0xA3 返回非 0x00 | CheckStatusFail (MkdLockResult) | 锁端验证失败 |
| 缺少锁侧 smSecret | DYNAMIC_KEY_ERROR (4) | KY53E 开锁必须提供 smSecret |

---

## 八、完整调用示例

### KY53E 开锁（直连模式）

```java
MkdElectronicKeyManager manager = MkdElectronicKeyManager.getInstance();
manager.initialize(app);
manager.setSmSecret("your-32-char-hex-sm-secret");

// 等待心跳确认锁芯已连接...
// heartEntity.getLockCylinderState() == 1

manager.setUnlockListener(new OnUnlockListener() {
    @Override
    public void onUnlock(boolean isSuccess, boolean isOpen) {
        // isOpen: true=开锁, false=关锁
    }
    @Override
    public void onError(int code, String msg) {
        // 错误处理
    }
});

// 开锁：password 长度 ≥ 4 字节
manager.unlock("123456", true);

// 关锁：
manager.unlock("123456", false);
```

### KY53E 开锁（读写器中转模式）

```java
MkdLockManagerNewer lockManager = MkdLockManagerNewer.getInstance();
lockManager.setElectronicKeySmSecret("your-32-char-hex-sm-secret");

lockManager.unlockElectronicKeyWithSecretKey(
    uid, "123456", "your-sm-secret",
    new MkdLockManagerProgressListener() {
        @Override
        public void onSuccess(Map<String, String> result) {
            // result: {"lockStatus": "1", "isOpen": "true"}
        }
        @Override
        public void onFailed(MkdLockResult result) {
            // 错误处理
        }
        @Override
        public void onChargeProgress(int progress) {
            // progress: 100 表示完成
        }
    }
);
```

### KY53N 开锁（直连模式）

```java
// KY53N 不需要 smSecret 也能工作（有回退链）
manager.setElectronicKeyCrypto(
    ElectronicKeyCryptoResolver.ENCRYPT_MODE_AES128,
    "your-16-byte-key-in-hex");

// 开锁：password 长度 ≥ 1 字节
manager.unlock("1", true);
```

### 关锁阈值配置（仅 KY53E）

```java
manager.setConfigCloseThresholdListener(new OnConfigCloseThresholdListener() {
    @Override
    public void onConfigCloseThreshold(boolean success, int thresholdMv) { }
    @Override
    public void onError(int code, String msg) { }
});

// 设置关锁阈值为 1500mV
manager.configCloseThreshold("123456", 1500, "your-sm-secret");
```
