> SDK接口资料快照，非本Demo已完成全部功能的说明。运行/交付状态以工程根README为准。

# MkdElectronicKeyLib 蓝牙通讯协议文档

> 基于当前 `MkdElectronicKeyLib` 代码实现整理  
> 整理日期：2026-08-27
> 适用型号：`KY53E`、`KY53N`

---

## 1. 概述

`MkdElectronicKeyLib` 是电子钥匙 Android SDK，通过 BLE 与电子钥匙通信，提供以下能力：

- 电子钥匙心跳接收
- 电子钥匙内部信息读取
- 缓存日志读取与清理
- 时间同步
- 重启电子钥匙
- 电子钥匙经锁芯执行开锁/关锁
- 离线授权下发与管理
- 锁芯 SN / 锁状态 / 协议版本读取
- OTA 固件升级

SDK 根据蓝牙名称自动识别设备类型：

| 型号 | 识别规则 | 协议差异 |
| --- | --- | --- |
| `KY53E` | 名称包含或前缀为 `KY53E` | 锁操作命令 `0xA3`，锁状态命令 `0xA4` |
| `KY53N` | 名称包含或前缀为 `KY53N` | 锁操作命令 `0xA5`，锁状态命令 `0xA7` |

也可通过 `setPreferredKeyType(...)` 手动覆盖自动识别结果。

### 1.1 当前实现关键结论

为避免继续按旧协议理解，这里先给出当前代码的核心结论：

1. 心跳现在按**明文**解析，不再解密；心跳中的 `electronicKeyEncryptMode` / `lockEncryptMode` 只用于协商后续指令的加解密算法。
2. 电子钥匙协议存在两条密钥链路：
   - **钥匙侧链路**：用于 `0x05 / 0x07 / 0x09 / 0x0A` 等电子钥匙协议，通常使用钥匙 SN 查询到的 `smSecret`。
   - **锁侧链路**：用于 `KY53E` 的 `A3` 开关锁和关锁阈值配置，必须显式传入锁 SN 查询到的 `smSecret`。
3. `A1`、`A4`、`A6`、`A9` 现在都是**明文收发**。
4. `KY53E` 开关锁主流程现在是 `A1 -> A3`，不再依赖 `A2`。
5. `0x09` / `0x0A` 的收发加解密使用**钥匙侧** `smSecret`，但 `0x09` 业务数据区里的 `AuthNode.lockSmSecret` 以及 `0x0A` 查询响应里的 `lockSmSecret` 都表示**锁侧** `smSecret`。
6. `MkdLockLib` 通过 BLE 读写器调用电子钥匙时，仍按电子钥匙型号选择 `A3` 或 `A5`；`PL56N/FL23N` 的 NFC 状态和 Block5 安全操作属于锁侧 NFC 协议，不替换电子钥匙的 `A3/A5` 协议。
7. `PL56N/FL23N` 的锁侧通信模式来自锁状态 `Page19`，其安全开关锁使用锁侧 `smSecret`；电子钥匙 `A3/A5` 使用哪一侧的密钥和模式，仍以本章的型号规则为准。

---

## 2. BLE 通讯参数

### 2.1 GATT

| 项目 | UUID |
| --- | --- |
| Service | `0000abf0-0000-1000-8000-00805f9b34fb` |
| Write Characteristic | `0000abf1-0000-1000-8000-00805f9b34fb` |
| Notify Characteristic | `0000abf2-0000-1000-8000-00805f9b34fb` |

### 2.2 连接与写入

| 参数 | 当前实现 |
| --- | --- |
| 扫描超时 | 默认 `15000 ms` |
| 连接超时 | `15000 ms` |
| Auto Reconnect | `false` |
| Transport | `TRANSPORT_LE` |
| PHY | `PHY_LE_1M_MASK` |
| 目标 MTU | `512` |
| 有效单包大小 | `MTU - 3` |
| 写类型 | `WRITE_TYPE_NO_RESPONSE` |
| 分包延迟 | 包间 `5 ms`，请求间 `10 ms` |

### 2.3 发送模式

`MkdElectronicKeyManager#setDebug(boolean)` 控制发送策略：

- `true`：立即发送
- `false`：默认串行队列发送，上一条响应完成后才发送下一条

OTA 升级期间，普通业务指令会被拒绝发送。

---

## 3. 通用帧格式

### 3.1 帧结构

```text
+--------+----------+----------+------+--------------+------+
| Head   | Len_H    | Len_L    | Cmd  | Payload      | LRC  |
| 1 byte | 1 byte   | 1 byte   | 1 b  | N bytes      | 1 b  |
+--------+----------+----------+------+--------------+------+
| M0     | M1       | M2       | M3   | M4..M(N-1)   | M(N) |
+--------+----------+----------+------+--------------+------+
```

### 3.2 帧头

| 帧头 | 含义 |
| --- | --- |
| `0x71` | 固定 16 字节数据区的常规业务帧 |
| `0x73` | 需要锁协议加密或多块数据的业务帧 |

SDK 接收端同时接受 `0x71` 和 `0x73` 两类通知帧，并支持分包重组。

### 3.3 长度字段

- `Len_H + Len_L` 为 **大端**
- 表示整帧长度
- 即：`Head + Length(2) + Cmd + Payload + LRC`

### 3.4 校验

LRC 计算方式与 `UtilFunction.calculateLRC(...)` 一致：

```text
LRC = 0x00 - sum(all previous bytes)
```

接收端使用 `UtilFunction.checkSumData(...)` 校验整帧。

---

## 4. 加密与字节序

### 4.1 加密总体规则

当前库存在三类收发链路：

- 默认密钥链路：当前主要只剩 `0xA2` 兼容接口使用，固定 `AES-128-ECB`
- 电子钥匙侧业务链路：根据心跳里的 `electronicKeyEncryptMode` 在 `AES128` 和 `GM128` 之间切换
- 锁侧业务链路：根据心跳里的 `lockEncryptMode` 在 `AES128` 和 `GM128` 之间切换

其中：

