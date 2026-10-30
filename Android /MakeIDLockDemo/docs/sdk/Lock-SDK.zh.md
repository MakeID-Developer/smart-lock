> SDK接口资料快照，非本Demo已完成全部功能的说明。运行/交付状态以工程根README为准。

# MkdLockLib Android SDK 接入与接口使用文档

[简体中文](Lock-SDK.zh.md) | [English](Lock-SDK.en.md)

`MkdLockLib` 是 MakeID 智能锁统一操作库，对外入口为 `MkdLockManagerNewer`。库内按锁类型封装 NFC、BLE 读写器、手机 BLE、USB 等不同通信方式，上层业务通过切换 `MkdLockTypeEnum` 后调用统一接口完成读 SN、读状态、电量、开关锁、读版本、网络参数等操作。本文重点补充 KY53E/KY53N 电子钥匙的第三方 AAR 接入方式。

## 基本信息

- 模块名：`MkdLockLib`
- 包名：`com.makeid.lock_2`
- 当前源码版本：`1.7.19`（以实际交付 AAR 清单为准）
- 最低 Android 版本：`minSdk 21`
- 主要入口：`MkdLockManagerNewer.getInstance()`
- 常用回调：`MkdLockManagerListener`、`MkdLockManagerProgressListener`
- 依赖模块：`MkdBLEConnectLib`、`MkdElectronicKeyLib`
- 文档核对日期：`2026-10-30`
- 示例验证状态：已对照当前公开接口静态核对，未执行编译、打包或真机验证

## 相关文档

- NFC 开锁协议整理（原SDK技术附录，需向供应方索取）：当前 NFC 锁通用协议，以及 `PL56N/FL23N` 的 Page16~Page23、Block5 和阈值配置说明。
- FL23N 当前接口整理（原SDK技术附录，需向供应方索取）：Android SDK 中 `FL23N/PL56N` 状态读取、MCU 启动检测、加密模式分流和开关锁接口的当前实现。
- PL56N / FL23N 加密操作后充电流程（原SDK技术附录，需向供应方索取）：mode `1/2` 的 Block5 响应 `M0=0` 后继续充电，电量达标才回调开关锁或阈值配置成功。
- iOS FL23N / PL56N NFC 适配文档（原SDK技术附录，需向供应方索取）：iOS Core NFC 原生命令、随机数和锁侧 `smSecret` 缓存、mode `0/1/2` 开关锁，以及电子钥匙 BLE `0x0B` 音效同步。
- 电子钥匙 0x0B 同步音效协议开发文档（原SDK技术附录，需向供应方索取）：`KY53E/KY53N` 音效或 LED 状态同步的 BLE 帧、心跳加密方式和钥匙侧 `smSecret` 使用规则。
- 开关锁统一 smSecret 接口改造开发文档（原SDK技术附录，需向供应方索取）：普通锁开关锁统一三参接口、二参弃用兼容和测试工具迁移说明。

## 第三方接入指南（AAR 交付）

本文面向接收 AAR 的 Android 原生应用开发者，示例使用 **Java + Groovy Gradle**。第三方只通过 `MkdLockManagerNewer` 使用电子钥匙，无需直接初始化或操作 `MkdElectronicKeyManager`。后文保留 NFC、普通读写器、BLE 锁和 USB 锁的接口说明。

### 阅读导航