- `A1` 读取锁 SN/随机码：明文请求，明文响应
- `A4` `KY53E` 锁状态：明文请求，明文响应
- `A7` `KY53N` 锁状态：明文请求，明文响应
- `A3` `KY53E`：按**锁侧**心跳模式加解密
- `A5` `KY53N`：按**钥匙侧**心跳模式加解密

### 4.2 默认密钥

| 项目 | 当前实现 |
| --- | --- |
| 算法 | AES |
| 密钥长度 | 128 bit（16 字节） |
| 工作模式 | ECB |
| IV | 不使用 |
| 分组长度 | 16 字节 |
| 默认填充 | 默认密钥单块接口不做自动填充 |

说明：

- `NativeLib` 的实现位于 mkdelectronickeylib.cpp（原SDK技术附录，需向供应方索取）
- 默认密钥链路底层使用 `AES-128-ECB`
- 默认密钥的单块接口要求输入长度 **必须刚好 16 字节**
- 多块默认密钥数据由 Java 层按 16 字节一块拆开，逐块调用单块接口

JNI 中默认密钥明文写死为：

```text
makeid@25*66-888
```

长度正好 16 字节，对应 AES-128 密钥。

涉及接口：

| 接口 | 方向 | 输入要求 |
| --- | --- | --- |
| `encryptWithDefaultKey(byte[] data)` | 加密 | `data.length == 16` |
| `decryptWithDefaultKey(byte[] data)` | 解密 | `data.length == 16` |

这两个接口本身：

- 不做自动补齐
- 不做 PKCS7 去填充
- 只处理单个 16 字节块

对于超过 16 字节的数据，SDK 通过 `CmdUtils.encryptDefaultKeyBlocks(...)` / `decryptDefaultKeyBlocks(...)` 逐块处理。

### 4.3 心跳协商业务密钥

当前业务加密 key 不再来自 `0xA2`。

当前实现改为：

- SDK 默认根据最近一次心跳自动缓存电子钥匙侧加密方式
- 业务层通常只需要设置对应的**钥匙侧** `smSecret`
- 如需显式覆盖，也可以通过 `setElectronicKeyCrypto(int encryptMode, String key)` 注入加解密上下文
- `key` 必须是 32 位十六进制字符串
- 解析后得到 16 字节运行 key
- 电子钥匙侧协议默认使用最近一次心跳中的 `electronicKeyEncryptMode`
- 锁侧 `A3` 不使用全局配置，必须在业务接口中显式传入**锁侧** `smSecret`
- `KY53N A5` 使用**钥匙侧** `smSecret`
- 无论当前心跳协商出来的是 `AES128` 还是 `GM128`，只要命中电子钥匙侧加解密链路，都必须先设置合法的钥匙侧 `smSecret`

模式映射：

| 心跳模式 | SDK 模式 | native 实现 |
| --- | --- | --- |
| `0x01` | `AES128` | `AES-128-ECB` |
| `0x02` | `GM128` | `SM4-ECB` |

当 `smSecret` 为空或格式非法时：

- SDK 直接返回错误
- 不再 fallback 到默认密钥
- 不再 fallback 到 `A2` 动态密钥

涉及接口：

| 接口 | 方向 | 输入要求 |
| --- | --- | --- |
| `encryptDataBytes(byte[] data, byte[] key)` | 加密 | `key.length == 16`，明文任意长度 |
| `decryptDataBytes(byte[] data, byte[] key)` | 解密 | `key.length == 16`，密文长度必须是 16 |
| `encryptDataBytesBySm4(byte[] data, byte[] key)` | 加密 | `key.length == 16`，当前电子钥匙协议按 16 字节块、无填充处理 |
| `decryptDataBytesBySm4(byte[] data, byte[] key)` | 解密 | `key.length == 16`，当前电子钥匙协议按 16 字节块、无填充处理 |

### 4.4 填充规则

#### 默认密钥接口

`encryptWithDefaultKey(...)` / `decryptWithDefaultKey(...)`：

- 只接受 16 字节
- 不负责补齐
- 不负责去填充

因此凡是使用默认密钥的协议体，Java 层都会先保证长度正好是：

- 16 字节，或
- 16 的整数倍

#### 锁协议接口

`encryptDataBytes(...)` 使用 **PKCS7 填充**，`encryptDataBytesBySm4(...)` 当前电子钥匙协议按 **16 字节块无填充** 处理：

```text
paddingValue = paddedLen - plainLen
```

例如：

- 明文 4 字节，会补 12 个 `0x0C`
- 明文 15 字节，会补 1 个 `0x01`
- 明文 16 字节，会补满 16 个 `0x10`

注意：

- 当前库里的开锁/关锁请求体本身已经固定为 16 字节，因此实际线上几乎不会触发“扩成 32 字节”的情况
- `decryptDataBytes(...)` 当前只支持解密 **单个 16 字节块**
- `encryptDataBytesBySm4(...)` / `decryptDataBytesBySm4(...)` 当前用于电子钥匙协议时，按 **单个 16 字节块无填充** 处理
- 当前 `A3`/`A5` 响应体长度固定为 16 字节，SDK 直接按单块处理

### 4.5 Java 字符串 AES 接口

`NativeLib` 还提供了两组字符串接口：

| 接口 | 说明 |
| --- | --- |
| `encryptData(String plaintext, String key)` | AES-128-ECB，加密后返回字节数组 |
| `decryptData(byte[] ciphertext, String key)` | AES-128-ECB，解密后返回字符串 |

特点：

- 使用 OpenSSL `EVP_aes_128_ecb()`
- 启用 OpenSSL 默认 padding
- 密钥取传入字符串的前 16 字节

这组接口当前 **不参与电子钥匙主协议收发**，属于通用 native 辅助接口。

### 4.6 协议中的 AES 使用分布

#### 使用默认密钥加密请求

当前主业务协议中，默认密钥链路主要只用于：

- `0xA2` 交换密钥兼容接口

补充：

- `0x02` 查询电子钥匙内部信息 **已改为明文请求**
- `0xA1` 读取锁序列号 **已改为明文请求**
- `0xA4` `KY53E` 读取锁状态 **已改为明文请求**
- `0xA7` `KY53N` 读取锁状态 **已改为明文请求**
- `0xA9` 查询协议版本 **已改为明文请求**

#### 使用电子钥匙侧协议密钥多块加密请求

- `0x05` 读取缓存日志
- `0x07` 时间同步
- `0x09` 离线授权
- `0x0A` 管理离线授权
- `0x10` 进入 OTA 模式
- `0x11` OTA 数据包

即：Java 层先把明文切成多个 16 字节块，再根据心跳协商的电子钥匙加密模式逐块加密：

- `AES128` -> AES
- `GM128` -> SM4

加密 key 为电子钥匙侧 `smSecret`。

#### 使用锁侧协议密钥加密请求

- `0xA3` `KY53E` 开锁/关锁

#### 使用电子钥匙侧协议密钥单块加密请求

- `0x06` 重启电子钥匙
- `0x08` 清除缓存日志
- `0xA5` `KY53N` 开锁/关锁

#### 使用电子钥匙侧协议密钥解密响应

当前以下业务响应走电子钥匙侧协议密钥解密：

- `0x05` 读取缓存日志响应
- `0x06` 重启电子钥匙响应
- `0x07` 同步时间响应
- `0x09` 离线授权响应
- `0x0A` 管理离线授权响应
- `0x08` 清除缓存日志响应
- `0x10` 进入 OTA 模式响应
- `0x11` OTA 数据包响应
- `0xA5` 开关锁响应

实际算法取决于心跳上报模式：

- `AES128` -> AES
- `GM128` -> SM4

补充：

- `0xA1` 读取锁序列号 **已改为明文响应**
- `0xA3` 开关锁响应 **按锁侧心跳模式解密**
- `0xA5` 开关锁响应 **按钥匙侧心跳模式解密**
- `0xA4` `KY53E` 锁状态响应 **已改为明文响应**，不再走默认密钥解密
- `0xA7` `KY53N` 锁状态响应 **已改为明文响应**，不再走默认密钥解密
- `0xA9` 查询协议版本响应 **已改为明文响应**，不再走默认密钥解密

### 4.7 实现注意事项

1. ECB 模式不带 IV，同块明文会得到同块密文，安全性弱于 CBC/GCM，但当前协议就是这样实现的。
2. 默认密钥是硬编码在 native 层的明文字符串，若协议升级，Android SDK 和设备固件必须同步替换。
3. 默认密钥单块接口非常严格，传入非 16 字节会直接失败返回 `null`。
4. AES 链路的 `decryptDataBytes(...)` 解密能力并不对称：
   - `encryptDataBytes(...)` 支持任意长度明文并自动 PKCS7 填充
   - `decryptDataBytes(...)` 只支持 16 字节密文
5. GM 链路当前使用 `SM4-ECB` 单块无填充，请求和响应都直接按 16 字节处理。

### 4.8 常见字节序

| 字段 | 字节序 |
| --- | --- |
| 帧长度 | 大端 |
| `syncTime` 请求时间戳 | 大端 |
| 心跳请求时间戳 | 小端 |
| OTA 包序号 / 总包数 | 小端 |
| OTA 单包长度 | 小端 |
| 离线授权 `startDatetime` / `endDatetime` | 小端 |
| 离线授权 `nid` | 小端 |
| 离线授权 `count` | 小端 |
| 管理离线授权请求 `nid` | 大端 |
| 管理离线授权响应 `currentIndex` / `totalCount` | 大端 |
| `KY53E` 锁状态霍尔值 | 小端 |
| `KY53N` 锁状态 `nfcVolt` | 小端 |

---

## 5. SDK 层业务约束

### 5.1 心跳

- 心跳由设备主动上报
- `sendHeart(String id)` 已仅保留兼容，不再真正发包

### 5.2 锁相关前置条件

| 业务 | 前置条件 |
| --- | --- |
| 读取锁 SN | 已连接电子钥匙，且最近心跳显示锁芯已连接 |
| 开锁 / 关锁 | 已连接电子钥匙，最近心跳显示锁芯已连接，已设置合法 `smSecret`，密码格式合法 |
| 读取锁状态 | 仅校验电子钥匙蓝牙连接，建议锁芯已接入 |

### 5.3 查询全部离线授权

查询全部离线授权不是一次返回完整列表，而是：

1. 多次返回 `0x0A` 响应
2. 每次带一条 `AuthNode`
3. SDK 内部累计
4. 收到结束标记后，通过 `onManageOfflineAuthFinish(List<AuthNode>)` 一次性交付最终列表

### 5.4 OTA

OTA 流程：

1. 发送 `0x10` 进入 OTA 模式
2. 按当前 MTU 分包构建多个 `0x11`
3. 每包必须等待成功响应后再发下一包
4. 超时 `10s` 或响应校验失败视为升级失败

OTA 单包最大固件负载：

```text
maxPayloadSize = Config.MAX_PACKET_SIZE - 15
```

---

## 6. 指令总览

| Cmd | 功能 | 请求帧头 | 主要模型 |
| --- | --- | --- | --- |
| `0x01` | 心跳 | 设备主动上报 | `KY53E` / `KY53N` |
| `0x02` | 查询电子钥匙内部信息 | `0x71` | `KY53E` / `KY53N` |
| `0x05` | 读取缓存日志 | `0x73` | `KY53E` / `KY53N` |
| `0x06` | 重启电子钥匙 | `0x71` | `KY53E` / `KY53N` |
| `0x07` | 同步时间 | `0x73` | `KY53E` / `KY53N` |
| `0x08` | 清除缓存日志 | `0x71` | `KY53E` / `KY53N` |
| `0x09` | 发送离线授权 | `0x73` | `KY53E` / `KY53N` |
| `0x0A` | 管理离线授权 | `0x73` | `KY53E` / `KY53N` |
| `0x0B` | 同步电子钥匙音效/LED 状态 | `0x73` | `KY53E` / `KY53N` |
| `0x10` | 进入 OTA 模式 | `0x73` | `KY53E` / `KY53N` |
| `0x11` | OTA 数据包 | `0x73` | `KY53E` / `KY53N` |
| `0xA1` | 读取锁序列号和随机数 | `0x71` | `KY53E` / `KY53N` |
| `0xA2` | 交换密钥兼容接口 | `0x71` | 兼容保留 |
| `0xA3` | `KY53E` 开锁/关锁 | `0x73` | `KY53E` |
| `0xA4` | `KY53E` 查询锁状态 | `0x71` | `KY53E` |
| `0xA5` | `KY53N` 开锁/关锁 | `0x73` | `KY53N` |
| `0xA6` | 查询锁芯版本信息 | `0x71` | `KY53E` / `KY53N` |
| `0xA7` | `KY53N` 查询锁状态 | `0x71` | `KY53N` |
| `0xA9` | 查询锁协议版本 | `0x71` | `KY53E` / `KY53N` |