- [AAR 引入与依赖](#aar-引入与依赖)
- [Manifest 与运行时权限](#manifest-与运行时权限)
- [初始化与接入顺序](#初始化与接入顺序)
- [电子钥匙接口速查](#电子钥匙接口速查)
- [参数与密钥说明](#参数与密钥说明)
- [完整 KY53E 接入示例](#完整-ky53e-接入示例)
- [常用业务示例](#常用业务示例)
- [电子钥匙扩展接口](#电子钥匙扩展接口)
- [常见错误码](#常见错误码)
- [第三方接入排查与交付检查](#第三方接入排查与交付检查)

### AAR 引入与依赖

#### 1. 交付文件

**当前源码采用普通模块依赖，不是已经合并依赖的单 AAR。** `MkdLockLib/build.gradle` 中两个内部库使用 `implementation project(...)`，`embed` 未启用。因此，不能只复制一个 `MkdLockLib.aar` 就完成当前版本的接入。

同一批次交付以下三个 AAR，并放入宿主 App 的 `app/libs/`。下列文件名是为方便示例统一重命名后的名称；实际交付文件可能包含版本、日期等后缀，依赖路径应与实际文件一致。

```text
app/
└── libs/
    ├── MkdLockLib.aar
    ├── MkdBLEConnectLib.aar
    └── MkdElectronicKeyLib.aar
```

| 文件 | 用途 | 当前源码版本 |
| --- | --- | --- |
| `MkdLockLib.aar` | 统一管理入口、电子钥匙适配、NFC/读写器操作、鉴权 JNI | `1.7.19` |
| `MkdBLEConnectLib.aar` | BLE 扫描、连接、收发，提供 `Device` 类型 | `1.1` |
| `MkdElectronicKeyLib.aar` | 电子钥匙协议、实体、回调及加密 JNI | `1.0.2` |

> 必须使用供应方配套交付的版本，不能混用旧 AAR、旧 JAR 或重复引入同一模块。未来若交付形式变为真正的合并 AAR，应以当次交付清单为准：已内嵌的库不要再次添加。本文不宣称当前已经实现单 AAR 交付。

#### 2. Maven 仓库

在宿主项目的 `settings.gradle` 中，将以下仓库合并进已有配置（不要重复声明整个配置块）：

```groovy
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' } // XXPermissions
    }
}
```

#### 3. App 模块依赖

在 `app/build.gradle` 中加入：

```groovy
android {
    // 本示例按 SDK 当前源码的 compileSdk 34 接入；宿主可以使用兼容的更高版本。
    compileSdk 34

    defaultConfig {
        minSdk 21
        // 当前电子钥匙模块仅配置 arm64-v8a，电子钥匙示例以 64 位 ARM 真机为目标。
        ndk {
            abiFilters 'arm64-v8a'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    packagingOptions {
        jniLibs {
            // 两个业务 AAR 都携带 OpenSSL。仅在确认同一批次 SO 内容相同时去重。
            pickFirsts += ['**/libcrypto_1_1.so', '**/libssl_1_1.so']
        }
    }
}

dependencies {
    implementation files('libs/MkdLockLib.aar')
    implementation files('libs/MkdBLEConnectLib.aar')
    implementation files('libs/MkdElectronicKeyLib.aar')

    // 本地 AAR 不附带 Maven POM，宿主需显式声明这些外部依赖。
    // 以下版本与当前 MkdLockLib 源码配置一致，不代表这些依赖的最新版本。
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'io.reactivex.rxjava2:rxjava:2.2.10'
    implementation 'io.reactivex.rxjava2:rxandroid:2.1.1'
    implementation 'com.github.getActivity:XXPermissions:18.5'
}
```

宿主已使用相同依赖时，统一管理兼容版本即可，无需重复声明。不要同时使用上面的 `files(...)` 和覆盖同一批文件的 `fileTree(...)`；也不要将源码工程里的 `implementation project(':MkdLockLib')` 当作第三方 AAR 接入方法。

#### 4. ABI、JNI 与混淆

- 当前 `MkdLockLib` 配置了 `arm64-v8a` 和 `armeabi-v7a`，但 `MkdElectronicKeyLib` 只配置了 `arm64-v8a`；**完整电子钥匙链路目前以 `arm64-v8a` 为共同 ABI**。不能仅凭某个 AAR 包含 32 位库就宣称整套 SDK 支持 32 位。
- 不支持用当前交付配置在 x86/x86_64 模拟器上验证完整 JNI 链路。32 位支持需供应方另外提供整套匹配产物。
- JNI 依赖包括 `libnfclock.so`、`libmkdelectronickeylib.so` 以及 OpenSSL 动态库。不要删除 AAR 内的 `jni/` 文件，也不要直接排除重复的 OpenSSL 库。
- 当前源码两模块中的 arm64 OpenSSL 文件内容相同；实际交付时仍应核对最终 AAR 内文件。若来自不同版本，不要盲目 `pickFirst`，应先由供应方统一依赖。
- AAR 消费方不需要复制 SDK 的 CMake/NDK 配置，也不需要自己编译 native 源码；最终产物的 SO 完整性、16 KB 页兼容性需针对实际交付包单独验证。

`MkdLockLib` 的 consumer rules 已保留鉴权 JNI 类。当前 `MkdElectronicKeyLib` 的 consumer rules 为空；宿主启用 R8/ProGuard 时，建议初次接入在 `app/proguard-rules.pro` 添加以下保守规则，后续再根据实际使用范围收窄：

```proguard
-keep class com.makeid.nfclock.AlgorithmHelper { *; }
-keep class com.makeid.mkdelectronickeylib.** { *; }
-keep class com.makeid.lock_2.** { *; }
-keep class com.makeid.blelibrary.** { *; }
```

### Manifest 与运行时权限

仅使用电子钥匙 BLE 能力的宿主，可以按下面的配置声明权限和可选硬件能力。AAR 本身也会合并权限；最终请检查宿主的 **Merged Manifest**，不要只看 App 自己的 Manifest。

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.BLUETOOTH"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"
        android:maxSdkVersion="30" tools:replace="android:maxSdkVersion" />
    <!-- 本示例不使用 BLE 扫描推导物理位置。 -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
    <!-- 当前 SDK Manifest 声明了 USB host；仅用 BLE 的宿主可覆盖为可选。 -->
    <uses-feature android:name="android.hardware.usb.host"
        android:required="false" tools:replace="android:required" />
    <uses-feature android:name="android.hardware.nfc" android:required="false" />

    <application android:name=".DemoApplication">
        <!-- 无布局演示 Activity，由宿主内部页面启动；包名与后面的 Java 示例一致。 -->
        <activity android:name=".ElectronicKeyDemoActivity" android:exported="false" />
    </application>
</manifest>
```

- Android 12/API 31 及以上：示例按 `targetSdk >= 31`，动态申请 `BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`。
- Android 6～11/API 23～30：动态申请定位权限，并开启系统定位服务；Android 5/API 21～22 不弹运行时权限框。
- `neverForLocation` 只适用于不从扫描结果推导物理位置的业务；该声明可能过滤部分 BLE 广播，必须用目标设备验证。若业务确实需要位置，应按真实用途重新设计权限，不能照抄“不用于定位”的声明。
- 电子钥匙 BLE 开锁示例不需要申请相机、媒体或“所有文件访问”权限。OTA 示例使用 App 可读的 `File`，不等于必须申请所有文件访问权限。
- SDK 的 `checkPermissionAndRequest(...)` 是现有综合权限助手，会额外申请相机、定位和存储等权限，**不是最小 BLE 权限集合**。采用本节配置时，应像后面的示例一样自行申请权限，不要再同时调用该助手。
- 当前 AAR Manifest 包含存储、媒体等额外权限。若宿主仅用 BLE，可评估后通过 `tools:node="remove"` 移除不使用的 `MANAGE_EXTERNAL_STORAGE`、`READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`、`NFC` 权限；需要其他 SDK 功能时不要盲目删除。

### 初始化与接入顺序

1. 向供应方提供宿主的实际 `applicationId`，申请匹配包名的 `appID`、`appSecret`。不要把 SDK AppID 与 Android `applicationId` 混为一谈。
2. 使用 `Application` 调用 `initWithAppID(...)`；返回 `false` 时停止后续业务。
3. 切换到 `MKD_LOCK_TYPE_READER`。**不要使用仅保留的 `MKD_LOCK_TYPE_ELECTRONIC_KEY`，也不要因设备通过 BLE 连接就误选 `MKD_LOCK_TYPE_BLE`。**
4. 获取运行时权限，确认蓝牙打开；旧版 Android 还需确认定位服务打开。
5. 注册心跳，设置扫描前缀，扫描并连接用户选中的钥匙；连接前停止扫描，避免重复连接。
6. 等待有效心跳。蓝牙连接成功不代表锁芯已接入；开锁前还要确认 `lockCylinderState == 1`、锁芯身份及业务授权。
7. 根据设备名从业务服务取得**钥匙侧**密钥，并调用 `setElectronicKeySmSecret(...)`。锁侧密钥则按本次目标锁查询，不能混用。
8. 调用对应开关锁接口，处理成功、失败和进度；一项业务结束后再发下一项。不要在周期心跳内自动重复开锁。
9. 页面或会话退出时停止扫描、取消监听、断开连接；只有整个 SDK 业务退出时才调用 `release()`。

> SDK 使用进程内单例和共享回调状态，不适合多个页面同时切换模式或同时控制设备。同一个 KY 会话不要混用 `MkdLockManagerNewer` 与 `MkdElectronicKeyManager`，也不要在开锁、读状态、OTA 之间并发调用。内部发送队列不等于支持业务事务并发。

### 电子钥匙接口速查

以下接口均属于 `com.makeid.lock_2.MkdLockManagerNewer`。表中为方法名与参数，返回类型除特别标注外均为 `void`；回调类型位于 `com.makeid.lock_2.listener` 或 `com.makeid.mkdelectronickeylib.listener`。

| 接口 | 作用 / 回调 |
| --- | --- |
| `initWithAppID(String appID, String appSecret, Application application)` | 鉴权；同步返回 `boolean` |
| `isInit()` | 返回 `boolean`，查询鉴权状态 |
| `changeCurrentLockType(MkdLockTypeEnum type)` | 电子钥匙选择 `MKD_LOCK_TYPE_READER` |
| `setDeviceScanPrefix(String... prefix)` | 按设备名前缀过滤，如 `"KY53E", "KY53N"` |
| `startScan(int timeOut, MkdScanListener listener)` / `stopScan()` | 扫描/停止；`timeOut` 单位毫秒 |
| `connectDevice(Device device, MkdBleConnectListener listener)` | 连接扫描得到的设备对象；也有 `String` 设备地址重载 |
| `isBleDeviceConnect()` / `disConnectDevice()` | 返回 `boolean` 查询连接 / 断开 |
| `setOnElectronicKeyHeartBeatListener(OnHeartBeatListener listener)` | 主动心跳监听；传 `null` 解除业务监听 |
| `sendElectronicKeyHeart(String id, OnHeartBeatListener listener)` | 兼容接口，当前仅设置监听，不主动发心跳 |
| `setElectronicKeySmSecret(String smSecret)` | 设置钥匙侧 16 字节密钥，32 个 hex 字符 |
| `setElectronicKeyCrypto(int encryptMode, String key)` | 保留的显式配置入口；常规接入使用心跳协商 |
| `readElectronicKeyInfo(String id, OnReadElectKeyInfoListener listener)` | 钥匙信息；成功返回 `ElectronicKeyInfo` |
| `syncElectronicKeyTime(long timestamp, OnSyncTimeListener listener)` | 同步 Unix 时间戳，单位秒 |
| `syncElectronicKeyTone(ElectronicKeyToneType type, OnSyncElectronicKeyToneListener listener)` | 音效/LED；提交写请求即回调，不代表设备执行完成 |
| `readLockBasicInfoSuccess(MkdLockManagerListener listener)` | KY53N 从有效心跳返回锁芯 `sn` / `mac`；KY53E 当前返回不支持，应读心跳或 `A1` |
| `readElectronicKeyLockSN(String id, OnReadSerialNoListener listener)` | `A1` 读取锁芯信息，返回 `LockInfo` |
| `readElectronicKeyLockState(String id, OnReadLockStateListener listener)` | KY53E `A4` / KY53N `A7` 明文读取，返回 `LockStateEntity` |
| `readElectronicKeyLockProtocolVersion(OnReadLockProtocolVersionListener listener)` | `A9` 明文读取，返回 `LockProtocolVersionInfo` |
| `readElectronicKeyLockFirmwareVersion(OnReadLockFirmwareVersionListener listener)` | `A6` 明文读取，返回 `LockFirmwareVersionInfo`；不依赖 `smSecret` |
| `unlockElectronicKeyWithSecretKey(String uid, String password, String smSecret, MkdLockManagerProgressListener listener)` | 电子钥匙协议开锁；KY53E 走 `A1 → A3`，参数 `smSecret` 为锁侧密钥 |
| `lockElectronicKeyWithSecretKey(String uid, String password, String smSecret, MkdLockManagerProgressListener listener)` | 电子钥匙协议关锁；密钥规则同上 |
| `unlockWithSecretKey(String password, String smSecret, MkdLockManagerProgressListener listener)` / `lockWithSecretKey(...)` | 普通锁/读写器透传接口；KY53E 不支持，KY53N 走 NFC 读写器流程 |
| `configElectronicKeyCloseThreshold(String uid, String password, int thresholdMv, String smSecret, OnConfigCloseThresholdListener listener)` | KY53E `A1 → A3(action=0x11)`；锁侧密钥；阈值单位 mV |
| `readElectronicKeyCacheLog(String id, OnReadCacheLogListener listener)` / `clearElectronicKeyCacheLog(String id, OnClearCacheLogListener listener)` | 读取/清除钥匙缓存日志，使用已设置的钥匙侧密钥 |
| `sendElectronicKeyOfflineAuth(AuthNode node, String smSecret, OnSendOfflineAuthListener listener)` | 下发离线授权，参数 `smSecret` 为钥匙侧密钥 |
| `queryElectronicKeyOfflineAuth(int nid, String smSecret, OnManageOfflineAuthListener listener)` | 查询单个离线授权 |
| `queryAllElectronicKeyOfflineAuth(String smSecret, OnManageOfflineAuthListener listener)` | 查询全部，处理多包进度及最终列表 |
| `deleteElectronicKeyOfflineAuth(int nid, String smSecret, OnManageOfflineAuthListener listener)` / `deleteAllElectronicKeyOfflineAuth(String smSecret, OnManageOfflineAuthListener listener)` | 删除单个/全部离线授权 |
| `exchangeElectronicKey(String id, OnExchangeKeyListener listener)` | 兼容密钥交换；另有 `(id, smSecret, listener)` 重载，不是当前开关锁必需前置 |
| `rebootElectronicKey(String id, OnRebootKeyListener listener)` | 重启钥匙；请求发出后可能断开连接 |
| `upgradeElectronicKeyFirmware(File file, OnOtaUpgradeListener listener)` | OTA，使用钥匙侧上下文；升级期间不要发其他业务 |
| `removeScanListener()` / `releaseAllConnection()` / `release()` | 移除扫描监听 / 释放 BLE 连接 / 退出整个 SDK 业务 |

离线授权接口同时保留不带 `smSecret` 的重载，此时使用预先设置的钥匙侧密钥。更多参数及回调示例见后面的电子钥匙扩展章节。

#### 回调与业务完成判定

- `MkdLockManagerListener`：`onSuccess(Map<String, String>)` / `onFailed(MkdLockResult)`。
- `MkdLockManagerProgressListener`：额外提供 `onChargeProgress(int)`；进度达到 100 不能替代成功回调。
- 电子钥匙专用 listener 返回强类型实体或布尔结果；例如 `onSyncTime(false, timestamp)` 本身就是业务失败，不能只实现 `onSyncTimeError(...)`。
- 多包日志读取和离线授权查询应等待各自的 `on...Finish(...)`；进度或单包回调不代表全量完成。
- 回调不保证在主线程，也不要在回调中阻塞等待另一个 SDK 回调；UI 更新和业务状态修改统一切回主线程。
- 不同操作成功 Map 的语义不同。电子钥匙协议开关锁当前返回 `isOpen`（字符串 `"true"` / `"false"`）及 `lockStatus`，其中该路径的 `lockStatus` 固定为 `"1"`，**不能据此推断实时锁状态**；需要实际状态时读取后续心跳或调用状态接口。
- 失败回调的 `MkdLockResult` 在部分旧路径可能为 `null`，日志和 UI 必须判空；专用 listener 的数字错误码见后文，不要与统一枚举混用。

### 参数与密钥说明

| 参数 | 格式与来源 | 使用注意 |
| --- | --- | --- |
| `appID` / `appSecret` | 供应方按宿主包名授权 | 不是锁密码、不是设备密钥；不得写入日志 |
| `uid` / `id` | 业务系统分配的用户/操作标识，按 UTF-8 写入固定字段 | 常用请求字段 16 字节，不足补零、超长截断；建议使用不超过 16 字节的 ASCII 标识。不是 BLE MAC，也不要默认用设备名替代 |
| `password` | 锁密码的十六进制字符串，不带 `0x`、空格或分隔符 | KY53E `A3` 实际使用前 4 字节；建议由业务系统提供准确的 8 个 hex 字符，不要传入未编码的显示文本 |
| `keySmSecret` | 钥匙侧密钥，16 字节 / 32 个 hex 字符 | 按钥匙身份查询，设置给 `setElectronicKeySmSecret`；用于时间、日志、离线授权、音效、OTA 等钥匙侧加密链路 |
| `lockSmSecret` | 锁侧密钥，16 字节 / 32 个 hex 字符 | 按锁芯身份查询；KY53E 的每次开锁/关锁/阈值配置显式传入，不回退全局锁侧缓存 |
| `timestampSeconds` | Unix 时间戳，秒 | `System.currentTimeMillis() / 1000L`，不能直接传毫秒 |
| `thresholdMv` | 整数，单位 mV，按 16 位字段编码 | 应使用供应方确认的设备有效范围，不要仅因能编码就随意设值 |
| `firmwareFile` | 当前 App 可读、与目标硬件匹配的固件 `File` | 固件来源、适用型号和完整性由业务侧先校验 |

**两类加密模式也不能混淆：**心跳的 `electronicKeyEncryptMode` 对应钥匙侧，`lockEncryptMode` 对应锁侧；`1` 为 AES128，`2` 为 GM128/SM4。`KY53E A3` 使用锁侧模式与锁侧密钥；`KY53N A5` 电子钥匙协议使用钥匙侧模式与钥匙侧密钥。KY53N 通过普通读写器接口操作锁时，则遵循目标锁的 NFC 协议，不能套用 A5 的钥匙侧规则。

本 README 的密钥字符串只用于格式说明，不能作为生产密钥。不要把生产密钥或真实密码硬编码进示例、仓库或日志；取得密钥后还应按当前钥匙与锁芯身份匹配，避免拿上一把锁的参数开下一把锁。

### 完整 KY53E 接入示例

以下两个 Java 类使用包名 `com.example.keydemo`；宿主可替换成自己的包名，并同步调整 Manifest。示例无布局，演示权限、扫描、连接、心跳、手动开关锁与清理链路，**不是自动开锁程序**。UI 按钮和密钥查询由宿主业务提供。

#### 1. Application 中鉴权

若宿主已有自定义 `Application`，把初始化代码合并进去，不要再注册第二个 `Application`。示例配置项需要替换为供应方签发的真实值；生产配置不应在源码中公开。

```java
package com.example.keydemo;

import android.app.Application;
import com.makeid.lock_2.MkdLockManagerNewer;

public final class DemoApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        boolean ok = MkdLockManagerNewer.getInstance().initWithAppID(
                "替换为供应方签发的APP_ID",
                "替换为供应方签发的APP_SECRET",
                this);
        // 页面通过 isInit() 检查结果，鉴权失败时不允许发业务命令。
        if (!ok) {
            android.util.Log.e("KeyDemo", "SDK鉴权失败，请检查实际applicationId和授权配置");
        }
    }
}
```

#### 2. Activity 中扫描、连接和手动操作

示例只连接用户预先选定的 `KY53E26G0022`。实际应用应展示扫描列表，由用户选定后再连接，且应结合已绑定设备身份进行校验，而不是只信任广播名。所有业务状态在主线程管理，开关锁按钮绑定到 `operateLock(...)`，不能在心跳回调里调用它。

```java
package com.example.keydemo;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.makeid.blelibrary.bean.Device;
import com.makeid.lock_2.MkdLockManagerNewer;
import com.makeid.lock_2.ble.listener.MkdBleConnectListener;
import com.makeid.lock_2.ble.listener.MkdScanListener;
import com.makeid.lock_2.constant.MkdLockTypeEnum;
import com.makeid.lock_2.entity.MkdLockResult;
import com.makeid.lock_2.listener.MkdLockManagerProgressListener;
import com.makeid.mkdelectronickeylib.entity.HeartEntity;
import com.makeid.mkdelectronickeylib.listener.OnHeartBeatListener;

import java.util.Map;

public final class ElectronicKeyDemoActivity extends Activity {
    private static final String TAG = "KeyDemo";
    private static final String TARGET_NAME = "KY53E26G0022";
    private static final int REQUEST_BLE = 1001;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final MkdLockManagerNewer sdk = MkdLockManagerNewer.getInstance();
    private HeartEntity latestHeart;
    private boolean connecting;
    private boolean busy;
    private boolean closed;
    private int session;
    private Runnable operationTimeout;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!sdk.isInit()) {
            show("SDK未鉴权，停止接入");
            finish();
            return;
        }
        sdk.changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);
        sdk.setOnElectronicKeyHeartBeatListener(new OnHeartBeatListener() {
            @Override
            public void onHeartBeat(HeartEntity heart) {
                // 始终 post，统一到主线程管理状态，避免在 SDK 回调中同步重入业务。
                main.post(() -> {
                    if (closed || !sdk.isBleDeviceConnect()) return;
                    latestHeart = heart;
                    show(heart != null && heart.getLockCylinderState() == 1
                            ? "锁芯已接入，可核对身份并手动操作" : "等待锁芯接入");
                });
            }
        });
        requestBlePermissions();
    }

    private String[] requiredPermissions() {
        if (Build.VERSION.SDK_INT >= 31) {
            return new String[]{Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT};
        }
        return new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION};
    }

    private void requestBlePermissions() {
        if (Build.VERSION.SDK_INT < 23) {
            startScan();
            return;
        }
        for (String permission : requiredPermissions()) {
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(requiredPermissions(), REQUEST_BLE);
                return;
            }
        }
        startScan();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                          int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_BLE || closed) return;
        if (grantResults.length == 0) {
            show("权限申请已取消");
            return;
        }
        for (int result : grantResults) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                show("权限未授予；请在设置中授权后重新进入");
                return;
            }
        }
        startScan();
    }

    private void startScan() {
        // 调用前由页面引导用户开启蓝牙；Android 6～11 还需开启定位服务。
        sdk.setDeviceScanPrefix("KY53E");
        sdk.startScan(10_000, new MkdScanListener() {
            @Override public void onScanStart() { show("开始扫描"); }
            @Override public void onScanStop() { show("扫描停止"); }
            @Override public void onScanError(String msg) { show("扫描失败：" + msg); }

            @Override
            public void onScanResult(Device device, boolean isConnectedBySys) {
                main.post(() -> {
                    if (closed || connecting || sdk.isBleDeviceConnect()) return;
                    if (device == null || !TARGET_NAME.equals(device.getName())) return;
                    connecting = true; // 先置位，防止重复广播触发多次 connect。
                    latestHeart = null;
                    final int currentSession = ++session;
                    sdk.stopScan();
                    sdk.connectDevice(device, new MkdBleConnectListener() {
                        @Override
                        public void connectSuccess(Device connectedDevice) {
                            main.post(() -> {
                                if (closed || currentSession != session) return;
                                connecting = false;
                                show("蓝牙已连接，等待心跳；此时不能直接认定锁芯已连接");
                            });
                        }
                        @Override
                        public void connectFailed(String msg) {
                            main.post(() -> {
                                if (closed || currentSession != session) return;
                                connecting = false;
                                latestHeart = null;
                                show("连接失败：" + msg);
                            });
                        }
                        @Override
                        public void connectClose() {
                            main.post(() -> {
                                if (closed || currentSession != session) return;
                                ++session;
                                connecting = false;
                                latestHeart = null;
                                finishOperation();
                                show("设备断开；重新连接后需重新取得心跳和匹配密钥");
                            });
                        }
                    });
                });
            }
        });
    }

    // 由业务服务按当前钥匙身份获取密钥后，在主线程调用；不要填入锁侧密钥。
    public void configureKeySecret(String keySmSecret) {
        if (closed || !sdk.isBleDeviceConnect() || latestHeart == null) {
            show("请先连接并等待心跳");
            return;
        }
        if (keySmSecret == null || !keySmSecret.matches("[0-9a-fA-F]{32}")) {
            show("钥匙侧密钥格式错误");
            return;
        }
        sdk.setElectronicKeySmSecret(keySmSecret);
    }

    // 由用户明确点击按钮后在主线程调用；参数从业务授权结果取得，不在示例中写死。
    // open=true 开锁，open=false 关锁。expectedLockSn 是此次授权针对的锁芯 SN。
    public void operateLock(boolean open, String uid, String expectedLockSn,
                            String passwordHex, String lockSmSecret) {
        if (closed || busy || !sdk.isBleDeviceConnect()) {
            show("未连接或上次操作尚未结束");
            return;
        }
        if (latestHeart == null || latestHeart.getLockCylinderState() != 1
                || expectedLockSn == null || expectedLockSn.isEmpty()
                || !expectedLockSn.equals(latestHeart.getLockSN())) {
            show("锁芯未就绪或与授权目标不一致");
            return;
        }
        if (uid == null || !uid.matches("[\\x20-\\x7E]{1,16}")
                || passwordHex == null || !passwordHex.matches("[0-9a-fA-F]{8}")
                || lockSmSecret == null || !lockSmSecret.matches("[0-9a-fA-F]{32}")) {
            show("业务ID、锁密码或锁侧密钥格式错误");
            return;
        }
        busy = true;
        final int currentSession = session;
        // 30秒只是本示例的业务等待上限，不是 SDK 协议时限或取消命令接口。
        operationTimeout = () -> {
            ++session; // 忽略本次会话的迟到业务回调。
            latestHeart = null;
            connecting = false;
            finishOperation();
            sdk.disConnectDevice();
            show("等待超时，已断开；结果未知，请核实锁状态，勿自动重试");
        };
        main.postDelayed(operationTimeout, 30_000);
        MkdLockManagerProgressListener listener = new MkdLockManagerProgressListener() {
            @Override public void onChargeProgress(int progress) {
                show("操作进度：" + progress + "%（进度不代表最终成功）");
            }
            @Override public void onFailed(MkdLockResult result) {
                main.post(() -> {
                    if (closed || currentSession != session) return;
                    finishOperation();
                    show(result == null ? "操作失败，未知错误"
                            : "操作失败：" + result.name() + "/" + result.getKey()
                                    + "/" + result.getValue());
                });
            }
            @Override public void onSuccess(Map<String, String> data) {
                main.post(() -> {
                    if (closed || currentSession != session) return;
                    finishOperation();
                    show(open ? "开锁成功" : "关锁成功");
                });
            }
        };
        if (open) {
            sdk.unlockElectronicKeyWithSecretKey(uid, passwordHex, lockSmSecret, listener);
        } else {
            sdk.lockElectronicKeyWithSecretKey(uid, passwordHex, lockSmSecret, listener);
        }
    }

    private void finishOperation() {
        busy = false;
        if (operationTimeout != null) main.removeCallbacks(operationTimeout);
        operationTimeout = null;
    }

    private void show(String message) {
        // 实际 UI 更新应放到主线程；本示例只输出不含密钥的业务状态。
        Log.i(TAG, message);
    }

    @Override
    protected void onDestroy() {
        closed = true;
        ++session;
        finishOperation();
        main.removeCallbacksAndMessages(null);
        if (sdk.isInit()) {
            sdk.stopScan();
            sdk.removeScanListener();
            sdk.setOnElectronicKeyHeartBeatListener(null);
            sdk.disConnectDevice();
        }
        // 不在普通页面销毁时 release 全局单例，避免影响其他 SDK 业务。
        super.onDestroy();
    }
}
```

宿主按钮的调用关系为：业务后端完成授权 → 核对当前钥匙名和心跳锁芯 SN → 获取 `uid`、`passwordHex`、`lockSmSecret` → 用户点击后调用 `operateLock(true, uid, expectedLockSn, passwordHex, lockSmSecret)`。关锁传 `false`。`configureKeySecret(keySmSecret)` 用于钥匙侧业务配置，不替代每次 A3 显式传入的锁侧密钥。

示例只演示单页面独占会话，断线后由用户重新进入页面连接；生产应用还应管理后台/前台生命周期、心跳新鲜度、权限撤销、连接等待超时、异常恢复和业务授权有效期。等待超时或断线后可能出现“设备已执行，但 App 未收到确认”，应重新读取状态或现场确认，不要自动补发开锁。

### 常用业务示例

本节示例均在鉴权、READER 连接及有效心跳就绪后调用；**各示例独立执行，不能一次性并发下发**。类型分别从 `com.makeid.mkdelectronickeylib.entity`、`com.makeid.mkdelectronickeylib.listener` 导入。

#### 读取锁芯固件版本（无需密钥）

```java
import com.makeid.lock_2.MkdLockManagerNewer;
import com.makeid.mkdelectronickeylib.entity.LockFirmwareVersionInfo;
import com.makeid.mkdelectronickeylib.listener.OnReadLockFirmwareVersionListener;