---

## 7. 各指令详细协议

## 7.1 心跳（`0x01`）

### 请求

虽然 SDK 保留了 `getHeartbeatCmd(String id)`，但当前业务上不主动发送。

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x01
Data  = Crypto_By_ElectronicKey_Heartbeat_Mode( uid[12] + timestamp[4] )
LRC   = 1 byte
```

- `uid[12]`：UTF-8，不足补 `0x00`
- `timestamp[4]`：当前秒级时间戳，小端

### 响应

当前心跳响应体按 32 字节明文解析，旧短包仍兼容：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `electronicKeyBattery` | 钥匙电量 |
| `1` | 1 | `electronicKeyState` | `0` 正常，`1` 充电 |
| `2` | 1 | `lockCylinderState` | `0` 未连接锁芯，`1` 已连接 |
| `3` | 1 | `lockState` | `0` 无状态，`1` 已开锁，`2` 已关锁 |
| `4` | 12 | `lockSN` | 锁芯 SN，UTF-8 |
| `16` | 9 | `lockMac` | 9 字节字段，结构为长度前缀 + MAC 数据，按有效长度转大写十六进制字符串 |
| `25` | 4 | `electronicKeyTimeSec` | 电子钥匙内部时间，大端 |
| `29` | 1 | `electronicKeyEncryptMode` | 电子钥匙加密模式：`0x01` AES128，`0x02` GM128 |
| `30` | 1 | `lockEncryptMode` | 锁具加密模式：`0x01` AES128，`0x02` GM128 |
| `31` | 1 | `reserve` | 预留字节 |

对应回调：`OnHeartBeatListener.onHeartBeat(HeartEntity)`

兼容说明：

- 当明文长度不足 29 字节时，只解析基础字段与已存在的 `SN / MAC`。
- 当明文长度不足 30/31/32 字节时，新字段 `electronicKeyEncryptMode`、`lockEncryptMode`、`reserve` 保持默认值 `0`。

---

## 7.2 查询电子钥匙内部信息（`0x02`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0x02
Data  = uid[16]
LRC
```

### 响应

响应体不是二进制结构，而是 UTF-8 JSON 字符串。SDK 当前解析字段：

| JSON 字段 | 对应实体字段 |
| --- | --- |
| `dname` | 设备名称 |
| `dtype` | 设备类型 |
| `dhfversion` | 硬件版本 |
| `timezoo` | 时区 |
| `freememory` | 剩余内存 |
| `logesize` | 日志数量 |
| `authsize` | 授权数量 |

对应回调：`OnReadElectKeyInfoListener.onReadElectKeyInfo(ElectronicKeyInfo)`

---

## 7.3 读取缓存日志（`0x05`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x05
Data  = Encrypt_By_Heartbeat_Mode( uid[16] )
LRC
```

- `Encrypt_By_Heartbeat_Mode`：
  - 心跳模式为 `AES128` 时，使用 `smSecret` 做 AES-128-ECB
  - 心跳模式为 `GM128` 时，使用 `smSecret` 做 GM128/SM4-ECB

### 响应

单包日志响应协议按当前 SDK 解析为：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `flag` | 当前必须为 `0x00` |
| `1` | 64 | `encryptedPayload` | 按心跳模式加密的 64 字节数据 |

解密后的 `encryptedPayload`：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 4 | `packetIndex` | 大端 |
| `4` | 60 | `logNode` | 日志节点有效区 |

日志节点 `LogNode` 结构：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 16 | `uid` | UTF-8 固定长 |
| `16` | 16 | `kid` | UTF-8 固定长 |
| `32` | 16 | `lid` | UTF-8 固定长 |
| `48` | 4 | `timestamp` | 小端 |
| `52` | 1 | `action` | `LogAction` |
| `53` | 3 | `reserve` | 保留 |
| `56` | 4 | `nid` | 大端 |

说明：

- SDK 内部通过 `CmdUtils.cacheLogs` 累计日志
- `encryptedPayload[64]` 按 4 个 16 字节分块，使用当前心跳协商模式和 `smSecret` 逐块解密
- 读取过程中通过 `onReadCacheLogProgress(int length)` 回调当前累计条数
- 收到结束包后，通过 `onReadCacheLog(List<LogNode>)` 与 `onReadCacheLogFinish()` 收尾

---

## 7.4 重启电子钥匙（`0x06`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x06
Data  = Crypto_By_ElectronicKey_Heartbeat_Mode( uid[16] )
LRC
```

### 响应

按电子钥匙侧心跳模式解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功，其它失败 |

对应回调：`OnRebootKeyListener.onRebootKey(boolean)`

---

## 7.5 同步时间（`0x07`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x07
Data  = Encrypt_By_Heartbeat_Mode( timestamp[4] + padding[12] )
LRC
```

- `timestamp[4]`：大端秒级 Unix 时间戳
- `Encrypt_By_Heartbeat_Mode`：
  - 当心跳中电子钥匙加密模式为 `AES128` 时，使用当前已设置业务密钥按 AES 加密；
  - 当心跳中电子钥匙加密模式为 `GM128` 时，使用当前已设置业务密钥按 GM128/SM4 加密。
- `0x07` 与 `0xA3`、`0xA5` 一样，发送前必须先根据最新心跳或显式配置完成加解密上下文设置。

### 响应

按心跳协商的当前加密模式解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功 |
| `1` | 4 | `timeSec` | 大端 |

- 当 `status != 0x00` 时视为同步失败。

对应回调：`OnSyncTimeListener.onSyncTime(boolean isSuccess, long timestamp)`

---

## 7.5.1 同步音效（`0x0B`）

`0x0B` 的指令字保持明文，请求的 16 字节业务体必须使用钥匙侧心跳协商的 AES128/GM128 模式及钥匙侧 `smSecret` 加密。

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x0B
Data  = Crypto_By_ElectronicKey_Heartbeat_Mode(M0 + 15 bytes 0x00)
LRC   = 1 byte
```

| `M0` | 音效 |
| --- | --- |
| `0x01` | 提示音 |
| `0x02` | 警告音 |
| `0x03` | 报警音 |
| `0x04` | 开锁音 |
| `0x05` | 关锁音 |
| `0x06` | 开/关失败音 |
| `0x07` | 低电量音 |
| `0x08` | 运行灯 |
| `0x09` | 警告灯 |
| `0x0A` | 错误灯 |
| `0x0B` | 低电量灯 |
| `0x0C` | 充电灯 |
| `0x0D` | 满电灯 |
| `0x0E` | 正常灯 |
| `0x0F` | 提示灯 |
| `0x10` | 忙碌灯 |
| `0x11` | 蓝牙已连接 |
| `0x12` | 蓝牙已断开 |
| `0x13` | 开锁成功音 |
| `0x14` | 关锁成功音 |
| `0x15` | 关锁失败音 |
| `0x16` | 操作超时音 |

### 响应与回调

设备不会返回 `0x0B` 协议响应。SDK 将数据提交到 BLE 写请求后即调用
`OnSyncElectronicKeyToneListener.onSyncElectronicKeyTone(true, toneType)`，该回调仅表示
“命令已下发”，不表示设备已播放音效或切换 LED 成功。

---

## 7.6 清除缓存日志（`0x08`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x08
Data  = Crypto_By_ElectronicKey_Heartbeat_Mode( uid[16] )
LRC
```

### 响应

按电子钥匙侧心跳模式解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功 |

对应回调：`OnClearCacheLogListener.onClearCacheLog(boolean)`

---

## 7.7 交换密钥兼容接口（`0xA2`）

当前 `exchangeKey(...)` 外部接口仍保留兼容，但锁业务主流程已不再依赖 `0xA2`。

当前实现：

- `MkdElectronicKeyManager.exchangeKey(...)`
- `MkdLockManagerNewer.exchangeElectronicKey(...)`

都会优先返回基于当前 `smSecret` 解析得到的 16 字节运行 key。

也就是说：

- 业务层不再需要先发 `A2`
- 运行 key 的真实来源是 `smSecret`
- `A2` 不再作为开关锁和阈值配置的前置步骤

---

## 7.8 `KY53E` 开锁 / 关锁（`0xA3`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0xA3
Data  = AES_Dynamic( payload[16] )
LRC
```

`payload[16]` 当前实现：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0..3` | 4 | `lockRandom` | 来自 `0xA1` 回包的锁随机码 |
| `4..7` | 4 | `password` | 锁密码前 4 字节 |
| `8` | 1 | `action` | `0x03` 开锁，`0x0C` 关锁，`0x11` 霍尔阈值配置 |
| `9..10` | 2 | `closeThresholdMv` | 关锁阈值，`uint16`，大端，普通开关锁时填 `0` |
| `11..15` | 5 | 保留 | `0x00` |

说明：

- SDK 内部会先读一次 `0xA1`，取到随机码后再发送 `0xA3`
- `A3` 请求加密方式由心跳模式决定：
  - `AES128` -> `encryptDataBytes(payload, keyBytes)`
  - `GM128` -> `encryptDataBytesBySm4(payload, keyBytes)`
- `keyBytes` 来自本次 `A3` 接口显式传入的锁侧 `smSecret`
- 若未显式传入锁侧 `smSecret`，SDK 直接返回失败，不回退任何锁侧全局缓存

### 响应

SDK 当前按心跳模式解密响应，并解析：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功，`0xFF` 不支持设备，其它失败 |
| `1..6` | 6 | 保留 | 当前为 `0x00` |
| `7` | 1 | `action` | 动作回显：`0x03` 开锁，`0x0C` 关锁，`0x11` 阈值配置 |
| `8..15` | 8 | 保留 | 当前为 `0x00` |

对应回调：

- 开锁/关锁：`OnUnlockListener.onUnlock(boolean isSuccess, boolean isOpen)`
- 关锁阈值配置：`OnConfigCloseThresholdListener.onConfigCloseThreshold(boolean isSuccess, int thresholdMv)`

---

## 7.9 `KY53N` 开锁 / 关锁（`0xA5`）

### 请求

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0xA5
Data  = Crypto_By_Heartbeat_Mode( payload[16] )
LRC
```

`payload[16]`：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `action` | `0x00` 开锁，`0xFF` 关锁 |
| `1..15` | 15 | `password` | 锁密码，最多 15 字节 |

### 响应

SDK 当前按心跳模式解密响应，并解析：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功，`0x01` 失败，`0xFF` 不支持 |
| `1` | 1 | `action` | `0x00` 开锁，`0xFF` 关锁 |

说明：

- 当前 `A5` 使用**钥匙侧** `smSecret`
- 算法取最近一次心跳里的 `electronicKeyEncryptMode`
- 即使当前心跳模式是 `AES128`，`A5` 也仍然使用钥匙侧 `smSecret`，不是只在 `GM128` 下才需要
- 若当前没有有效的钥匙侧 `smSecret` / 模式，SDK 会直接失败，不再走明文兜底
- 当前 `dispatchMakeIdResponse(...)` 对 `0xA5` 的动作类型，优先使用本次发送时缓存的 `pendingUnlockIsOpen`
- 因此上层结果以 SDK 回调值为准

---

## 7.10 读取锁序列号与随机数（`0xA1`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0xA1
Data  = uid[16]
LRC
```

### 响应

响应体为 16 字节明文：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0..11` | 12 | `serialNo` | 锁芯 SN，UTF-8 |
| `12..15` | 4 | `lockRandom` | 随机数，HEX 字符串输出 |

对应实体：`LockInfo`

---