// 放在 Activity/业务类的方法内：
MkdLockManagerNewer.getInstance().readElectronicKeyLockFirmwareVersion(
        new OnReadLockFirmwareVersionListener() {
            @Override
            public void onReadLockFirmwareVersion(LockFirmwareVersionInfo info) {
                if (info == null) return;
                String productionDate = info.getProductionDate();
                String firmwareVersion = info.getFirmwareVersion();
                String hardwareVersion = info.getHardwareVersion();
                // 将结果切回主线程后展示，或上报至业务系统用于兼容性判断。
            }
            @Override
            public void onReadLockFirmwareVersionError(int code, String error) {
                android.util.Log.e("KeyDemo", "A6读取失败：" + code + "/" + error);
            }
        });
```

#### 同步时间（钥匙侧密钥）

```java
import com.makeid.mkdelectronickeylib.listener.OnSyncTimeListener;

// keySmSecret 为业务服务按当前钥匙查询得到的32位hex字符串。
MkdLockManagerNewer.getInstance().setElectronicKeySmSecret(keySmSecret);
MkdLockManagerNewer.getInstance().syncElectronicKeyTime(
        System.currentTimeMillis() / 1000L,
        new OnSyncTimeListener() {
            @Override
            public void onSyncTime(boolean success, long timestamp) {
                android.util.Log.i("KeyDemo", "时间同步结果：" + success);
            }
            @Override
            public void onSyncTimeError(int code, String error) {
                android.util.Log.e("KeyDemo", "时间同步失败：" + code + "/" + error);
            }
        });
```

#### 查询全部离线授权（多包回调）

```java
import com.makeid.mkdelectronickeylib.entity.AuthNode;
import com.makeid.mkdelectronickeylib.entity.ManageOfflineAuthResult;
import com.makeid.mkdelectronickeylib.listener.OnManageOfflineAuthListener;
import java.util.List;

MkdLockManagerNewer.getInstance().queryAllElectronicKeyOfflineAuth(
        keySmSecret,
        new OnManageOfflineAuthListener() {
            @Override
            public void onManageOfflineAuthResult(ManageOfflineAuthResult result) {
                // 单包结果；不要在这里把多包查询当成全部结束。
            }
            @Override
            public void onManageOfflineAuthProgress(int current, int total) {
                android.util.Log.i("KeyDemo", "授权查询进度：" + current + "/" + total);
            }
            @Override
            public void onManageOfflineAuthFinish(List<AuthNode> authNodes) {
                // 最终列表；AuthNode 含敏感字段，不要直接序列化写日志。
                android.util.Log.i("KeyDemo", "授权查询完成，条数：" + authNodes.size());
            }
            @Override
            public void onManageOfflineAuthError(int code, String error) {
                android.util.Log.e("KeyDemo", "授权查询失败：" + code + "/" + error);
            }
        });
```

#### KY53N 使用普通读写器透传开锁

KY53N 可以走普通 NFC 读写器透传链路；需等待寻卡成功，并按目标锁型准备密码与锁侧密钥。下面是调用点，`progressListener` 按后文“回调说明”实现；不是 KY53E 的开锁写法。

```java
// 已切换 READER、已连接 KY53N、已发现目标锁，且业务授权已完成。
MkdLockManagerNewer.getInstance().unlockWithSecretKey(
        passwordHex, lockSmSecret, progressListener);
```

不要为了绕过 KY53E 的不支持错误而调用这个接口；KY53E 应使用完整示例中的 `unlockElectronicKeyWithSecretKey(...)`。

## 初始化

使用任何锁操作接口前，必须先完成 SDK 鉴权初始化。

```java
boolean success = MkdLockManagerNewer.getInstance()
        .initWithAppID(APP_ID, APP_SECRET, application);

if (!success) {
    // 授权失败，后续业务接口会返回 MkdLockResult.AuthenticationFail
}
```

初始化成功后，SDK 默认创建 NFC 类型锁实例。后续如需操作 BLE、USB 或读写器，需调用 `changeCurrentLockType(...)` 切换当前锁类型。

## 权限申请

BLE、扫码或存储相关能力可能依赖 Android 运行时权限，NFC 使用 Manifest 中的普通权限。SDK 内置的是综合权限申请助手，会申请相机、定位、蓝牙和存储等权限；仅使用电子钥匙 BLE 的第三方应用应优先按前文“Manifest 与运行时权限”自行申请最小权限，不要将下面的方法视为 BLE 开锁必需步骤。

```java
MkdLockManagerNewer.getInstance().checkPermissionAndRequest(context, new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        // result == MkdLockResult.PERMISSION_ERROR
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // 权限已授予
    }
});
```

## 锁类型切换

`MkdLockTypeEnum` 中定义了以下枚举，当前 `MkdLockLib` 实际落地实现的类型为 NFC、BLE 读写器、手机 BLE、USB。电子钥匙能力集成在读写器模式中使用：

| 类型 | 说明 |
| --- | --- |
| `MKD_LOCK_TYPE_NFC` | 手机 NFC 直接操作锁 |
| `MKD_LOCK_TYPE_READER` | BLE NFC 读写器操作锁；支持普通读写器、KY53N 读写器透传，以及 KY53E/KY53N 电子钥匙扩展能力 |
| `MKD_LOCK_TYPE_BLE` | 手机 BLE 直接操作蓝牙锁 |
| `MKD_LOCK_TYPE_USB` | USB 操作锁 |
| `MKD_LOCK_TYPE_ELECTRONIC_KEY` | 仅保留枚举，当前不作为独立锁类型使用；电子钥匙能力请切换到 `MKD_LOCK_TYPE_READER` 后调用 `MkdLockManagerNewer` 的 `ElectronicKey` 接口 |

示例：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);
```

切换类型后，后续读 SN、读状态、开关锁等接口都会走当前类型对应的实现。

## 回调说明

普通业务接口使用 `MkdLockManagerListener`：

```java
new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        String msg = result == null ? "" : result.getValue();
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // 成功数据通过 map 返回
    }
}
```

带充电进度的操作使用 `MkdLockManagerProgressListener`：

```java
new MkdLockManagerProgressListener() {
    @Override
    public void onChargeProgress(int progress) {
        // progress: 0-100
    }

    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
    }
}
```

注意：SDK 回调不保证一定在主线程执行。App 层如需更新 UI，应切回主线程后再操作 View。

## BLE 设备扫描与连接

### 设置扫描前缀

```java
MkdLockManagerNewer.getInstance().setDeviceScanPrefix("LOCK-", "其他前缀");
```

### 扫描设备

```java
MkdLockManagerNewer.getInstance().startScan(10_000, new MkdScanListener() {
    @Override
    public void onScanStart() {
    }

    @Override
    public void onScanStop() {
    }

    @Override
    public void onScanResult(Device device, boolean isConnectedBySys) {
        // 保存 device，用于后续 connectDevice(device, listener)
    }

    @Override
    public void onScanError(String errorMsg) {
    }
});
```

停止扫描：

```java
MkdLockManagerNewer.getInstance().stopScan();
```

### 连接 BLE 设备

```java
MkdLockManagerNewer.getInstance().connectDevice(device, new MkdBleConnectListener() {
    @Override
    public void connectSuccess(Device device) {
    }

    @Override
    public void connectFailed(String msg) {
    }

    @Override
    public void connectClose() {
    }
});
```

也可以通过设备标识字符串连接：

```java
MkdLockManagerNewer.getInstance().connectDevice(deviceAddress, listener);
```

连接状态：

```java
boolean connected = MkdLockManagerNewer.getInstance().isBleDeviceConnect();
```

断开或释放连接：

```java
MkdLockManagerNewer.getInstance().disConnectDevice();
MkdLockManagerNewer.getInstance().releaseAllConnection();
```

## NFC 连接

手机 NFC 模式下，切换锁类型后连接 `Tag`：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_NFC);

MkdLockManagerNewer.getInstance().connectTag(tag, status -> {
    if (status) {
        // NFC 已连接
    } else {
        // NFC 断开或连接失败
    }
});
```

NFC 辅助接口：

```java
boolean supportNfc = MkdLockManagerNewer.getInstance().isSupportNFC(context);
boolean nfcOpen = MkdLockManagerNewer.getInstance().isNFCOpen(context);