## 7.11 `KY53E` 读取锁状态（`0xA4`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0xA4
Data  = uid[16]
LRC
```

### 响应

当前响应体为 **24 字节明文**，SDK 直接按以下结构解析：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `cmdRes` | 指令结果 |
| `1` | 1 | `lockStaDatSet` | 锁状态数据集，`26A4/26D1`：`0` 关锁，`1` 开锁 |
| `2` | 1 | `tempNow` | 温度，有符号 `int8_t` |
| `3` | 1 | `writeSnSupported` | 是否能写号，`0` 否，`1` 是 |
| `4` | 1 | `unlockCompleteFlag` | 开锁完好标志，`0` 异常，`1` 正常 |
| `5` | 1 | `commKeyReadyFlag` | 通信密钥完好标志，`0` 异常，`1` 正常 |
| `6` | 1 | `a3VerifyPassedFlag` | 本次通信 `A3` 校验通过标志，`0` 否，`1` 是 |
| `7` | 1 | `sensorConfig` | 传感器配置（预留） |
| `8..9` | 2 | `systemVoltageMv` | 系统电压值，单位 `mV`，小端 |
| `10..11` | 2 | `hall1ThresholdMv` | 霍尔1相差阈值，单位 `mV`，小端 |
| `12..13` | 2 | `hall1VoltageMv` | 霍尔1电压值，单位 `mV`，小端 |
| `14..15` | 2 | `hall2ThresholdMv` | 霍尔2相差阈值，单位 `mV`，小端 |
| `16..17` | 2 | `hall2VoltageMv` | 霍尔2电压值，单位 `mV`，小端 |
| `18..23` | 6 | `res` | 预留 |

SDK 兼容说明：

- 为了兼容旧调用方，`LockStateEntity` 仍会回填部分历史字段
- `volHall1 <- hall1VoltageMv`
- `volHall2 <- hall2VoltageMv`
- `dyKeyOkFlg <- writeSnSupported`
- `pwdVerifyOkFlg <- unlockCompleteFlag`
- `proDataGet <- commKeyReadyFlag`
- `proDataRdy <- a3VerifyPassedFlag`
- `pwdOkFlg <- sensorConfig`

---

## 7.12 `KY53N` 读取锁状态（`0xA7`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0xA7
Data  = uid[16]
LRC
```

### 响应

当前响应体为明文，SDK 直接按以下结构解析：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0..1` | 2 | `nfcVolt` | 小端 |
| `2` | 1 | `nfcStatus` | NFC 状态 |
| `3` | 1 | `tempNow` | 温度 |
| `4..end` | N | `res` | 保留 |

兼容填充：

- `LockStateEntity.volHall1 = nfcVolt`
- `LockStateEntity.cmdRes = 0`
- 其余 `KY53E` 专属字段回填为 `0`

---

## 7.13 查询锁协议版本（`0xA9`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0xA9
Data  = 16 bytes 0x00
LRC
```

说明：

- `M0..M15` 置空
- 请求不加密

### 响应

当前响应体按 **明文** 直接解析：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `cmdRes` | 指令结果，`0x00` 成功，`0x01` 失败，`0xFF` 当前条件下不支持 |
| `1` | 1 | `type` | 协议类型 |
| `2` | 1 | `keyLength` | 密钥长度 |
| `3` | 1 | `mainVersion` | 主版本号 |
| `4` | 1 | `subVersion` | 次版本号 |
| `5..end` | N | `res` | 预留 |

对应实体：`LockProtocolVersionInfo`

---

## 7.14 查询锁芯版本信息（`0xA6`）

### 请求

```text
Head  = 0x71
Len   = 0x0015
Cmd   = 0xA6
Data  = 16 bytes 0x00
LRC
```

请求明文，不使用钥匙侧或锁侧 `smSecret`。

### 响应

响应命令固定 `0xA6`，业务体 `M0..M47` 共 48 字节，按明文解析：

| 偏移 | 协议字段 | 有效长度 | 说明 |
| --- | --- | --- | --- |
| `0..15` | `M0..M15` | 8 byte | 生产日期；按第一个 `0x00` 截断。 |
| `16..31` | `M16..M31` | 11 byte | 固件版本；按第一个 `0x00` 截断。 |
| `32..47` | `M32..M47` | 4 byte | 硬件版本；按第一个 `0x00` 截断。 |

对应实体：`LockFirmwareVersionInfo`。响应业务体不足 48 字节时视为解析失败。

---

## 7.15 发送离线授权（`0x09`）

### 请求

```text
Head  = 0x73
Len   = payloadLen + 5
Cmd   = 0x09
Data  = Encrypt_By_Heartbeat_Mode_MultiBlock( authPayload[96] )
LRC
```

- `Encrypt_By_Heartbeat_Mode_MultiBlock`：
  - 将 `authPayload[96]` 按 16 字节分块
  - 每块都按当前心跳模式使用 `smSecret` 加密

当前 SDK 实际线上的授权结构长度为 **96 字节**，不是旧注释中的 `kid[32] / lid[32]`。

说明：

- `0x09` 的收发加解密，使用**电子钥匙侧** `smSecret`
- `authPayload[80..95]` 的 `lockSmSecret`，是写入业务数据区的**锁侧** `smSecret`
- 这两个概念不要混用

#### `authPayload[96]`

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0..15` | 16 | `uid` | UTF-8 固定长 |
| `16..31` | 16 | `kid` | UTF-8 固定长 |
| `32..47` | 16 | `lid` | UTF-8 固定长 |
| `48..63` | 16 | `password` | HEX 转字节，固定 16 字节 |
| `64..79` | 16 | `ruleNode` | 见下表 |
| `80..95` | 16 | `lockSmSecret` | 锁侧 `smSecret`，HEX 转字节，固定 16 字节 |

#### `ruleNode[16]`

| 偏移 | 长度 | 字段 | 字节序 |
| --- | --- | --- | --- |
| `0..3` | 4 | `startDatetime` | 小端 |
| `4..7` | 4 | `endDatetime` | 小端 |
| `8..11` | 4 | `nid` | 小端 |
| `12..13` | 2 | `count` | 小端 |
| `14` | 1 | `enable` | - |
| `15` | 1 | `authMode` | - |

### 响应

按心跳协商的当前加密模式解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功，否则失败 |

对应回调：`OnSendOfflineAuthListener.onSendResult(boolean)`

---

## 7.16 管理离线授权（`0x0A`）

### 请求

统一 21 字节：

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x0A
Data  = Encrypt_By_Heartbeat_Mode( managePayload[16] )
LRC
```