MkdLockManagerNewer.getInstance().createPendingIntent(activity);
MkdLockManagerNewer.getInstance().enableForegroundDispatch(activity);
MkdLockManagerNewer.getInstance().disableForegroundDispatch(activity);
```

## 通用锁操作接口

以下接口会根据当前 `MkdLockTypeEnum` 自动分发到 NFC、读写器、BLE 或 USB 实现。

### 读取锁基本信息

```java
MkdLockManagerNewer.getInstance().readLockBasicInfoSuccess(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        String sn = map.get("sn");
        String mac = map.get("mac");
        String supportNewProtocol = map.get("isSupportNewProtocol");
    }
});
```

常见返回字段：

| 字段 | 说明 |
| --- | --- |
| `sn` | 锁 SN 或 AX 锁编号 |
| `mac` | 锁 MAC，部分锁型可能为空 |
| `isSupportNewProtocol` | NFC 锁是否支持新协议，非所有锁型返回 |

### 读取锁状态和电量

```java
MkdLockManagerNewer.getInstance().readStatusAndElectricity(listener);
```

常见返回字段：

| 字段 | 说明 |
| --- | --- |
| `lockStatus` | 锁状态，不同锁型含义可能不同 |
| `nfcElectricity` | NFC 电量，单位 mV |
| `solarEnergyElectricity` | 太阳能电量，单位 mV |
| `batteryElectricity` | 电池电量，单位 mV 或协议返回值 |
| `temperature` | 温度，部分锁型返回 |
| `randomHex` | `PL56N/FL23N` 的 Page16 4 字节随机数 |
| `communicationEncryptionMode` | 通信加密方式，`PL56N/FL23N` 返回：`0` 不加密，`1` AES128，`2` GM128 |
| `communicationEncryptionModeName` | 通信加密方式名称：`NONE` / `AES128` / `GM128` / `UNKNOWN` |
| `sensorConfig` | 传感器配置原始值，`PL56N/FL23N` 返回 |
| `doorMagneticHall` | 门磁霍尔配置，`PL56N/FL23N` 返回：`0` 无，`1` 有 |
| `parameterStatus` | 参数状态原始值，`PL56N/FL23N` 返回 |
| `unlockCodeStatus` | 开锁码参数状态，`PL56N/FL23N` 返回：`0` 未配置，`1` 已配置 |
| `communicationKeyStatus` | 通信密钥参数状态，`PL56N/FL23N` 返回：`0` 未配置，`1` 已配置 |
| `hall1ReferenceDiffStatus` | 霍尔 1 参考差值参数状态，`PL56N/FL23N` 返回：`0` 未配置，`1` 已配置 |
| `lockBeamStatus` | 锁梁状态，运营商 BLE 锁返回 |
| `lockTypeC` | Type-C 连接状态，运营商 BLE 锁返回 |
| `lockBle` | 蓝牙连接状态，运营商 BLE 锁返回 |
| `lockShackleCondition` | 锁机械状态，部分 NFC 锁返回 |
| `birth` | 出厂日期，部分 BLE 锁返回 |

### 新协议锁状态说明

当前 `CL01`、`FL23N`、`PL56N` 按新协议锁处理。手机 NFC 和 BLE NFC 读写器在调用 `readStatusAndElectricity(...)` 时，会先通过多次读取状态判断 MCU 是否启动：

- 最多读取 `25` 次。
- 每次间隔 `200ms`。
- 判断依据为 NFC 电量是否发生变化。
- NFC 电量发生变化后，立即返回本次读取到的状态结果。
- 超过最大次数仍未变化时，返回 `MkdLockResult.MCU_START_FAILED`。
- 旧协议锁型不走该轮询逻辑，仍按原单次读取状态流程处理。

`PL56N/FL23N` 使用专用命令从 Page16 开始读取 Page16~Page19，并保持接口字段兼容：

| 字段 | 当前解析 |
| --- | --- |
| `randomHex` | `response[0..3]`，Page16 4 字节随机数 |
| Page17 | `response[4..7]`，当前忽略 |
| `nfcElectricity` | `response[8..9]` 大端，单位 mV |
| `lockStatus` | `response[10] & 0xff` |
| `temperature` | `response[11]`，最高位为符号位 |
| `communicationEncryptionMode` | `response[12] & 0xff` |
| `communicationEncryptionModeName` | `0=NONE`，`1=AES128`，`2=GM128`，其他为 `UNKNOWN` |
| `sensorConfig` | `response[13] & 0xff` |
| `doorMagneticHall` | `sensorConfig bit0` |
| `parameterStatus` | `response[14] & 0xff` |
| `unlockCodeStatus` | `parameterStatus bit0` |
| `communicationKeyStatus` | `parameterStatus bit1` |
| `hall1ReferenceDiffStatus` | `parameterStatus bit2` |
| `solarEnergyElectricity` | 固定返回 `"0"` |
| `batteryElectricity` | 固定返回 `"0"` |

说明：

- 查询状态不新增对外接口，但内部使用专用 Page16 命令；其他锁型继续使用原 Page18 状态命令。
- 手机 NFC 仅对“17 字节且首字节为 `00`”的响应去掉前导字节；BLE 读写器安全响应不执行该归一化。
- 其他锁型不会返回 `communicationEncryptionMode`、`sensorConfig`、`parameterStatus` 等扩展字段，业务层展示时应先判断字段是否存在。

### 读取开锁次数

```java
MkdLockManagerNewer.getInstance().readUnlockTimes(listener);
```

成功返回：

| 字段 | 说明 |
| --- | --- |
| `unlockTimes` | 开锁次数 |

### 读取固件版本

```java
MkdLockManagerNewer.getInstance().readFWVersion(listener);
```

成功返回：

| 字段 | 说明 |
| --- | --- |
| `version` | 固件版本 |
| `hardwareVersion` | 硬件版本，部分 BLE 锁返回 |

### 开锁

```java
MkdLockManagerNewer.getInstance().unlockWithSecretKey(
        password, lockSmSecret, new MkdLockManagerProgressListener() {
    @Override
    public void onChargeProgress(int progress) {
    }

    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // 开锁成功
    }
});
```

说明：

- 所有普通锁开锁均应调用三参接口 `unlockWithSecretKey(password, lockSmSecret, listener)`；不使用锁侧 SM 密码的锁型传 `null`。
- 二参 `unlockWithSecretKey(password, listener)` 仅保留兼容并已弃用；`PL56N/FL23N` mode 1/2 使用它会因缺少锁侧 `smSecret` 失败。
- NFC 锁可能需要充电流程，进度通过 `onChargeProgress` 返回。
- `CL01/FL23N/PL56N` 等新协议锁在查询状态时会先等待 MCU 启动；若 25 次读取内 NFC 电量未变化，会返回 `MkdLockResult.MCU_START_FAILED`。
- `PL56N/FL23N` 根据最终状态中的 `communicationEncryptionMode` 分流：mode 0（不加密）使用旧明文流程且允许 `lockSmSecret` 为空；mode 1 使用 AES128、mode 2 使用 GM128/SM4，key 均为锁侧 `smSecret`（16 字节 hex，32 个十六进制字符）。
- mode 1/2 必须传入合法的锁侧 `smSecret`，否则返回 `MkdLockResult.PasswordError`；未知 mode 返回 `MkdLockResult.CheckStatusFail`，不会回退明文流程。
- mode 1/2 的安全流程为 Block5：将 16 字节密文按 Page20~Page23 逐 page 写入（每 page 4 字节），初始等待 500ms 后最多轮询 25 次响应，响应解密校验通过后返回成功。
- 手机 NFC 侧兼容“17 字节且首字节为 `00`”的 Block5 响应（自动去掉前导字节）；BLE 读写器侧按 16 字节校验，不做该归一化。
- BLE AX 锁开锁时会根据已读取或传入的密码下发 AX 开锁协议。
- 在读写器模式下，KY53N 和普通读写器设备通过 NFC 读写器透传协议开锁；KY53E 调用该统一接口会返回 `MkdLockResult.UNSUPPORTED_DEVICE`。
- 密码错误通常返回 `MkdLockResult.PasswordError` 或 `MkdLockResult.VerifyPwdFail`，具体取决于锁型。

### 关锁

```java
MkdLockManagerNewer.getInstance().lockWithSecretKey(
        password, lockSmSecret, progressListener);
```

说明：

- 所有普通锁关锁均应调用三参接口 `lockWithSecretKey(password, lockSmSecret, listener)`；不使用锁侧 SM 密码的锁型传 `null`。
- 二参 `lockWithSecretKey(password, listener)` 仅保留兼容并已弃用。
- 关锁是否支持取决于当前锁型。
- `PL56N/FL23N` 关锁前会校验当前锁状态，仅 `lockStatus` 为 `"0"` 或 `"2"` 时允许关锁，否则返回 `MkdLockResult.LOCK_STATUS_NOT_SUPPORT_OPERATION`。
- `PL56N/FL23N` mode 0 不校验锁侧 `smSecret`；mode 1/2 必须传入 16 字节 hex `smSecret`，安全流程与开锁一致（Block5 逐 page 写入 + 轮询解密响应）。
- 在读写器模式下，KY53N 和普通读写器设备通过 NFC 读写器透传协议关锁；KY53E 调用该统一接口会返回 `MkdLockResult.UNSUPPORTED_DEVICE`。
- 失败可能返回 `MkdLockResult.CheckLockStatusFail`、`MkdLockResult.PasswordError` 等。

### 配置 PL56N/FL23N 关锁阈值

```java
MkdLockManagerNewer.getInstance().configLockCloseThreshold(
        password, thresholdMv, lockSmSecret, new OnConfigCloseThresholdListener() {
    @Override
    public void onConfigCloseThreshold(boolean isSuccess, int thresholdMv) {
        // 配置结果及本次配置的阈值
    }

    @Override
    public void onError(int code, String error) {
        // 失败，code 对应 MkdLockResult.getKey()
    }
});
```

说明：

- 回调 `OnConfigCloseThresholdListener` 位于 `com.makeid.mkdelectronickeylib.listener` 包（`MkdElectronicKeyLib`）。
- 仅 `PL56N/FL23N` 支持该接口，其他锁型通过 `onError` 返回 `UNSUPPORTED_DEVICE`。
- 该接口对应 Block5 业务动作 `0x11`，只支持 mode 1/2；mode 0 返回 `UNSUPPORTED_DEVICE`，不会写入 Page20~Page23。
- 执行前同样会先完成 MCU 启动检测并读取 Page16~Page19 状态，再按 mode 路由。
- mode 1/2 必须传入合法的锁侧 `smSecret`（16 字节 hex），否则返回 `PasswordError`；安全流程与开关锁一致（逐 page 写入 + 轮询解密响应）。
- SDK 不限制 `thresholdMv` 的业务范围，协议按 2 字节大端写入。

### 重置锁状态

```java
MkdLockManagerNewer.getInstance().resetLock(password, progressListener);
```

成功时可能返回：

| 字段 | 说明 |
| --- | --- |
| `lockStatus` | 重置后的锁状态 |
| `reset` | 重置结果标记，部分锁型返回 |

## 读写器相关接口

切换到读写器模式：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);
```

连接 BLE 读写器后，SDK 会根据设备型号处理寻卡：

- 普通读写器、KY53N：连接成功后自动开启寻卡。
- KY53E：连接成功后不自动开启寻卡，仅使用电子钥匙业务能力。

可以注册寻卡回调：

```java
MkdLockManagerNewer.getInstance().addReceiveRWSearchCardListener(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        String hasCard = map.get("hasCard");
        String uid = map.get("uid");
        String protocol = map.get("protocol");
    }
});
```

查询读写器状态：

```java
MkdLockManagerNewer.getInstance().queryBleReaderWriterStatus(listener);
```

常见返回字段：

| 字段 | 说明 |
| --- | --- |
| `rwPowerMV` | 读写器电量 mV |
| `rwPowerPercent` | 读写器电量百分比 |
| `rwHW` | 读写器硬件版本 |
| `rwSW` | 读写器固件版本 |

设置 NFC 协议：

```java
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.DEFAULT.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_14443_A.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_14443_B.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_15693.getValue());
```

### KY 设备发送队列

普通读写器设备仍按原逻辑直接发送 BLE 指令。当前连接设备为 KY53E 或 KY53N 时，`MkdLockLib` 会对读写器命令和电子钥匙命令做串行发送：