说明：

- `0x0A` 的收发加解密，使用**电子钥匙侧** `smSecret`
- 查询响应里授权节点 `M96-M111` 的 `lockSmSecret`，是返回业务数据里的**锁侧** `smSecret`

#### `managePayload[16]`

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `operationType` | `0x01` 查单个，`0x02` 查全部，`0x03` 删单个，`0x04` 删全部 |
| `1..4` | 4 | `nid` | 仅单条查询/删除时有效，大端 |
| `5..15` | 11 | 保留 | `0x00` |

### 响应

响应体按心跳协商模式多块解密，key 为电子钥匙侧 `smSecret`。

#### 响应头（前 16 字节）

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功，`0x01` 失败 |
| `1` | 1 | `operationType` | 同请求 |
| `2..3` | 2 | `currentIndex` | 大端 |
| `4..5` | 2 | `totalCount` | 大端 |
| `6..15` | 10 | 保留 | - |

#### 查询返回附带 `AuthNode`

当满足以下条件时，SDK 继续解析授权节点：

- 操作为查询单条或查询全部
- `success == true`
- 非“查询全部结束包”
- 响应总长度至少 `112` 字节

授权节点结构：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `16..31` | 16 | `uid` | UTF-8 |
| `32..47` | 16 | `kid` | UTF-8 |
| `48..63` | 16 | `lid` | UTF-8 |
| `64..79` | 16 | `password` | HEX |
| `80..83` | 4 | `startDatetime` | 小端 |
| `84..87` | 4 | `endDatetime` | 小端 |
| `88..91` | 4 | `nid` | 小端 |
| `92..93` | 2 | `count` | 小端 |
| `94` | 1 | `enable` | - |
| `95` | 1 | `authMode` | - |
| `96..111` | 16 | `lockSmSecret` | 锁侧 `smSecret`，HEX |

#### 查询全部结束判定

当前 SDK 约定：

- `status == 0x01`
- `operationType == 0x02`

此时不认为是错误，而是认为“查询全部结束”。

---

## 7.17 OTA 升级

### 7.17.1 进入 OTA 模式（`0x10`）

```text
Head  = 0x73
Len   = 0x0015
Cmd   = 0x10
Data  = Crypto_By_ElectronicKey_Heartbeat_Mode( otaInfo[16] )
LRC
```

`otaInfo[16]`：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0..3` | 4 | `softwareVersion` | UTF-8，最多 4 字节 |
| `4..7` | 4 | `hardwareVersion` | UTF-8，最多 4 字节 |
| `8..15` | 8 | 保留 | `0x00` |

响应解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功 |

### 7.17.2 OTA 数据包（`0x11`）

```text
Head  = 0x73
Len   = packetDataLen + 15
Cmd   = 0x11
Data  = packetIndex[4] + totalPacketCount[4] + packetSize[2] + packetData[N]
LRC
```

字段定义：

| 偏移 | 长度 | 字段 | 字节序 |
| --- | --- | --- | --- |
| `0..3` | 4 | `packetIndex` | 小端，从 `1` 开始 |
| `4..7` | 4 | `totalPacketCount` | 小端 |
| `8..9` | 2 | `packetSize` | 小端 |
| `10..` | N | `packetData` | 固件分片 |

响应解密后：

| 偏移 | 长度 | 字段 | 说明 |
| --- | --- | --- | --- |
| `0` | 1 | `status` | `0x00` 成功 |
| `1..4` | 4 | `packetIndex` | 小端，应与请求一致 |

SDK 会校验返回包序号是否与当前待确认包一致。

---

## 8. 典型业务流程

## 8.1 监听电子钥匙心跳

1. 连接电子钥匙
2. 开启 Notify
3. 设备主动上报 `0x01`
4. SDK 回调 `OnHeartBeatListener.onHeartBeat(...)`

## 8.2 标准开锁流程

1. 通过心跳确认 `lockCylinderState == 1`
2. 根据电子钥匙型号选择开锁协议：`KY53E` 使用 `0xA3`，`KY53N` 使用 `0xA5`
3. `KY53E` 使用心跳中的 `lockEncryptMode` 和锁侧 `smSecret`；`KY53N` 使用心跳中的 `electronicKeyEncryptMode` 和钥匙侧 `smSecret`
4. 不区分当前是 `AES128` 还是 `GM128`，对应业务链路都必须先提供合法的 16 字节 `smSecret`
5. `KY53E` SDK 内部先明文发送 `0xA1` 读取锁随机码；`KY53N` 不依赖 `A2` 获取动态密钥
6. 根据型号发送 `0xA3` 或 `0xA5`
7. 收到开锁结果回调

SDK 已封装一体化入口：

```java
unlock(uid, lockKey, true, listener)
```

### 8.2.1 `MkdLockLib` 对接边界

当 `MkdLockLib` 使用 BLE 读写器连接电子钥匙时，调用链为：

```text
MkdLockLib 对外开锁接口
 -> MkdReaderLockImpl
 -> MkdReaderHelper
 -> ReaderElectronicKeyAdapter
 -> 电子钥匙 A1/A3 或 A5
```

`MkdLockLib` 对外统一使用以下接口：

```java
MkdLockManagerNewer.getInstance().unlockWithSecretKey(
        password, lockSmSecret, listener);
MkdLockManagerNewer.getInstance().lockWithSecretKey(
        password, lockSmSecret, listener);