- 同一时间只写入一条指令。
- 收到一条完整的 `0x70`、`0x71` 或 `0x73` 帧后再发送下一条。
- KY 设备主动上报的心跳帧也会作为完整响应释放队列。
- `0x0B` 同步音效指令不等待设备协议响应；写入请求提交后立即回调成功，也不会占用等待响应的队列状态。
- 断开连接、重新连接或释放资源时会清空待发送队列。

## 电子钥匙扩展接口

电子钥匙能力通过读写器模式统一接入。使用前先切换到读写器模式并连接 KY53E 或 KY53N 设备：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);

MkdLockManagerNewer.getInstance().connectDevice(device, connectListener);
```

设备能力说明：

| 设备 | 开关锁 | 电子钥匙业务 |
| --- | --- | --- |
| KY53E | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` 返回 `UNSUPPORTED_DEVICE`；需要使用 `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)` | 支持 |
| KY53N | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` 走读写器 NFC 透传流程 | 支持 |
| 普通读写器/YS | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` 走读写器 NFC 透传流程 | 不支持 |

### 心跳监听

KY 设备会主动上报心跳。注册监听后等待设备上报即可，`sendElectronicKeyHeart(...)` 当前只用于设置监听，不主动发送心跳指令。

当前心跳载荷已扩展为 32 字节明文，SDK 直接按明文统一解析。心跳中包含电子钥匙状态、锁芯连接状态、锁状态、锁芯 `SN` / `MAC`、电子钥匙内部时间，以及钥匙和锁具加密模式。

```java
MkdLockManagerNewer.getInstance().setOnElectronicKeyHeartBeatListener(new OnHeartBeatListener() {
    @Override
    public void onHeartBeat(HeartEntity heartEntity) {
        int keyBattery = heartEntity.getElectronicKeyBattery();
        int keyState = heartEntity.getElectronicKeyState();
        int lockCylinderState = heartEntity.getLockCylinderState();
        int lockState = heartEntity.getLockState();
        String lockSN = heartEntity.getLockSN();
        String lockMac = heartEntity.getLockMac();
        long electronicKeyTimeSec = heartEntity.getElectronicKeyTimeSec();
        int electronicKeyEncryptMode = heartEntity.getElectronicKeyEncryptMode();
        int lockEncryptMode = heartEntity.getLockEncryptMode();
    }
});
```

`HeartEntity` 字段说明：

| 字段 | 说明 |
| --- | --- |
| `electronicKeyBattery` | 钥匙电量，范围 `0~100` |
| `electronicKeyState` | 钥匙内部状态：`0` 正常，`1` 充电 |
| `lockCylinderState` | 锁芯连接状态：`0` 未连接，`1` 已连接 |
| `lockState` | 锁状态：`0` 无状态，`1` 已开锁，`2` 已关锁 |
| `lockSN` | 锁芯 SN，对应心跳明文 `M4~M15` |
| `lockMac` | 锁芯 MAC，对应心跳明文 `M16~M24`，9 字节字段内部仍为“长度前缀 + MAC 数据” |
| `electronicKeyTimeSec` | 电子钥匙内部时间，Unix 时间戳，单位秒，对应心跳明文 `M25~M28` |
| `electronicKeyEncryptMode` | 电子钥匙加密模式：`1` AES128，`2` GM128 |
| `lockEncryptMode` | 锁具加密模式：`1` AES128，`2` GM128 |
| `reserve` | 心跳预留字节，对应明文 `M31` |

补充说明：

- 锁芯未连接时，`lockSN` / `lockMac` 可能为空。
- KY 设备主动上报的心跳帧会同时作为发送队列的完成信号，收到心跳后才会继续发送下一条 KY 指令。
- 如需在业务层实时感知锁芯连接变化，建议常驻注册 `setOnElectronicKeyHeartBeatListener(...)`。
- 若设备仍返回旧短包心跳，SDK 会兼容解析基础字段，新增字段默认值为 `0`。
- 建议在收到第一条有效心跳后，不区分当前心跳是 `AES128` 还是 `GM128`，都先用电子钥匙蓝牙名称查询**钥匙侧** `smSecret`，然后直接设置给 SDK；加密方式由 SDK 根据心跳自动缓存。

### 基于心跳读取锁芯 SN / MAC

在 `MKD_LOCK_TYPE_READER` 模式下，当前连接 **KY53N** 时，调用统一的读锁基本信息接口会从最近一次电子钥匙心跳中返回锁芯 `SN` 和 `MAC`。**KY53E 当前调用该通用接口返回 `UNSUPPORTED_DEVICE`**，应直接读取 `OnHeartBeatListener` 中的 `getLockSN()` / `getLockMac()`，或使用 `readElectronicKeyLockSN(uid, listener)` 读取 A1 信息。下面的通用读信息示例适用于 KY53N：

```java
MkdLockManagerNewer.getInstance().readLockBasicInfoSuccess(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        String sn = map.get("sn");
        String mac = map.get("mac");
    }
});
```

说明：

- 该流程要求电子钥匙已通过心跳上报为“锁芯已连接”状态。
- 若当前尚未收到有效心跳，或心跳中未携带锁芯 `SN`，接口会返回对应失败结果。
- `mac` 为心跳中的锁芯 `MAC`，格式为不带分隔符的大写十六进制字符串。

### 电子钥匙信息、时间和锁状态

```java
MkdLockManagerNewer.getInstance().readElectronicKeyInfo(uid, readKeyInfoListener);
MkdLockManagerNewer.getInstance().syncElectronicKeyTime(timestampSeconds, syncTimeListener);
MkdLockManagerNewer.getInstance().setElectronicKeySmSecret(
        "00112233445566778899AABBCCDDEEFF");
MkdLockManagerNewer.getInstance().exchangeElectronicKey(uid, exchangeKeyListener);
MkdLockManagerNewer.getInstance().readElectronicKeyLockSN(uid, readSerialNoListener);
MkdLockManagerNewer.getInstance().readElectronicKeyLockState(uid, readLockStateListener);
MkdLockManagerNewer.getInstance().readElectronicKeyLockProtocolVersion(readProtocolVersionListener);
MkdLockManagerNewer.getInstance().readElectronicKeyLockFirmwareVersion(readFirmwareVersionListener);
MkdLockManagerNewer.getInstance().rebootElectronicKey(uid, rebootKeyListener);
```

说明：

- `uid` 为电子钥匙业务 ID。测试工具中通常从本地配置或输入框读取。
- `setElectronicKeySmSecret(...)` 用于设置**钥匙侧** `smSecret`。后续 `0x05 / 0x07 / 0x09 / 0x0A / 0xA5 / 0x10 / 0x11` 等接口会结合 SDK 最近一次心跳缓存的加密方式自动处理。
- 上述“自动处理”仅指 SDK 自动选择 `AES128` 或 `GM128`；如果这些接口需要走钥匙侧加解密链路，那么两种模式下都要求已经设置合法的钥匙侧 `smSecret`。
- `setElectronicKeyCrypto(...)` 仍保留，但更适合做显式覆盖；常规接入不需要再手动设置加密方式。
- `exchangeElectronicKey(...)` 仍保留，但当前主要作为兼容接口使用；它不再作为 `KY53E / KY53N` 开关锁前置步骤。
- `readElectronicKeyLockSN(...)` 要求电子钥匙已连接锁芯，否则会返回未连接锁芯错误。
- `readElectronicKeyLockState(...)` 当前走明文：`KY53E` 用 `A4`，`KY53N` 用 `A7`。
- `readElectronicKeyLockProtocolVersion(...)` 走 `A9` 明文协议，返回锁协议类型、版本号等信息。
- `readElectronicKeyLockFirmwareVersion(...)` 走 `A6` 明文协议，返回锁芯生产日期、固件版本和硬件版本；不依赖 `smSecret`。
- 非 KY53E/KY53N 设备调用这些接口会通过对应电子钥匙 listener 返回不支持或连接失败。

### 同步电子钥匙音效或 LED 状态

```java
MkdLockManagerNewer.getInstance().syncElectronicKeyTone(
        ElectronicKeyToneType.LOCK_ON_TONE,
        new OnSyncElectronicKeyToneListener() {
            @Override
            public void onSyncElectronicKeyTone(boolean isSuccess,
                                                 ElectronicKeyToneType toneType) {
                // 指令已提交到 BLE 写请求
            }

            @Override
            public void onSyncElectronicKeyToneError(int code, String message) {
                // 参数、连接状态或加密上下文错误
            }
        });
```

说明：

- 仅当前连接设备为 `KY53E` 或 `KY53N` 时支持。
- 对应电子钥匙 `0x0B` 指令。指令字明文发送，16 字节业务体 `M0 + 15` 个 `0x00` 使用钥匙侧心跳协商的加密方式及当前钥匙侧 `smSecret` 加密。
- 设备不会回复 `0x0B`。SDK 将数据提交到 BLE 写请求后即回调 `onSyncElectronicKeyTone(true, toneType)`，成功不代表设备实际播放、点亮或执行完成。
- 下发前仍会检查 SDK 鉴权、BLE 连接、电子钥匙状态以及钥匙侧加密上下文；失败通过 `onSyncElectronicKeyToneError(...)` 返回。
- `ElectronicKeyToneType` 支持 `0x01~0x07` 音效、`0x08~0x10` LED 状态、`0x11/0x12` 蓝牙连接状态以及 `0x13~0x16` 开关锁结果和超时提示。

### KY53E 电子钥匙开关锁

KY53E 不启用读写器透传开关锁能力，如需通过电子钥匙协议开关锁，使用以下接口：

```java
MkdLockManagerNewer.getInstance()
        .unlockElectronicKeyWithSecretKey(
                uid,
                password,
                lockSmSecret,
                progressListener);

MkdLockManagerNewer.getInstance()
        .lockElectronicKeyWithSecretKey(
                uid,
                password,
                lockSmSecret,
                progressListener);
```

执行约束：

- `password` 为锁密码十六进制字符串。
- `lockSmSecret` 是**锁侧** `smSecret`，必须显式传入。
- `A3` 未传锁侧 `smSecret` 时直接失败。
- 当前主流程已改为 `A1 -> A3`，不再依赖 `A2`。
- 失败前会校验 BLE 连接、锁芯连接状态、密码格式。

如需配置 `KY53E` 关锁霍尔阈值：

```java
MkdLockManagerNewer.getInstance().configElectronicKeyCloseThreshold(
        uid,
        password,
        thresholdMv,
        lockSmSecret,
        listener);
```

这里的 `lockSmSecret` 也表示**锁侧** `smSecret`。

### 缓存日志

```java
MkdLockManagerNewer.getInstance().readElectronicKeyCacheLog(uid, new OnReadCacheLogListener() {
    @Override
    public void onReadCacheLog(List<LogNode> logNodes) {
        // 全量日志
    }

    @Override
    public void onReadCacheLogProgress(int length) {
        // 本次收到的日志条数
    }

    @Override
    public void onReadCacheLogFinish() {
        // 读取完成
    }

    @Override
    public void onReadCacheLogError(int code, String error) {
    }
});

MkdLockManagerNewer.getInstance().clearElectronicKeyCacheLog(uid, clearCacheLogListener);
```