```

其中 `lockSmSecret` 是锁侧 `smSecret`。对于 `KY53E` 的 `A3`，该参数必须为查询锁信息得到的 32 位 HEX 字符串；对于 `KY53N` 的 `A5`，开关锁实际使用钥匙侧 `smSecret`，锁侧参数为空不会阻止 `A5` 发送，但钥匙侧 `smSecret` 必须已经通过心跳后的钥匙 SN 查询并设置到 SDK。

密钥和模式规则如下：

| 场景 | 电子钥匙指令 | 加密模式来源 | 加密 key | 说明 |
| --- | --- | --- | --- | --- |
| `KY53E` 开关锁 | `A1 -> A3` | 心跳 `lockEncryptMode` | 锁侧 `smSecret` | `A1` 明文读取锁 SN 和随机数；`A3` 请求和响应按锁侧模式处理 |
| `KY53N` 开关锁 | `A5` | 心跳 `electronicKeyEncryptMode` | 钥匙侧 `smSecret` | 不依赖 `A2`；请求和响应按钥匙侧模式处理 |
| `PL56N/FL23N` 直接 NFC/读写器 NFC | Page16~Page19、Page20~Page23 | 锁状态 `communicationEncryptionMode` | 锁侧 `smSecret` | 这是锁侧 NFC Block5 流程，不是电子钥匙 `A3/A5` |

其中 `PL56N/FL23N` 的锁侧 NFC 流程为：

1. 读取 `Page16~Page19`；电量变化的状态帧作为有效状态，并缓存随机数和 `communicationEncryptionMode`。
2. mode `0` 走明文动作、写密码、充电流程，不要求锁侧 `smSecret`。
3. mode `1` 使用 AES128，mode `2` 使用 GM128/SM4，均以锁侧 `smSecret` 加密 16 字节 Block5 数据。
4. 密文按 `Page20~Page23`（`0x14~0x17`）逐 page 写入，等待 500ms 后轮询响应，最多 25 次；当前 `MkdLockLib` 的 PL56N/FL23N 操作间隔为 `LockConfig.timeInterval`，基础信息初始化后为 150ms。
5. 锁端覆盖密文后，按相同模式和锁侧 `smSecret` 解密，只解析 `M0`；`M0=0` 后继续充电，达到 `deviceMV` 才向上层返回成功。

`EL01`、`EL02`、`LK01` 查询状态时直接读取一次；其他锁型的对外状态查询执行最多 25 次、间隔 200ms 的 MCU 启动检测。该状态查询规则不改变电子钥匙 `A3/A5` 的密钥选择。

## 8.3 查询全部离线授权

1. 发送 `0x0A`，`operationType = 0x02`
2. 多次收到查询结果
3. SDK 内部累计 `AuthNode`
4. 收到结束包后回调：
   - `onManageOfflineAuthProgress(...)`
   - `onManageOfflineAuthFinish(List<AuthNode>)`

## 8.4 OTA 升级

1. 校验当前无其它待发送指令
2. 发送 `0x10`
3. 回调 `onEnterOtaMode()`
4. 循环发送 `0x11`
5. 每包成功后回调 `onProgress(current, total)`
6. 全部完成回调 `onSuccess()`

---

## 9. 回调与错误码

### 9.1 通用错误码

来自 `MkdElectronicKeyMenu`：

| Code | 含义 |
| --- | --- |
| `2` | 钥匙连接失败 |
| `3` | 密码格式错误 |
| `4` | 交换密钥异常 |
| `5` | 未连接锁 |
| `6` | 固件包文件无效 |
| `7` | 当前 MTU 不支持固件分包 |
| `8` | 进入 OTA 模式失败 |
| `9` | 固件升级失败 |
| `10` | OTA 升级进行中 |
| `11` | 不支持设备类型 |

### 9.2 业务回调对应

| 业务 | 成功回调 | 失败回调 |
| --- | --- | --- |
| 心跳 | `OnHeartBeatListener.onHeartBeat` | `onHeartBeatFail` |
| 电子钥匙信息 | `OnReadElectKeyInfoListener.onReadElectKeyInfo` | `onReadElectKeyInfoError` |
| 日志读取 | `OnReadCacheLogListener.onReadCacheLog` | `onReadCacheLogError` |
| 重启 | `OnRebootKeyListener.onRebootKey` | `onFail` |
| 时间同步 | `OnSyncTimeListener.onSyncTime` | `onSyncTimeError` |
| 清除日志 | `OnClearCacheLogListener.onClearCacheLog` | `onClearCacheLogFail` |
| 交换密钥兼容接口 | `OnExchangeKeyListener.onExchangeKey` | `onFail` |
| 开关锁 | `OnUnlockListener.onUnlock` | `onError` |
| 发送离线授权 | `OnSendOfflineAuthListener.onSendResult` | `onFail` |
| 管理离线授权 | `OnManageOfflineAuthListener.onManageOfflineAuthResult` | `onManageOfflineAuthError` |
| 读锁 SN | `OnReadSerialNoListener.onReadLockSN` | `onReadLockSNError` |
| 读锁状态 | `OnReadLockStateListener.onReadLockState` | `onReadLockStateError` |
| 读协议版本 | `OnReadLockProtocolVersionListener.onReadLockProtocolVersion` | `onReadLockProtocolVersionError` |
| OTA | `OnOtaUpgradeListener.onSuccess` | `onFail` |

---

## 10. 型号差异汇总

| 项目 | `KY53E` | `KY53N` |
| --- | --- | --- |
| 开关锁命令 | `0xA3` | `0xA5` |
| 锁密码最小要求 | 至少 4 字节 | 至少 1 字节 |
| 开关锁请求体 | `password[4] + action@byte7` | `action@byte0 + password[15]` |
| 锁状态命令 | `0xA4` | `0xA7` |
| 锁状态响应 | 霍尔/温度/标志位 | `nfcVolt + nfcStatus + temp` |
| 协议版本命令 | `0xA9` | `0xA9` |

---

## 11. 说明

1. 本文档以 **当前 SDK 实现** 为准，不以旧注释或历史协议稿为准。
2. `AuthNode` Java 类顶部注释中仍保留了旧版字段长度说明，但当前实际发包长度是：
   - `uid[16]`
   - `kid[16]`
   - `lid[16]`
   - `password[16]`
   - `ruleNode[16]`
   - `lockSmSecret[16]`
   同时，`0x0A` 查询返回的授权节点尾部 `M96..M111` 也按 `lockSmSecret[16]` 解析。
3. `KY53N` 开关锁响应当前代码已按心跳模式解密；文档已按当前实现记录。
4. 若后续设备固件协议升级，应同步更新：
   - `CmdUtils`
   - `ElectronicKeyProtocol`
   - 本文档