### 离线授权

```java
MkdLockManagerNewer.getInstance().sendElectronicKeyOfflineAuth(
        authNode,
        keySmSecret,
        sendOfflineAuthListener);
MkdLockManagerNewer.getInstance().queryElectronicKeyOfflineAuth(
        nid,
        keySmSecret,
        manageOfflineAuthListener);
MkdLockManagerNewer.getInstance().queryAllElectronicKeyOfflineAuth(
        keySmSecret,
        manageOfflineAuthListener);
MkdLockManagerNewer.getInstance().deleteElectronicKeyOfflineAuth(
        nid,
        keySmSecret,
        manageOfflineAuthListener);
MkdLockManagerNewer.getInstance().deleteAllElectronicKeyOfflineAuth(
        keySmSecret,
        manageOfflineAuthListener);
```

语义区分：

- 这些接口中的 `keySmSecret` 表示**钥匙侧** `smSecret`，用于 `0x09 / 0x0A` 收发加解密。
- `authNode.lockSmSecret` 表示授权写入数据里的**锁侧** `smSecret`。
- 若已提前通过 `setElectronicKeySmSecret(...)` 设置过钥匙侧 `smSecret`，也可以使用不带 `smSecret` 的重载。

`queryAllElectronicKeyOfflineAuth(...)` 为多包流程，可通过 `OnManageOfflineAuthListener.onManageOfflineAuthProgress(current, total)` 获取进度，通过 `onManageOfflineAuthFinish(List<AuthNode> authNodes)` 获取最终授权列表。

### OTA 升级

```java
MkdLockManagerNewer.getInstance().upgradeElectronicKeyFirmware(firmwareFile, new OnOtaUpgradeListener() {
    @Override
    public void onEnterOtaMode() {
    }

    @Override
    public void onProgress(int current, int total) {
    }

    @Override
    public void onSuccess() {
    }

    @Override
    public void onFail(int code, String msg) {
    }
});
```

## 运营商 BLE/USB 锁接口

切换 BLE 或 USB：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);

MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_USB);
```

读取和设置休眠时间：

```java
MkdLockManagerNewer.getInstance().readIdleTime(listener);
MkdLockManagerNewer.getInstance().writeIdleTime(60, listener);
```

读取休眠时间成功返回：

| 字段 | 说明 |
| --- | --- |
| `idleTime` | 休眠时间，单位秒 |

重启和立即休眠：

```java
MkdLockManagerNewer.getInstance().operateReset(listener);
MkdLockManagerNewer.getInstance().operateSleep(listener);
```

注册关锁状态上报：

```java
MkdLockManagerNewer.getInstance().regisMkdLockReportListener(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        // 上报失败或开锁状态
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // 收到关锁上报
    }
});
```

取消注册：

```java
MkdLockManagerNewer.getInstance().unRegisMkdLockReportListener();
```

USB 运行监听：

```java
MkdLockManagerNewer.getInstance()
        .setUSBRunningListener(new MkdUsbIndependentServer.IUsbConnectListener() {
            @Override
            public void onUsbConnect() {
            }

            @Override
            public void onUsbDisConnect() {
            }

            @Override
            public void onUsbDataConnectStatus(boolean status) {
            }
        });
```

## AX 蓝牙锁专用接口

AX 锁通过蓝牙名称前缀 `LOCK-` 识别，使用手机 BLE 模式：

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);
```

### 读取 AX 锁密码

```java
MkdLockManagerNewer.getInstance().readAXLockPassword(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        String password = map.get("password");
    }
});
```

成功返回：

| 字段 | 说明 |
| --- | --- |
| `password` | AX 锁密码，十六进制字符串 |

### 设置 AX 网络参数

```java
MkdLockManagerNewer.getInstance()
        .setAXNetworkParameter("120.24.1.1", 1883, listener);
```

### 读取 AX 网络参数

```java
MkdLockManagerNewer.getInstance().readAXNetworkParameter(listener);
```

设置和读取成功均返回：

| 字段 | 说明 |
| --- | --- |
| `ip` | 主报 IP |
| `port` | 主报端口 |

### 设置 AX APN 参数

```java
MkdAXApnInfo apnInfo = new MkdAXApnInfo();
apnInfo.setApnName("cmnet");
apnInfo.setApn("cmnet");
apnInfo.setUserName("");
apnInfo.setUserPsw("");
apnInfo.setAuthType("");
apnInfo.setApnType("");
apnInfo.setApnRever1("");

MkdLockManagerNewer.getInstance().setAXApnParameter(apnInfo, listener);
```

### 读取 AX APN 参数

```java
MkdLockManagerNewer.getInstance().readAXApnParameter(listener);
```

设置和读取成功均返回：

| 字段 | 说明 |
| --- | --- |
| `apnName` | APN 名称 |
| `apn` | APN |
| `userName` | 用户名 |
| `userPsw` | 密码 |
| `authType` | 鉴权方式 |
| `apnType` | APN 类型 |
| `apnRever1` | 保留字段 |

注意：AX APN 协议中每个字段固定 32 字节，写入时不足长度由底层补 0。

## NFC 网络类接口

部分 NFC 锁支持网络状态、设备参数、MQTT 密码、SIM 卡号等读取。

```java
MkdLockManagerNewer.getInstance().resetNetwork(listener);
MkdLockManagerNewer.getInstance().readNetworkStatus(listener);
MkdLockManagerNewer.getInstance().readDeviceParameter(listener);
MkdLockManagerNewer.getInstance().readMQTTPassword(listener);
MkdLockManagerNewer.getInstance().readSimCardNumber(listener);
```

常见返回字段：

| 接口 | 字段 | 说明 |
| --- | --- | --- |
| `readNetworkStatus` | `status` | 网络状态 |
| `readNetworkStatus` | `pw` | 网络信号强度 |
| `readDeviceParameter` | `defaultReconnectInterval` | 默认重连间隔 |
| `readDeviceParameter` | `defaultKeepAliveTime` | 默认保活时间 |
| `readMQTTPassword` | `password` | MQTT 密码 |
| `readSimCardNumber` | `SimICCID` | SIM 卡 ICCID |

## 工厂/调试类接口

以下接口一般用于工厂测试或调试。

```java
MkdLockManagerNewer.getInstance().readMCUStatus(5, listener);
MkdLockManagerNewer.getInstance().readSensorStatus(listener);
MkdLockManagerNewer.getInstance().readNfcLockRunLog(listener);
MkdLockManagerNewer.getInstance().getSystemClockTime(listener);
```

常见返回字段：

| 接口 | 字段 | 说明 |
| --- | --- | --- |
| `readMCUStatus` | `mcu_status` | MCU 状态原始数据 |
| `readSensorStatus` | `open` | 门状态 |
| `readSensorStatus` | `localStatus` | 锁舌状态 |
| `readNfcLockRunLog` | `defaultServerAddress` | 是否默认服务器地址 |
| `readNfcLockRunLog` | `lastNetWorkSuccess` | 上次网络请求是否成功 |
| `readNfcLockRunLog` | `lastNetWorkFailATCode` | 上次网络请求失败 AT 指令 |
| `getSystemClockTime` | `time` | 系统开机后经过时间 |

## 资源释放

普通 BLE 页面退出时先 `stopScan()`、`removeScanListener()`、`setOnElectronicKeyHeartBeatListener(null)`、`disConnectDevice()`，参见完整示例。`release()` 用于整个 SDK 业务退出，需先成功初始化，且确认没有其他页面使用共享单例：

```java
if (MkdLockManagerNewer.getInstance().isInit()) {
    MkdLockManagerNewer.getInstance().release();
}
```

`release()` 不是业务取消接口，也不应被当作恢复初始状态后可直接重用的保证；再次使用时按完整初始化与连接流程重建会话。

## 常见错误码

统一锁操作的 `MkdLockManagerListener.onFailed(...)` / `MkdLockManagerProgressListener.onFailed(...)` 使用 `MkdLockResult`；电子钥匙专用 listener 的 `on...Error(int, String)` / `onFail(int, String)` 使用其业务错误码，不能统一按 `MkdLockResult` 查表。建议同时记录入口方法、回调类型、枚举名、数字码与描述。

`MkdLockResult` 常见值如下：

| 枚举 | `getKey()` | 说明 |
| --- | --- | --- |
| `AuthenticationFail` | `0` | SDK 授权失败 |
| `ConnectFail` | `1` | NFC 连接失败 |
| `WriteDataFail` | `2` | NFC 写入数据失败 |
| `ChargePowerFail` | `3` | 充电失败 |
| `VerifyPwdFail` | `4` | 密码校验失败 |
| `CheckStatusFail` | `5` | 校验锁具状态失败；电子钥匙锁侧上下文/响应异常也可能返回此码 |
| `PasswordError` | `7` | 密码错误；部分加密流程中也表示密钥格式/参数错误 |
| `BLENoConnect` | `9` | 未连接 BLE 设备 |
| `SET_NFC_RES_TIME_OUT` | `11` | 枚举定义为 NFC 模块响应超时，不能据此解释另一套电子钥匙错误码 |
| `NEED_CONNECT_NFC` | `12` | 请靠近 NFC 标签 |
| `READ_NFC_DATA_FAIL` | `13` | 读取 NFC 数据失败 |
| `MCU_START_FAILED` | `19` | 新协议锁型查询状态时，25 次读取内 NFC 电量未变化，判定 MCU 启动失败 |
| `TAG_LOST` | `25` | NFC Tag 丢失 |
| `PERMISSION_ERROR` | `27` | 权限申请失败 |
| `CheckLockStatusFail` | `28` | 关锁校验锁具状态失败 |
| `UNSUPPORTED_DEVICE` | `29` | 当前设备或当前锁类型不支持该接口 |
| `RESET_LOCK_STATUS_FAIL` | `30` | 重置锁具状态失败 |
| `LOCK_STATUS_NOT_SUPPORT_OPERATION` | `31` | 当前锁具状态不支持操作 |
| `ELECTRONIC_KEY_NOT_CONNECT_LOCK` | `32` | 电子钥匙未连接锁芯 |

可通过以下方式获取错误描述：

```java
if (result != null) {
    String name = result.name();
    int code = result.getKey();
    String message = result.getValue();
    // 同时记录入口方法和回调类型，不要只记录数字。
}
```

电子钥匙专用错误码中，`MkdElectronicKeyMenu` 定义了 `2` 钥匙连接失败、`3` 密码格式错误、`4` 交换密钥/加密上下文异常、`5` 未连接锁、`6~10` OTA 相关错误、`11` 不支持设备类型。部分专用回调也会直接返回 `MkdLockResult` 数字码或解析错误 `-1`，应结合接口和错误描述判断，不能仅看数字。

特别是 A3 响应解析为 `0xFF` 时，当前 `MkdLockLib` 的开关锁进度回调返回 `MkdLockResult.UNSUPPORTED_DEVICE`（`29`）；直接使用底层 `MkdElectronicKeyLib` 的开锁回调则返回 `11`。解析结果依赖正确的解密上下文，现场仍需核对完整响应，不能只凭数字认定设备型号不支持。

## 注意事项

- 必须先调用 `initWithAppID(...)`，初始化成功后再调用其他业务接口。
- 切换 NFC、BLE 读写器、BLE、USB 等不同模式时，需要先调用 `changeCurrentLockType(...)`。
- BLE/USB 操作前需确保设备已连接；NFC 操作前需确保 `Tag` 已连接。
- 电子钥匙能力在 `MKD_LOCK_TYPE_READER` 模式下使用，App 不应在同一个 KY 设备连接会话中同时直接操作 `MkdElectronicKeyManager` 和 `MkdLockManagerNewer`。
- KY53E 连接后不会自动开启读写器寻卡；KY53N 和普通读写器连接后会自动寻卡。
- KY53E 的 `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` 保持返回 `UNSUPPORTED_DEVICE`，需要使用 `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)`。
- KY53E/KY53N 连接时，读写器命令和电子钥匙命令会串行发送；普通读写器设备保持直接发送。
- `CL01/FL23N/PL56N` 查询状态时会等待 MCU 启动，判断逻辑为 NFC 电量变化；旧协议锁型不受影响。
- `PL56N/FL23N` 没有太阳能电量和电池电量，`solarEnergyElectricity`、`batteryElectricity` 固定返回 `"0"`。
- `PL56N/FL23N` 的扩展状态字段只在这两类锁型返回，其他锁型未返回时 App 不应拼接默认分隔符或强制展示空值。
- `PL56N/FL23N` 的开关锁和关锁阈值配置由锁端状态的 `communicationEncryptionMode` 决定流程：mode 0 明文、mode 1 AES128、mode 2 GM128/SM4；mode 1/2 必须提供锁侧 `smSecret`，SDK 不会用明文流程兜底未知 mode。
- `PL56N/FL23N` 的 `configLockCloseThreshold(...)`（`0x11`）只在 mode 1/2 可用，mode 0 调用会返回 `UNSUPPORTED_DEVICE`。
- AX 专用接口只适用于蓝牙名称以 `LOCK-` 开头的 AX 锁。
- SDK 回调线程不固定，App 更新 UI 时必须切回主线程。
- 不同锁型返回字段存在差异，业务层应通过 `map.containsKey(...)` 判断字段是否存在后再使用。

## 第三方接入排查与交付检查

### 常见接入问题

| 现象 | 优先检查 |
| --- | --- |
| 无法导入 `Device` 或电子钥匙 listener/entity | 配套 BLE / ElectronicKey AAR 是否齐全；本地 AAR 不会自动解析内部模块依赖 |
| `NoClassDefFoundError` 指向 RxJava、XXPermissions 等 | 是否显式添加了外部依赖；不能只复制 AAR |
| `Duplicate class` | 是否同时引入源码模块与 AAR、多个版本，或在合并 AAR 外又添加其内嵌库 |
| 合并 JNI 时提示 OpenSSL 重复 | 核实实际交付包内同 ABI 的两份 SO 内容一致，再使用前文限定文件名的 `pickFirsts` |
| `UnsatisfiedLinkError` / 找不到 native 方法 | ABI 是否匹配；JNI 及 OpenSSL 是否完整；`NativeLib` / `AlgorithmHelper` 是否被混淆；保留完整异常栈，不要只记录“初始化失败” |
| `initWithAppID(...) == false` | 授权是否对应宿主最终 `applicationId`，包括渠道或 debug 后缀；AppID/AppSecret 是否匹配 |
| 扫描不到钥匙 | 蓝牙/权限/旧系统定位服务是否开启；扫描前缀是否匹配；广播名是否为空；设备是否正在被其他手机占用；`neverForLocation` 是否影响目标广播 |
| 已连接但无法开锁 | 是否使用 READER 模式；是否收到有效心跳、锁芯连接值是否为 1；参数是否与当前锁芯匹配 |
| KY53E 返回 `UNSUPPORTED_DEVICE` | 是否误调用普通 `unlockWithSecretKey`；如果来自 A3 响应，再查解密结果及钥匙/锁芯固件兼容性 |
| A3 失败但钥匙信息/版本可读 | 明文读取成功不代表锁侧加密参数正确；核对 `lockEncryptMode`、本次锁侧 `smSecret`、密码、随机码和响应 |
| 偶发失败、回调归属错乱或队列长时间等待 | 是否在心跳内反复发命令、重复点击、多页面并发、混用两个 Manager；先串行业务并记录完整时序 |
| 仅显示数字 `11`，无法判断原因 | 必须同时记录回调类型、枚举名/错误描述和库版本；两套错误码的 `11` 含义不同，见前文错误码说明 |
| 超时后不确定锁是否打开 | 不自动重试；保留现场，恢复连接后读取状态或人工确认实际结果 |

### 现场日志最小信息

提交问题时，提供一次完整失败过程，不要只截取最后一行错误：

1. 宿主包名、App 版本、三个 AAR 的完整文件名/版本/校验值、手机型号、Android 版本和进程 ABI。
2. 钥匙型号、设备名、钥匙固件版本、目标锁芯型号/SN、锁芯固件版本，以及是否只发生在某一钥匙或锁芯组合。
3. 调用的入口方法、当前 `MkdLockTypeEnum`、时间顺序、是否重复点击/切换页面。
4. 最近心跳的锁芯连接状态、锁状态、钥匙侧/锁侧加密模式，以及 A1/A3 请求与响应日志。
5. 完整失败回调：`MkdLockResult.name()`、`getKey()`、`getValue()`，或电子钥匙 listener 的 `code + error`；JNI 异常另附完整栈。

SDK 当前日志可能包含协议明文载荷（其中可能有密码或授权数据），不能把 `MkdLog.DEBUG = false` 当作统一关闭日志的开关：当前 `MkdLog` 的输出方法未检查该字段。采集和共享前必须脱敏，不要在公开日志中附带完整密码、密钥、授权节点或其他敏感身份信息。

### AAR 供应方交付清单

发布给第三方前，建议随包提供：

- 配套的三个 AAR（或明确注明已合并范围的单 AAR）、版本清单及每个文件的 SHA-256。
- 本 README、目标设备/固件支持范围、业务凭证及密钥获取方式；真实凭证通过安全渠道单独交付。
- 外部 Maven 依赖清单、ABI 支持范围、JNI/consumer rules 和 SO 去重说明。
- 如需离线接入，应另行提供经许可可分发的外部依赖及离线仓库方案，不能承诺仅三个 AAR 就能完全离线解析所有 Maven 依赖。
- 实际发布包的验证记录：权限、扫描/连接、心跳、锁芯热插拔、开关锁、读版本、断线/超时恢复、混淆后的 release 安装包，以及适用设备上的 native/16 KB 页兼容性。

**本文档的示例仅做了源码接口与文本静态核对，未执行编译、构建、打包或真机验证。实际交付 AAR、宿主编译与真机运行由 SDK 供应方和接入方自行验证；文档中的配置不等于验证报告。**

## 版本记录

##### 文档更新（2026-10-30，未变更 SDK 代码）

- 按当前源码版本 `1.7.19` 核对基本信息，补充第三方 AAR 依赖、ABI、Manifest、权限、JNI 和混淆接入说明。
- 增加电子钥匙接口速查、两侧密钥/参数规则、完整 KY53E Java 示例及常用异步业务示例；纠正通用读基本信息接口对 KY53E 的支持范围和页面资源清理说明。
- 补充两套错误码的区别、现场日志和 AAR 交付检查清单；明确尚未编译、打包及真机验证。

##### V1.7.17
- 普通锁开锁、关锁统一使用 `unlockWithSecretKey(password, smSecret, listener)` / `lockWithSecretKey(password, smSecret, listener)`；二参重载标记为弃用兼容，并仅以 `smSecret=null` 转发。
- Android 测试页面普通锁开锁、关锁统一传入“锁 SM 密码”输入值；电子钥匙专用开关锁入口保持不变。

##### V1.7.16
- `PL56N/FL23N` 状态查询改用专用命令读取 Page16~Page19，新增 `randomHex`（Page16 4 字节随机数）字段；手机 NFC 仅对 17 字节且首字节为 `00` 的响应去前导字节。
- 新增 `unlockWithSecretKey(password, smSecret, listener)` / `lockWithSecretKey(password, smSecret, listener)` 重载：按状态中的通信加密方式路由，mode 0 走原明文流程（可不传 `smSecret`），mode 1 AES128、mode 2 GM128/SM4 走 Block5 安全流程。
- 新增 `configLockCloseThreshold(password, thresholdMv, smSecret, listener)`（Block5 业务动作 `0x11`），仅 mode 1/2 支持，mode 0 返回 `UNSUPPORTED_DEVICE`。
- Block5 安全流程：16 字节密文按 Page20~Page23 逐 page 写入（每 page 4 字节），初始等待 500ms 后最多轮询 25 次响应并解密校验；手机 NFC 与 BLE 读写器共用同一路由结果。
- mode 1/2 加解密通过 JNI `NativeLib` 完成（AES128 / SM4），锁侧 `smSecret` 必须为 16 字节 hex，否则返回 `PasswordError`。

##### V1.7.15
- 调整 CL01/FL 系列/PL56N 关锁前置状态判断：`lockStatus` 为 `"0"` 或 `"2"` 时允许关锁。

##### V1.7.14
- 更新电子钥匙离线授权协议组包。

##### V1.7.13
- 更新电子钥匙心跳协议，扩展心跳实体字段。

##### V1.7.12
- `MkdLockLib` 读写器模式集成 KY53E/KY53N 电子钥匙业务能力。
- KY53E 连接后不自动开启读写器寻卡。
- KY 设备发送读写器命令和电子钥匙命令时串行写入，收到完整响应帧或主动心跳帧后继续发送下一条；普通读写器设备保持直接发送。
- KY53E 统一开关锁接口仍返回 `UNSUPPORTED_DEVICE`，电子钥匙协议开关锁使用 `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)`。
- 电子钥匙钥匙侧加解密通过 `setElectronicKeySmSecret(...)` 设置 `smSecret`，加密方式由心跳缓存决定；KY53E A3 开关锁和阈值配置仍显式传入锁侧 `smSecret`。
- `CL01/FL23N/PL56N` 查询状态新增 MCU 启动检测：最多 25 次、每次间隔 200ms，NFC 电量变化后返回，否则返回 `MCU_START_FAILED`。
- `PL56N/FL23N` 查询状态新增通信加密方式、传感器配置和参数状态字段，太阳能电量和电池电量固定返回 `"0"`。
