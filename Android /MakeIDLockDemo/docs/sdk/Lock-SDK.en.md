> SDK接口资料快照，非本Demo已完成全部功能的说明。运行/交付状态以工程根README为准。

# MkdLockLib Android SDK Integration and API Guide

[English](Lock-SDK.en.md) | [简体中文](Lock-SDK.zh.md)

`MkdLockLib` is MakeID's unified smart lock SDK, exposed through `MkdLockManagerNewer`. It supports NFC, BLE readers, direct BLE connections, and USB. Applications select a transport using `MkdLockTypeEnum`, then call unified APIs to read serial numbers, status, battery levels, firmware versions, and network settings, or to unlock and lock devices. This guide focuses on integrating KY53E/KY53N electronic keys through AAR distribution.

## SDK Information

- Module: `MkdLockLib`
- Package: `com.makeid.lock_2`
- Current source version: `1.7.19` (the actual AAR delivery manifest takes precedence)
- Minimum Android API level: `minSdk 21`
- Main entry point: `MkdLockManagerNewer.getInstance()`
- Common callbacks: `MkdLockManagerListener`, `MkdLockManagerProgressListener`
- Required modules: `MkdBLEConnectLib`, `MkdElectronicKeyLib`
- Documentation reviewed on: `2026-10-30`
- Example verification: statically checked against the current public APIs; not compiled, packaged, or verified on a physical device

## Related Documents

The linked technical documents below are currently available in Chinese.

- NFC Unlocking Protocol（原SDK技术附录，需向供应方索取） (Chinese): common NFC lock protocol, plus Page16-Page23, Block5, and threshold configuration for `PL56N/FL23N`.
- Current FL23N APIs（原SDK技术附录，需向供应方索取） (Chinese): current Android implementations of `FL23N/PL56N` status reads, MCU startup detection, encryption mode routing, and lock/unlock APIs.
- Charging After Encrypted PL56N / FL23N Operations（原SDK技术附录，需向供应方索取） (Chinese): in modes `1/2`, charging continues after Block5 returns `M0=0`; lock/unlock or threshold success is reported only after the charge level reaches the required threshold.
- iOS FL23N / PL56N NFC Integration（原SDK技术附录，需向供应方索取） (Chinese): Core NFC commands, random-number and lock-side `smSecret` caching, mode `0/1/2` lock/unlock, and electronic key BLE `0x0B` tone synchronization.
- Electronic Key 0x0B Tone Synchronization（原SDK技术附录，需向供应方索取） (Chinese): BLE frames, heartbeat encryption modes, and key-side `smSecret` rules for KY53E/KY53N tones and LEDs.
- Unified smSecret Lock/Unlock APIs（原SDK技术附录，需向供应方索取） (Chinese): three-argument APIs for ordinary locks, deprecated two-argument overloads, and test tool migration.

## Third-Party Integration Guide (AAR Distribution)

This guide is for native Android developers receiving AAR files. Examples use **Java + Groovy Gradle**. Integrators should access electronic keys through `MkdLockManagerNewer`, without directly initializing or operating `MkdElectronicKeyManager`. Later sections also document NFC, ordinary readers, BLE locks, and USB locks.

### Navigation

- [AAR Setup and Dependencies](#aar-setup-and-dependencies)
- [Manifest and Runtime Permissions](#manifest-and-runtime-permissions)
- [Initialization and Integration Sequence](#initialization-and-integration-sequence)
- [Electronic Key API Reference](#electronic-key-api-reference)
- [Parameters and Keys](#parameters-and-keys)
- [Complete KY53E Integration Example](#complete-ky53e-integration-example)
- [Common Operation Examples](#common-operation-examples)
- [Electronic Key Extension APIs](#electronic-key-extension-apis)
- [Common Error Codes](#common-error-codes)
- [Integration Troubleshooting and Delivery Checklist](#integration-troubleshooting-and-delivery-checklist)

### AAR Setup and Dependencies

#### 1. Delivery Files

**The current source uses ordinary module dependencies, not a single AAR with dependencies embedded.** Both internal libraries use `implementation project(...)` in `MkdLockLib/build.gradle`; `embed` is not enabled. Copying only `MkdLockLib.aar` is therefore insufficient for this version.

Place all three matching AARs from the same delivery in the host application's `app/libs/` directory. The filenames below have been normalized for this example. Actual filenames may contain version or date suffixes; dependency paths must match the delivered filenames.

```text
app/
└── libs/
    ├── MkdLockLib.aar
    ├── MkdBLEConnectLib.aar
    └── MkdElectronicKeyLib.aar
```

| File | Purpose | Current Source Version |
| --- | --- | --- |
| `MkdLockLib.aar` | Unified manager, electronic key adapter, NFC/reader operations, and authentication JNI | `1.7.19` |
| `MkdBLEConnectLib.aar` | BLE scanning, connections, and data transport; provides `Device` | `1.1` |
| `MkdElectronicKeyLib.aar` | Electronic key protocols, models, callbacks, and cryptographic JNI | `1.0.2` |

> Use the matching versions supplied together. Do not mix older AARs/JARs or include the same module twice. If a future delivery is a genuinely merged AAR, follow that delivery's manifest and do not add embedded modules again. This guide does not claim that the current SDK is distributed as one self-contained AAR.

#### 2. Maven Repositories

Merge these repositories into the host project's existing `settings.gradle` configuration; do not duplicate the entire configuration block:

```groovy
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' } // XXPermissions
    }
}
```

#### 3. App Module Dependencies

Add the following to `app/build.gradle`:

```groovy
android {
    // This example uses compileSdk 34, matching the current SDK source. A compatible higher version is also acceptable.
    compileSdk 34

    defaultConfig {
        minSdk 21
        // The electronic key module currently targets arm64-v8a only; this example targets physical 64-bit ARM devices.
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
            // Both business AARs include OpenSSL. Deduplicate only after confirming that the delivered SO files are identical.
            pickFirsts += ['**/libcrypto_1_1.so', '**/libssl_1_1.so']
        }
    }
}

dependencies {
    implementation files('libs/MkdLockLib.aar')
    implementation files('libs/MkdBLEConnectLib.aar')
    implementation files('libs/MkdElectronicKeyLib.aar')

    // Local AARs do not include Maven POM metadata; declare these external dependencies explicitly.
    // These versions match the current MkdLockLib source configuration, not necessarily the latest dependency releases.
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.10.0'
    implementation 'io.reactivex.rxjava2:rxjava:2.2.10'
    implementation 'io.reactivex.rxjava2:rxandroid:2.1.1'
    implementation 'com.github.getActivity:XXPermissions:18.5'
}
```

If the host already uses these libraries, manage compatible versions centrally instead of declaring them twice. Do not combine `files(...)` above with a `fileTree(...)` that includes the same files. The source project's `implementation project(':MkdLockLib')` is not an AAR integration method for third-party applications.

#### 4. ABI, JNI, and Obfuscation

- `MkdLockLib` currently configures `arm64-v8a` and `armeabi-v7a`, but `MkdElectronicKeyLib` configures only `arm64-v8a`. **The common ABI for the complete electronic key stack is currently `arm64-v8a`.** A 32-bit library in one AAR does not imply 32-bit support across the SDK.
- The current delivery configuration does not support validating the complete JNI stack on x86/x86_64 emulators. The supplier must provide a complete, matching set of artifacts for 32-bit support.
- JNI dependencies include `libnfclock.so`, `libmkdelectronickeylib.so`, and the OpenSSL shared libraries. Do not remove files under `jni/` from the AARs or simply exclude duplicated OpenSSL libraries.
- The arm64 OpenSSL files in both source modules are currently identical. Still verify the files inside the final delivered AARs. If versions differ, do not blindly apply `pickFirst`; ask the supplier to align the dependencies first.
- AAR consumers do not need to copy the SDK's CMake/NDK configuration or compile native source. SO completeness and 16 KB page compatibility must be verified separately against the actual delivery artifacts.

The `MkdLockLib` consumer rules already preserve the authentication JNI class. The current `MkdElectronicKeyLib` consumer rules are empty. If the host enables R8/ProGuard, start with these conservative rules in `app/proguard-rules.pro`, then narrow them based on actual usage:

```proguard
-keep class com.makeid.nfclock.AlgorithmHelper { *; }
-keep class com.makeid.mkdelectronickeylib.** { *; }
-keep class com.makeid.lock_2.** { *; }
-keep class com.makeid.blelibrary.** { *; }
```

### Manifest and Runtime Permissions

For an application using only electronic key BLE features, declare permissions and optional hardware features as below. Permissions from the AARs are also merged: inspect the final **Merged Manifest**, not just the App's own Manifest.

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
    <!-- This example does not derive physical location from BLE scans. -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

    <uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
    <!-- The SDK Manifest declares USB host support; a BLE-only host can make it optional. -->
    <uses-feature android:name="android.hardware.usb.host"
        android:required="false" tools:replace="android:required" />
    <uses-feature android:name="android.hardware.nfc" android:required="false" />

    <application android:name=".DemoApplication">
        <!-- Layout-free demo Activity, launched internally; uses the Java example's package. -->
        <activity android:name=".ElectronicKeyDemoActivity" android:exported="false" />
    </application>
</manifest>
```

- Android 12/API 31 and later: this example assumes `targetSdk >= 31` and requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime.
- Android 6-11/API 23-30: request location permissions at runtime and enable system location services. Android 5/API 21-22 does not show runtime permission dialogs.
- Use `neverForLocation` only if scan results are not used to derive physical location. This flag can filter some BLE advertisements, so verify it with the target devices. If your application uses location, design permissions for that actual use instead of copying the no-location declaration.
- This BLE unlocking example does not require camera, media, or all-files-access permissions. Using an App-readable `File` for OTA does not inherently require all-files access.
- The SDK's existing `checkPermissionAndRequest(...)` helper requests a broad set of permissions, including camera, location, and storage. It is **not the minimum BLE permission set**. With this configuration, request permissions yourself as in the example below; do not also call that helper.
- The current AAR Manifest includes extra storage and media permissions. For a BLE-only host, assess whether unused `MANAGE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `READ_MEDIA_IMAGES`, and `NFC` permissions can be removed with `tools:node="remove"`. Do not remove permissions required by other SDK features.

### Initialization and Integration Sequence

1. Give the supplier the host's actual `applicationId` and obtain an `appID` and `appSecret` authorized for that package. The SDK AppID is not the Android `applicationId`.
2. Call `initWithAppID(...)` with an `Application`. If it returns `false`, stop further SDK operations.
3. Switch to `MKD_LOCK_TYPE_READER`. **Do not use the reserved `MKD_LOCK_TYPE_ELECTRONIC_KEY` value, or select `MKD_LOCK_TYPE_BLE` merely because the device connects over BLE.**
4. Obtain runtime permissions and ensure Bluetooth is enabled. Older Android versions also require location services to be enabled.
5. Register a heartbeat listener, set scan prefixes, scan, and connect the user-selected key. Stop scanning before connecting to avoid duplicate connection attempts.
6. Wait for a valid heartbeat. A successful BLE connection does not mean a lock cylinder is connected. Before unlocking, verify `lockCylinderState == 1`, the lock cylinder's identity, and the business authorization.
7. Retrieve the **key-side** secret from your backend using the device name, then call `setElectronicKeySmSecret(...)`. Retrieve the lock-side secret for the current target lock separately; do not interchange them.
8. Call the appropriate lock/unlock API and handle success, failure, and progress. Finish one operation before starting another. Do not repeatedly trigger unlocking from periodic heartbeats.
9. On page/session exit, stop scanning, remove listeners, and disconnect. Call `release()` only when shutting down all SDK-related operations.

> The SDK uses process-wide singletons and shared callback state. Multiple pages must not switch modes or control devices concurrently. Do not mix `MkdLockManagerNewer` and `MkdElectronicKeyManager` in one KY session, or run unlock, status, and OTA operations concurrently. An internal send queue does not imply support for concurrent business transactions.

### Electronic Key API Reference

All methods below belong to `com.makeid.lock_2.MkdLockManagerNewer`. The table lists method names and parameters. Return types are `void` unless otherwise noted. Callback types are in `com.makeid.lock_2.listener` or `com.makeid.mkdelectronickeylib.listener`.

| API | Purpose / Callback |
| --- | --- |
| `initWithAppID(String appID, String appSecret, Application application)` | Authenticate; returns `boolean` synchronously |
| `isInit()` | Returns `boolean`: authentication state |
| `changeCurrentLockType(MkdLockTypeEnum type)` | Select `MKD_LOCK_TYPE_READER` for electronic keys |
| `setDeviceScanPrefix(String... prefix)` | Filter by device-name prefix, e.g. `"KY53E", "KY53N"` |
| `startScan(int timeOut, MkdScanListener listener)` / `stopScan()` | Start/stop scanning; `timeOut` is in milliseconds |
| `connectDevice(Device device, MkdBleConnectListener listener)` | Connect a scanned device; a `String` device-address overload is also available |
| `isBleDeviceConnect()` / `disConnectDevice()` | Return `boolean` connection state / disconnect |
| `setOnElectronicKeyHeartBeatListener(OnHeartBeatListener listener)` | Listen for unsolicited heartbeats; pass `null` to remove the application listener |
| `sendElectronicKeyHeart(String id, OnHeartBeatListener listener)` | Compatibility API: currently only sets the listener; does not send a heartbeat request |
| `setElectronicKeySmSecret(String smSecret)` | Set the 16-byte key-side secret as 32 hex characters |
| `setElectronicKeyCrypto(int encryptMode, String key)` | Retained explicit configuration API; use heartbeat negotiation for normal integration |
| `readElectronicKeyInfo(String id, OnReadElectKeyInfoListener listener)` | Read key information; returns `ElectronicKeyInfo` on success |
| `syncElectronicKeyTime(long timestamp, OnSyncTimeListener listener)` | Synchronize a Unix timestamp, in seconds |
| `syncElectronicKeyTone(ElectronicKeyToneType type, OnSyncElectronicKeyToneListener listener)` | Tone/LED synchronization; callback occurs when the write is submitted, not when device execution is confirmed |
| `readLockBasicInfoSuccess(MkdLockManagerListener listener)` | KY53N: read lock cylinder `sn` / `mac` from a valid heartbeat. KY53E currently returns unsupported; use heartbeat data or `A1` instead |
| `readElectronicKeyLockSN(String id, OnReadSerialNoListener listener)` | Read lock cylinder information using `A1`; returns `LockInfo` |
| `readElectronicKeyLockState(String id, OnReadLockStateListener listener)` | Plaintext read: KY53E `A4` / KY53N `A7`; returns `LockStateEntity` |
| `readElectronicKeyLockProtocolVersion(OnReadLockProtocolVersionListener listener)` | Plaintext `A9` read; returns `LockProtocolVersionInfo` |
| `readElectronicKeyLockFirmwareVersion(OnReadLockFirmwareVersionListener listener)` | Plaintext `A6` read; returns `LockFirmwareVersionInfo`; no `smSecret` required |
| `unlockElectronicKeyWithSecretKey(String uid, String password, String smSecret, MkdLockManagerProgressListener listener)` | Unlock using the electronic key protocol. KY53E uses `A1 → A3`; `smSecret` is the lock-side secret |
| `lockElectronicKeyWithSecretKey(String uid, String password, String smSecret, MkdLockManagerProgressListener listener)` | Lock using the electronic key protocol; same secret rules as above |
| `unlockWithSecretKey(String password, String smSecret, MkdLockManagerProgressListener listener)` / `lockWithSecretKey(...)` | Ordinary lock/reader passthrough APIs; unsupported on KY53E; KY53N uses the NFC reader flow |
| `configElectronicKeyCloseThreshold(String uid, String password, int thresholdMv, String smSecret, OnConfigCloseThresholdListener listener)` | KY53E `A1 → A3(action=0x11)`; lock-side secret; threshold in mV |
| `readElectronicKeyCacheLog(String id, OnReadCacheLogListener listener)` / `clearElectronicKeyCacheLog(String id, OnClearCacheLogListener listener)` | Read/clear cached key logs using the configured key-side secret |
| `sendElectronicKeyOfflineAuth(AuthNode node, String smSecret, OnSendOfflineAuthListener listener)` | Send offline authorization; `smSecret` is the key-side secret |
| `queryElectronicKeyOfflineAuth(int nid, String smSecret, OnManageOfflineAuthListener listener)` | Query one offline authorization |
| `queryAllElectronicKeyOfflineAuth(String smSecret, OnManageOfflineAuthListener listener)` | Query all offline authorizations; handle multi-packet progress and the final list |
| `deleteElectronicKeyOfflineAuth(int nid, String smSecret, OnManageOfflineAuthListener listener)` / `deleteAllElectronicKeyOfflineAuth(String smSecret, OnManageOfflineAuthListener listener)` | Delete one/all offline authorizations |
| `exchangeElectronicKey(String id, OnExchangeKeyListener listener)` | Compatibility key exchange; also supports `(id, smSecret, listener)`; not a prerequisite for current lock/unlock flows |
| `rebootElectronicKey(String id, OnRebootKeyListener listener)` | Reboot the key; the connection may close after submission |
| `upgradeElectronicKeyFirmware(File file, OnOtaUpgradeListener listener)` | OTA using the key-side context; do not issue other operations during the upgrade |
| `removeScanListener()` / `releaseAllConnection()` / `release()` | Remove scan listener / release BLE connections / shut down all SDK-related operations |

Offline authorization APIs also retain overloads without `smSecret`; these use the previously configured key-side secret. See the Electronic Key Extension APIs section for more parameters and callback examples.

#### Callbacks and Operation Completion

- `MkdLockManagerListener`: `onSuccess(Map<String, String>)` / `onFailed(MkdLockResult)`.
- `MkdLockManagerProgressListener` additionally provides `onChargeProgress(int)`. Progress reaching 100 does not replace the success callback.
- Electronic key listeners return typed models or boolean results. For example, `onSyncTime(false, timestamp)` itself reports a failed operation; implementing only `onSyncTimeError(...)` is insufficient.
- For multi-packet log reads and offline authorization queries, wait for the corresponding `on...Finish(...)` callback. A progress or single-packet callback does not mean the entire operation is complete.
- Callbacks are not guaranteed to run on the main thread. Do not block inside a callback while waiting for another SDK callback. Dispatch UI updates and application state changes to the main thread.
- Success Map semantics vary by operation. Electronic key protocol lock/unlock currently returns `isOpen` (the string `"true"` / `"false"`) and `lockStatus`. In this path, `lockStatus` is always `"1"`; **do not interpret it as the live lock state**. For actual status, read a subsequent heartbeat or call a status API.
- `MkdLockResult` may be `null` in some legacy failure paths. Check for null before logging or updating the UI. Dedicated listener error numbers are described later; do not mix them with the unified enum.

### Parameters and Keys

| Parameter | Format and Source | Notes |
| --- | --- | --- |
| `appID` / `appSecret` | Issued by the supplier for the host package | Neither the lock password nor a device secret; do not log them |
| `uid` / `id` | User/operation identifier assigned by your business system; encoded as UTF-8 in a fixed field | Common request fields are 16 bytes, zero-padded or truncated. Use an ASCII identifier of at most 16 bytes. This is not the BLE MAC address; do not assume the device name is a substitute |
| `password` | Lock password as a hex string, without `0x`, spaces, or separators | KY53E `A3` uses the first 4 bytes. Have your backend supply exactly 8 hex characters; do not pass unencoded display text |
| `keySmSecret` | Key-side secret: 16 bytes / 32 hex characters | Retrieve by key identity and configure through `setElectronicKeySmSecret`; used for key-side encryption in time, log, offline authorization, tone, and OTA operations |
| `lockSmSecret` | Lock-side secret: 16 bytes / 32 hex characters | Retrieve by lock cylinder identity and pass explicitly for each KY53E unlock/lock/threshold operation; no fallback to a global lock-side cache |
| `timestampSeconds` | Unix timestamp in seconds | Use `System.currentTimeMillis() / 1000L`, not milliseconds |
| `thresholdMv` | Integer in mV, encoded in a 16-bit field | Use the device's supplier-confirmed valid range, not arbitrary values merely because they fit in the field |
| `firmwareFile` | App-readable firmware `File` compatible with the target hardware | Your application must validate the source, supported model, and integrity first |

**Do not confuse the two encryption modes:** heartbeat `electronicKeyEncryptMode` is key-side; `lockEncryptMode` is lock-side. `1` means AES128 and `2` means GM128/SM4. `KY53E A3` uses the lock-side mode and secret. The `KY53N A5` electronic key protocol uses the key-side mode and secret. When KY53N operates through the ordinary reader APIs, the target lock's NFC protocol applies; do not apply the A5 key-side rules to that path.

Secret strings in this README illustrate formats only and are not production keys. Never hardcode production secrets or real passwords into examples, repositories, or logs. Match retrieved credentials to the current key and lock cylinder; do not use a previous lock's parameters for the next lock.

### Complete KY53E Integration Example

The two Java classes below use `com.example.keydemo`. Replace it with your package and update the Manifest accordingly. This layout-free example demonstrates permissions, scanning, connections, heartbeats, manual lock/unlock, and cleanup. **It does not automatically unlock devices.** The host application supplies UI buttons and backend key retrieval.

#### 1. Authenticate in Application

If the host already has a custom `Application`, merge the initialization into it instead of registering another `Application`. Replace the example credentials with actual supplier-issued values. Do not expose production configuration in source code.

```java
package com.example.keydemo;

import android.app.Application;
import com.makeid.lock_2.MkdLockManagerNewer;

public final class DemoApplication extends Application {
    @Override
    public void onCreate() {
        super.onCreate();
        boolean ok = MkdLockManagerNewer.getInstance().initWithAppID(
                "REPLACE_WITH_SUPPLIER_ISSUED_APP_ID",
                "REPLACE_WITH_SUPPLIER_ISSUED_APP_SECRET",
                this);
        // The page checks isInit(); do not issue business commands if authentication failed.
        if (!ok) {
            android.util.Log.e("KeyDemo", "SDK authentication failed; check applicationId and credentials");
        }
    }
}
```

#### 2. Scan, Connect, and Operate Manually in Activity

The example connects only to the preselected `KY53E26G0022`. A real application should display scan results and let the user select a key, then validate its bound identity rather than trusting only its advertised name. All application state is managed on the main thread. Bind lock/unlock buttons to `operateLock(...)`; never call it from a heartbeat callback.

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
            show("SDK is not authenticated; integration stopped");
            finish();
            return;
        }
        sdk.changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);
        sdk.setOnElectronicKeyHeartBeatListener(new OnHeartBeatListener() {
            @Override
            public void onHeartBeat(HeartEntity heart) {
                // Always post to manage state on the main thread and avoid synchronous reentry from SDK callbacks.
                main.post(() -> {
                    if (closed || !sdk.isBleDeviceConnect()) return;
                    latestHeart = heart;
                    show(heart != null && heart.getLockCylinderState() == 1
                            ? "Lock cylinder connected; verify identity before manual operation" : "Waiting for lock cylinder");
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
            show("Permission request cancelled");
            return;
        }
        for (int result : grantResults) {
            if (result != PackageManager.PERMISSION_GRANTED) {
                show("Permission denied; grant access in Settings and reopen this page");
                return;
            }
        }
        startScan();
    }

    private void startScan() {
        // Prompt the user to enable Bluetooth first; Android 6-11 also requires location services.
        sdk.setDeviceScanPrefix("KY53E");
        sdk.startScan(10_000, new MkdScanListener() {
            @Override public void onScanStart() { show("Scan started"); }
            @Override public void onScanStop() { show("Scan stopped"); }
            @Override public void onScanError(String msg) { show("Scan failed: " + msg); }

            @Override
            public void onScanResult(Device device, boolean isConnectedBySys) {
                main.post(() -> {
                    if (closed || connecting || sdk.isBleDeviceConnect()) return;
                    if (device == null || !TARGET_NAME.equals(device.getName())) return;
                    connecting = true; // Set first to prevent duplicate advertisements from triggering multiple connects.
                    latestHeart = null;
                    final int currentSession = ++session;
                    sdk.stopScan();
                    sdk.connectDevice(device, new MkdBleConnectListener() {
                        @Override
                        public void connectSuccess(Device connectedDevice) {
                            main.post(() -> {
                                if (closed || currentSession != session) return;
                                connecting = false;
                                show("BLE connected; wait for a heartbeat before assuming the lock cylinder is connected");
                            });
                        }
                        @Override
                        public void connectFailed(String msg) {
                            main.post(() -> {
                                if (closed || currentSession != session) return;
                                connecting = false;
                                latestHeart = null;
                                show("Connection failed: " + msg);
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
                                show("Disconnected; obtain a new heartbeat and matching secrets after reconnecting");
                            });
                        }
                    });
                });
            }
        });
    }

    // Call on the main thread after retrieving the secret for the current key; do not pass a lock-side secret.
    public void configureKeySecret(String keySmSecret) {
        if (closed || !sdk.isBleDeviceConnect() || latestHeart == null) {
            show("Connect and wait for a heartbeat first");
            return;
        }
        if (keySmSecret == null || !keySmSecret.matches("[0-9a-fA-F]{32}")) {
            show("Invalid key-side secret format");
            return;
        }
        sdk.setElectronicKeySmSecret(keySmSecret);
    }

    // Call on the main thread only after an explicit user action; obtain parameters from backend authorization.
    // open=true unlocks; open=false locks. expectedLockSn identifies the authorized target cylinder.
    public void operateLock(boolean open, String uid, String expectedLockSn,
                            String passwordHex, String lockSmSecret) {
        if (closed || busy || !sdk.isBleDeviceConnect()) {
            show("Not connected, or a previous operation is still pending");
            return;
        }
        if (latestHeart == null || latestHeart.getLockCylinderState() != 1
                || expectedLockSn == null || expectedLockSn.isEmpty()
                || !expectedLockSn.equals(latestHeart.getLockSN())) {
            show("Lock cylinder is not ready or does not match the authorized target");
            return;
        }
        if (uid == null || !uid.matches("[\\x20-\\x7E]{1,16}")
                || passwordHex == null || !passwordHex.matches("[0-9a-fA-F]{8}")
                || lockSmSecret == null || !lockSmSecret.matches("[0-9a-fA-F]{32}")) {
            show("Invalid operation ID, lock password, or lock-side secret format");
            return;
        }
        busy = true;
        final int currentSession = session;
        // 30 seconds is this example's application timeout, not an SDK protocol deadline or cancellation API.
        operationTimeout = () -> {
            ++session; // Ignore late business callbacks from this session.
            latestHeart = null;
            connecting = false;
            finishOperation();
            sdk.disConnectDevice();
            show("Timed out and disconnected; result unknown. Verify lock state; do not retry automatically");
        };
        main.postDelayed(operationTimeout, 30_000);
        MkdLockManagerProgressListener listener = new MkdLockManagerProgressListener() {
            @Override public void onChargeProgress(int progress) {
                show("Progress: " + progress + "% (not final confirmation)");
            }
            @Override public void onFailed(MkdLockResult result) {
                main.post(() -> {
                    if (closed || currentSession != session) return;
                    finishOperation();
                    show(result == null ? "Operation failed: unknown error"
                            : "Operation failed: " + result.name() + "/" + result.getKey()
                                    + "/" + result.getValue());
                });
            }
            @Override public void onSuccess(Map<String, String> data) {
                main.post(() -> {
                    if (closed || currentSession != session) return;
                    finishOperation();
                    show(open ? "Unlock succeeded" : "Lock succeeded");
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
        // Real UI updates must run on the main thread; this example logs only secret-free operation status.
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
        // Do not release the global singleton when an ordinary page is destroyed; other SDK users may be active.
        super.onDestroy();
    }
}
```

The host button flow is: authorize through the backend → verify the current key name and heartbeat lock cylinder SN → obtain `uid`, `passwordHex`, and `lockSmSecret` → call `operateLock(true, uid, expectedLockSn, passwordHex, lockSmSecret)` after the user's click. Pass `false` to lock. `configureKeySecret(keySmSecret)` configures key-side operations; it does not replace the lock-side secret explicitly passed to each A3 operation.

This example assumes a single page owns the session; the user reopens the page to reconnect after disconnection. Production applications must also handle foreground/background lifecycle, heartbeat freshness, permission revocation, connection timeouts, recovery, and authorization expiry. After a timeout or disconnection, the device may have executed the command without the App receiving confirmation. Read status again or verify on site; do not automatically resend an unlock command.

### Common Operation Examples

Call these examples only after authentication, a READER connection, and a valid heartbeat. **Run each example independently, not concurrently.** Import models from `com.makeid.mkdelectronickeylib.entity` and callbacks from `com.makeid.mkdelectronickeylib.listener`.

#### Read Lock Cylinder Firmware Version (No Secret Required)

```java
import com.makeid.lock_2.MkdLockManagerNewer;
import com.makeid.mkdelectronickeylib.entity.LockFirmwareVersionInfo;
import com.makeid.mkdelectronickeylib.listener.OnReadLockFirmwareVersionListener;

// Place this call inside an Activity or business-layer method:
MkdLockManagerNewer.getInstance().readElectronicKeyLockFirmwareVersion(
        new OnReadLockFirmwareVersionListener() {
            @Override
            public void onReadLockFirmwareVersion(LockFirmwareVersionInfo info) {
                if (info == null) return;
                String productionDate = info.getProductionDate();
                String firmwareVersion = info.getFirmwareVersion();
                String hardwareVersion = info.getHardwareVersion();
                // Dispatch to the main thread to display results, or report them to your backend for compatibility checks.
            }
            @Override
            public void onReadLockFirmwareVersionError(int code, String error) {
                android.util.Log.e("KeyDemo", "A6 read failed: " + code + "/" + error);
            }
        });
```

#### Synchronize Time (Key-Side Secret)

```java
import com.makeid.mkdelectronickeylib.listener.OnSyncTimeListener;

// keySmSecret is the 32-character hex secret retrieved for the current key from your backend.
MkdLockManagerNewer.getInstance().setElectronicKeySmSecret(keySmSecret);
MkdLockManagerNewer.getInstance().syncElectronicKeyTime(
        System.currentTimeMillis() / 1000L,
        new OnSyncTimeListener() {
            @Override
            public void onSyncTime(boolean success, long timestamp) {
                android.util.Log.i("KeyDemo", "Time synchronization result: " + success);
            }
            @Override
            public void onSyncTimeError(int code, String error) {
                android.util.Log.e("KeyDemo", "Time synchronization failed: " + code + "/" + error);
            }
        });
```

#### Query All Offline Authorizations (Multi-Packet Callbacks)

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
                // A single-packet result; this does not mean the entire query has finished.
            }
            @Override
            public void onManageOfflineAuthProgress(int current, int total) {
                android.util.Log.i("KeyDemo", "Authorization query progress: " + current + "/" + total);
            }
            @Override
            public void onManageOfflineAuthFinish(List<AuthNode> authNodes) {
                // Final list. AuthNode contains sensitive fields; do not serialize it directly into logs.
                android.util.Log.i("KeyDemo", "Authorization query completed; count: " + authNodes.size());
            }
            @Override
            public void onManageOfflineAuthError(int code, String error) {
                android.util.Log.e("KeyDemo", "Authorization query failed: " + code + "/" + error);
            }
        });
```

#### Unlock Through Ordinary Reader Passthrough on KY53N

KY53N supports ordinary NFC reader passthrough. Wait until a card/lock is found, then prepare the password and lock-side secret for that lock model. The following is the call site; implement `progressListener` as shown under Callbacks. This is not the KY53E unlocking API.

```java
// READER mode selected, KY53N connected, target lock found, and backend authorization completed.
MkdLockManagerNewer.getInstance().unlockWithSecretKey(
        passwordHex, lockSmSecret, progressListener);
```

Do not use this API to bypass a KY53E unsupported-operation error. KY53E must use `unlockElectronicKeyWithSecretKey(...)` as in the complete example.

## Initialization

Authenticate and initialize the SDK before calling any lock operation API.

```java
boolean success = MkdLockManagerNewer.getInstance()
        .initWithAppID(APP_ID, APP_SECRET, application);

if (!success) {
    // Authentication failed; subsequent business APIs return MkdLockResult.AuthenticationFail.
}
```

After successful initialization, the SDK creates an NFC lock instance by default. To use BLE, USB, or a reader, call `changeCurrentLockType(...)` to select the appropriate type.

## Permission Requests

BLE, scanning codes, and storage features may require Android runtime permissions. NFC uses a normal Manifest permission. The SDK's built-in helper requests a broad set of camera, location, Bluetooth, and storage permissions. Third-party applications using only electronic key BLE features should request the minimum required permissions themselves, as described under Manifest and Runtime Permissions. The following helper is not mandatory for BLE unlocking.

```java
MkdLockManagerNewer.getInstance().checkPermissionAndRequest(context, new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        // result == MkdLockResult.PERMISSION_ERROR
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // Permissions granted.
    }
});
```

## Switching Lock Types

`MkdLockTypeEnum` defines the values below. `MkdLockLib` currently implements NFC, BLE readers, direct BLE, and USB. Electronic key features are integrated into reader mode:

| Type | Description |
| --- | --- |
| `MKD_LOCK_TYPE_NFC` | Operate locks directly through the phone's NFC interface |
| `MKD_LOCK_TYPE_READER` | Operate locks through a BLE NFC reader; supports ordinary readers, KY53N reader passthrough, and KY53E/KY53N electronic key extensions |
| `MKD_LOCK_TYPE_BLE` | Connect the phone directly to a BLE lock |
| `MKD_LOCK_TYPE_USB` | Operate locks over USB |
| `MKD_LOCK_TYPE_ELECTRONIC_KEY` | Reserved enum value, not a separate implemented lock type; switch to `MKD_LOCK_TYPE_READER` and call the `ElectronicKey` methods on `MkdLockManagerNewer` |

Example:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);
```

After switching, serial number, status, lock/unlock, and other calls are routed through the selected implementation.

## Callbacks

Ordinary operations use `MkdLockManagerListener`:

```java
new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        String msg = result == null ? "" : result.getValue();
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // Success data is returned in the map.
    }
}
```

Operations with charging progress use `MkdLockManagerProgressListener`:

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

Note: SDK callbacks are not guaranteed to run on the main thread. Switch to the main thread before updating Views.

## BLE Scanning and Connections

### Set Scan Prefixes

```java
MkdLockManagerNewer.getInstance().setDeviceScanPrefix("LOCK-", "OTHER_PREFIX");
```

### Scan for Devices

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
        // Save device for a subsequent connectDevice(device, listener) call.
    }

    @Override
    public void onScanError(String errorMsg) {
    }
});
```

Stop scanning:

```java
MkdLockManagerNewer.getInstance().stopScan();
```

### Connect a BLE Device

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

You can also connect using a device identifier string:

```java
MkdLockManagerNewer.getInstance().connectDevice(deviceAddress, listener);
```

Connection state:

```java
boolean connected = MkdLockManagerNewer.getInstance().isBleDeviceConnect();
```

Disconnect or release connections:

```java
MkdLockManagerNewer.getInstance().disConnectDevice();
MkdLockManagerNewer.getInstance().releaseAllConnection();
```

## NFC Connections

For direct phone NFC access, select the lock type and connect a `Tag`:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_NFC);

MkdLockManagerNewer.getInstance().connectTag(tag, status -> {
    if (status) {
        // NFC connected.
    } else {
        // NFC disconnected or connection failed.
    }
});
```

NFC helper APIs:

```java
boolean supportNfc = MkdLockManagerNewer.getInstance().isSupportNFC(context);
boolean nfcOpen = MkdLockManagerNewer.getInstance().isNFCOpen(context);

MkdLockManagerNewer.getInstance().createPendingIntent(activity);
MkdLockManagerNewer.getInstance().enableForegroundDispatch(activity);
MkdLockManagerNewer.getInstance().disableForegroundDispatch(activity);
```

## Unified Lock Operation APIs

The following methods are routed to the NFC, reader, BLE, or USB implementation according to the current `MkdLockTypeEnum`.

### Read Basic Lock Information

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

Common response fields:

| Field | Description |
| --- | --- |
| `sn` | Lock serial number or AX lock identifier |
| `mac` | Lock MAC address; may be empty for some models |
| `isSupportNewProtocol` | Whether the NFC lock supports the new protocol; not returned by all models |

### Read Lock Status and Battery Levels

```java
MkdLockManagerNewer.getInstance().readStatusAndElectricity(listener);
```

Common response fields:

| Field | Description |
| --- | --- |
| `lockStatus` | Lock status; meanings may differ between models |
| `nfcElectricity` | NFC supply voltage, in mV |
| `solarEnergyElectricity` | Solar supply voltage, in mV |
| `batteryElectricity` | Battery voltage in mV, or the protocol-defined value |
| `temperature` | Temperature; returned by some models |
| `randomHex` | 4-byte random number from Page16 on `PL56N/FL23N` |
| `communicationEncryptionMode` | Communication encryption on `PL56N/FL23N`: `0` unencrypted, `1` AES128, `2` GM128 |
| `communicationEncryptionModeName` | Encryption mode name: `NONE` / `AES128` / `GM128` / `UNKNOWN` |
| `sensorConfig` | Raw sensor configuration; returned by `PL56N/FL23N` |
| `doorMagneticHall` | Door magnetic Hall sensor configuration on `PL56N/FL23N`: `0` absent, `1` present |
| `parameterStatus` | Raw parameter status; returned by `PL56N/FL23N` |
| `unlockCodeStatus` | Unlock-code configuration on `PL56N/FL23N`: `0` not configured, `1` configured |
| `communicationKeyStatus` | Communication-key configuration on `PL56N/FL23N`: `0` not configured, `1` configured |
| `hall1ReferenceDiffStatus` | Hall 1 reference-difference configuration on `PL56N/FL23N`: `0` not configured, `1` configured |
| `lockBeamStatus` | Lock shackle status; returned by telecom-operator BLE locks |
| `lockTypeC` | Type-C connection status; returned by telecom-operator BLE locks |
| `lockBle` | BLE connection status; returned by telecom-operator BLE locks |
| `lockShackleCondition` | Mechanical lock state; returned by some NFC locks |
| `birth` | Production date; returned by some BLE locks |

### Status Handling for New-Protocol Locks

`CL01`, `FL23N`, and `PL56N` are currently treated as new-protocol locks. When `readStatusAndElectricity(...)` is called through phone NFC or a BLE NFC reader, the SDK first checks MCU startup by reading status repeatedly:

- At most `25` reads.
- `200ms` between reads.
- Startup is detected by a change in the NFC supply voltage.
- Once the voltage changes, the status from that read is returned immediately.
- If no change is detected after the maximum number of reads, the SDK returns `MkdLockResult.MCU_START_FAILED`.
- Legacy-protocol models do not use this polling logic; their original single-read behavior is retained.

`PL56N/FL23N` use a dedicated command to read Page16-Page19 starting at Page16 while retaining compatible response fields:

| Field | Current Parsing |
| --- | --- |
| `randomHex` | `response[0..3]`: 4-byte Page16 random number |
| Page17 | `response[4..7]`: currently ignored |
| `nfcElectricity` | `response[8..9]`, big-endian, in mV |
| `lockStatus` | `response[10] & 0xff` |
| `temperature` | `response[11]`, with the most significant bit as the sign bit |
| `communicationEncryptionMode` | `response[12] & 0xff` |
| `communicationEncryptionModeName` | `0=NONE`, `1=AES128`, `2=GM128`; otherwise `UNKNOWN` |
| `sensorConfig` | `response[13] & 0xff` |
| `doorMagneticHall` | `sensorConfig bit0` |
| `parameterStatus` | `response[14] & 0xff` |
| `unlockCodeStatus` | `parameterStatus bit0` |
| `communicationKeyStatus` | `parameterStatus bit1` |
| `hall1ReferenceDiffStatus` | `parameterStatus bit2` |
| `solarEnergyElectricity` | Always returns `"0"` |
| `batteryElectricity` | Always returns `"0"` |

Notes:

- No additional public status API is introduced. Internally, these models use the dedicated Page16 command; other models retain the Page18 status command.
- Phone NFC removes a leading byte only when the response is 17 bytes and starts with `00`. BLE reader security responses do not undergo this normalization.
- Other models do not return extension fields such as `communicationEncryptionMode`, `sensorConfig`, and `parameterStatus`. Check field presence before displaying them.

### Read Unlock Count

```java
MkdLockManagerNewer.getInstance().readUnlockTimes(listener);
```

Success response:

| Field | Description |
| --- | --- |
| `unlockTimes` | Number of unlock operations |

### Read Firmware Version

```java
MkdLockManagerNewer.getInstance().readFWVersion(listener);
```

Success response:

| Field | Description |
| --- | --- |
| `version` | Firmware version |
| `hardwareVersion` | Hardware version; returned by some BLE locks |

### Unlock

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
        // Unlock succeeded.
    }
});
```

Notes:

- For ordinary locks, use the three-argument `unlockWithSecretKey(password, lockSmSecret, listener)` API. Pass `null` for models that do not use a lock-side SM secret.
- The two-argument `unlockWithSecretKey(password, listener)` overload is deprecated and retained for compatibility only. On `PL56N/FL23N` modes 1/2, it fails because no lock-side `smSecret` is supplied.
- NFC locks may require charging; progress is reported through `onChargeProgress`.
- New-protocol models such as `CL01/FL23N/PL56N` wait for MCU startup during status reads. If the NFC supply voltage does not change within 25 reads, the SDK returns `MkdLockResult.MCU_START_FAILED`.
- `PL56N/FL23N` select the flow using `communicationEncryptionMode` in the final status: mode 0 (unencrypted) uses the legacy plaintext flow and allows an empty `lockSmSecret`; mode 1 uses AES128; mode 2 uses GM128/SM4. Both encrypted modes use the lock-side `smSecret` (16 bytes, represented by 32 hex characters).
- Modes 1/2 require a valid lock-side `smSecret`, otherwise `MkdLockResult.PasswordError` is returned. An unknown mode returns `MkdLockResult.CheckStatusFail`; there is no plaintext fallback.
- Modes 1/2 use the Block5 security flow: write the 16-byte ciphertext page by page to Page20-Page23 (4 bytes per page), wait 500ms initially, then poll the response up to 25 times. Success is reported after decryption and validation pass.
- Phone NFC accepts a 17-byte Block5 response starting with `00` by removing that leading byte. BLE readers validate a 16-byte response without this normalization.
- BLE AX locks use the AX unlocking protocol with the previously read or supplied password.
- In reader mode, KY53N and ordinary readers unlock through NFC reader passthrough. KY53E returns `MkdLockResult.UNSUPPORTED_DEVICE` for this unified API.
- Incorrect passwords typically return `MkdLockResult.PasswordError` or `MkdLockResult.VerifyPwdFail`, depending on the model.

### Lock

```java
MkdLockManagerNewer.getInstance().lockWithSecretKey(
        password, lockSmSecret, progressListener);
```

Notes:

- For ordinary locks, use the three-argument `lockWithSecretKey(password, lockSmSecret, listener)` API. Pass `null` for models that do not use a lock-side SM secret.
- The two-argument `lockWithSecretKey(password, listener)` overload is deprecated and retained for compatibility only.
- Locking support depends on the current model.
- Before locking `PL56N/FL23N`, the SDK checks the current state. Only `lockStatus` values `"0"` or `"2"` allow locking; otherwise it returns `MkdLockResult.LOCK_STATUS_NOT_SUPPORT_OPERATION`.
- `PL56N/FL23N` mode 0 does not validate the lock-side `smSecret`. Modes 1/2 require a 16-byte hex `smSecret` and use the same security flow as unlocking: page-by-page Block5 writes plus polling and decryption of responses.
- In reader mode, KY53N and ordinary readers lock through NFC reader passthrough. KY53E returns `MkdLockResult.UNSUPPORTED_DEVICE` for this unified API.
- Failures may return `MkdLockResult.CheckLockStatusFail`, `MkdLockResult.PasswordError`, or other errors.

### Configure the PL56N/FL23N Closing Threshold

```java
MkdLockManagerNewer.getInstance().configLockCloseThreshold(
        password, thresholdMv, lockSmSecret, new OnConfigCloseThresholdListener() {
    @Override
    public void onConfigCloseThreshold(boolean isSuccess, int thresholdMv) {
        // Configuration result and the threshold used for this operation.
    }

    @Override
    public void onError(int code, String error) {
        // Failure; code corresponds to MkdLockResult.getKey().
    }
});
```

Notes:

- `OnConfigCloseThresholdListener` is in `com.makeid.mkdelectronickeylib.listener` (`MkdElectronicKeyLib`).
- Only `PL56N/FL23N` support this API. Other models return `UNSUPPORTED_DEVICE` through `onError`.
- This API uses Block5 action `0x11` and supports modes 1/2 only. Mode 0 returns `UNSUPPORTED_DEVICE` without writing Page20-Page23.
- Before execution, the SDK performs MCU startup detection, reads Page16-Page19, and selects the flow by mode.
- Modes 1/2 require a valid lock-side `smSecret` (16-byte hex), otherwise `PasswordError` is returned. The security flow matches lock/unlock: page-by-page writes followed by polling and decryption of responses.
- The SDK does not enforce a business-specific range for `thresholdMv`; the protocol encodes it as two big-endian bytes.

### Reset Lock State

```java
MkdLockManagerNewer.getInstance().resetLock(password, progressListener);
```

Possible success fields:

| Field | Description |
| --- | --- |
| `lockStatus` | Lock state after reset |
| `reset` | Reset result flag; returned by some models |

## Reader APIs

Switch to reader mode:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);
```

After a BLE reader connects, card/lock discovery depends on its model:

- Ordinary readers and KY53N: discovery starts automatically after connection.
- KY53E: discovery does not start automatically; only electronic key operations are used.

Register a discovery callback:

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

Query reader status:

```java
MkdLockManagerNewer.getInstance().queryBleReaderWriterStatus(listener);
```

Common response fields:

| Field | Description |
| --- | --- |
| `rwPowerMV` | Reader battery voltage, in mV |
| `rwPowerPercent` | Reader battery percentage |
| `rwHW` | Reader hardware version |
| `rwSW` | Reader firmware version |

Set the NFC protocol:

```java
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.DEFAULT.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_14443_A.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_14443_B.getValue());
MkdLockManagerNewer.getInstance().setNfcProtocolEnum(NFCProtocolEnum.ISO_15693.getValue());
```

### KY Device Send Queue

Ordinary readers continue to send BLE commands directly. For a connected KY53E or KY53N, `MkdLockLib` serializes reader commands and electronic key commands:

- Only one command is written at a time.
- The next command is sent after a complete `0x70`, `0x71`, or `0x73` frame is received.
- Unsolicited KY heartbeat frames also count as complete responses and release the queue.
- The `0x0B` tone synchronization command does not wait for a device response. Success is reported immediately after submitting the write; it does not leave the queue waiting for a response.
- Disconnecting, reconnecting, or releasing resources clears the pending send queue.

## Electronic Key Extension APIs

Electronic key features are accessed through reader mode. Switch to reader mode and connect a KY53E or KY53N before use:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_READER);

MkdLockManagerNewer.getInstance().connectDevice(device, connectListener);
```

Device capabilities:

| Device | Lock/Unlock | Electronic Key Features |
| --- | --- | --- |
| KY53E | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` return `UNSUPPORTED_DEVICE`; use `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)` | Supported |
| KY53N | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` use NFC reader passthrough | Supported |
| Ordinary reader/YS | `unlockWithSecretKey(...)` / `lockWithSecretKey(...)` use NFC reader passthrough | Not supported |

### Heartbeat Listener

KY devices report heartbeats automatically. Register a listener and wait for reports. `sendElectronicKeyHeart(...)` currently only sets a listener; it does not send a heartbeat command.

The current heartbeat payload is 32 bytes of plaintext, parsed directly by the SDK. It contains key status, lock cylinder connection state, lock state, lock cylinder `SN` / `MAC`, the key's internal time, and key-side/lock-side encryption modes.

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

`HeartEntity` fields:

| Field | Description |
| --- | --- |
| `electronicKeyBattery` | Key battery percentage, `0-100` |
| `electronicKeyState` | Internal key state: `0` normal, `1` charging |
| `lockCylinderState` | Lock cylinder connection state: `0` disconnected, `1` connected |
| `lockState` | Lock state: `0` unavailable, `1` unlocked, `2` locked |
| `lockSN` | Lock cylinder SN, from plaintext heartbeat bytes `M4-M15` |
| `lockMac` | Lock cylinder MAC, from plaintext bytes `M16-M24`; this 9-byte field still uses a length prefix followed by MAC data |
| `electronicKeyTimeSec` | Key internal Unix timestamp, in seconds, from plaintext bytes `M25-M28` |
| `electronicKeyEncryptMode` | Key-side encryption mode: `1` AES128, `2` GM128 |
| `lockEncryptMode` | Lock-side encryption mode: `1` AES128, `2` GM128 |
| `reserve` | Reserved heartbeat byte, plaintext `M31` |

Additional notes:

- `lockSN` / `lockMac` may be empty if no lock cylinder is connected.
- Unsolicited KY heartbeat frames also signal completion to the send queue, allowing the next queued KY command to be sent.
- Keep a `setOnElectronicKeyHeartBeatListener(...)` listener registered to track lock cylinder connection changes in real time.
- For legacy short heartbeat packets, the SDK still parses the basic fields; new fields default to `0`.
- After the first valid heartbeat, retrieve the **key-side** `smSecret` using the key's BLE name and set it in the SDK, regardless of whether the heartbeat indicates `AES128` or `GM128`. The SDK automatically caches the encryption mode from heartbeats.

### Read Lock Cylinder SN / MAC from Heartbeat

In `MKD_LOCK_TYPE_READER` mode with a connected **KY53N**, the unified basic-information API returns the lock cylinder `SN` and `MAC` from the latest heartbeat. **KY53E currently returns `UNSUPPORTED_DEVICE` for this generic API.** For KY53E, read `getLockSN()` / `getLockMac()` from `OnHeartBeatListener`, or call `readElectronicKeyLockSN(uid, listener)` to read A1 information. The following generic example applies to KY53N:

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

Notes:

- This flow requires a heartbeat reporting that a lock cylinder is connected.
- If no valid heartbeat has arrived, or it contains no lock cylinder `SN`, the API reports the corresponding failure.
- `mac` is the heartbeat's lock cylinder `MAC`, formatted as uppercase hex without separators.

### Electronic Key Information, Time, and Lock State

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

Notes:

- `uid` is the electronic key business identifier. The test tool typically reads it from local configuration or an input field.
- `setElectronicKeySmSecret(...)` sets the **key-side** `smSecret`. Subsequent APIs such as `0x05 / 0x07 / 0x09 / 0x0A / 0xA5 / 0x10 / 0x11` use the encryption mode cached from the latest heartbeat automatically.
- Automatic handling means selecting `AES128` or `GM128` only. If an API uses key-side encryption/decryption, a valid key-side `smSecret` must already be configured in either mode.
- `setElectronicKeyCrypto(...)` is retained for explicit overrides. Normal integration does not need to set the encryption mode manually.
- `exchangeElectronicKey(...)` is retained primarily for compatibility. It is no longer a prerequisite for `KY53E / KY53N` lock/unlock operations.
- `readElectronicKeyLockSN(...)` requires a connected lock cylinder; otherwise it reports a lock-not-connected error.
- `readElectronicKeyLockState(...)` currently uses plaintext: `A4` for `KY53E`, `A7` for `KY53N`.
- `readElectronicKeyLockProtocolVersion(...)` uses plaintext `A9` and returns the lock protocol type, version, and related information.
- `readElectronicKeyLockFirmwareVersion(...)` uses plaintext `A6` and returns production date, firmware version, and hardware version for the lock cylinder. It does not require `smSecret`.
- Devices other than KY53E/KY53N report unsupported or connection failures through the corresponding electronic key listener.

### Synchronize Electronic Key Tones or LED State

```java
MkdLockManagerNewer.getInstance().syncElectronicKeyTone(
        ElectronicKeyToneType.LOCK_ON_TONE,
        new OnSyncElectronicKeyToneListener() {
            @Override
            public void onSyncElectronicKeyTone(boolean isSuccess,
                                                 ElectronicKeyToneType toneType) {
                // Command submitted to the BLE write request.
            }

            @Override
            public void onSyncElectronicKeyToneError(int code, String message) {
                // Invalid parameters, connection state, or cryptographic context.
            }
        });
```

Notes:

- Supported only when the connected device is `KY53E` or `KY53N`.
- Uses electronic key command `0x0B`. The command byte is plaintext; its 16-byte payload (`M0` plus fifteen `0x00` bytes) is encrypted using the key-side heartbeat-negotiated mode and current key-side `smSecret`.
- The device does not reply to `0x0B`. The SDK calls `onSyncElectronicKeyTone(true, toneType)` after submitting the BLE write. Success does not confirm that a tone played, an LED lit, or device execution completed.
- SDK authentication, BLE connection, electronic key state, and key-side cryptographic context are still checked before sending. Failures are reported through `onSyncElectronicKeyToneError(...)`.
- `ElectronicKeyToneType` supports tones `0x01-0x07`, LED states `0x08-0x10`, BLE connection states `0x11/0x12`, and lock/unlock results and timeout indications `0x13-0x16`.

### KY53E Electronic Key Lock/Unlock

KY53E does not enable reader-passthrough lock/unlock. Use these APIs to operate through the electronic key protocol:

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

Requirements:

- `password` is the lock password as a hex string.
- `lockSmSecret` is the **lock-side** `smSecret` and must be passed explicitly.
- A3 fails immediately if no lock-side `smSecret` is supplied.
- The current main flow is `A1 -> A3` and no longer depends on `A2`.
- The SDK checks the BLE connection, lock cylinder connection, and password format before proceeding.

To configure the `KY53E` closing Hall threshold:

```java
MkdLockManagerNewer.getInstance().configElectronicKeyCloseThreshold(
        uid,
        password,
        thresholdMv,
        lockSmSecret,
        listener);
```

Here, too, `lockSmSecret` means the **lock-side** `smSecret`.

### Cached Logs

```java
MkdLockManagerNewer.getInstance().readElectronicKeyCacheLog(uid, new OnReadCacheLogListener() {
    @Override
    public void onReadCacheLog(List<LogNode> logNodes) {
        // Full log list.
    }

    @Override
    public void onReadCacheLogProgress(int length) {
        // Number of log entries received in this batch.
    }

    @Override
    public void onReadCacheLogFinish() {
        // Reading finished.
    }

    @Override
    public void onReadCacheLogError(int code, String error) {
    }
});

MkdLockManagerNewer.getInstance().clearElectronicKeyCacheLog(uid, clearCacheLogListener);
```

### Offline Authorization

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

Distinguish these parameters:

- `keySmSecret` in these APIs is the **key-side** `smSecret`, used to encrypt/decrypt `0x09 / 0x0A` traffic.
- `authNode.lockSmSecret` is the **lock-side** `smSecret` contained in the authorization payload.
- If the key-side `smSecret` has already been configured through `setElectronicKeySmSecret(...)`, you may use overloads without an explicit `smSecret`.

`queryAllElectronicKeyOfflineAuth(...)` is a multi-packet flow. Track progress through `OnManageOfflineAuthListener.onManageOfflineAuthProgress(current, total)` and obtain the final list through `onManageOfflineAuthFinish(List<AuthNode> authNodes)`.

### OTA Upgrade

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

## Telecom-Operator BLE/USB Lock APIs

Switch to BLE or USB:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);

MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_USB);
```

Read and configure the idle timeout:

```java
MkdLockManagerNewer.getInstance().readIdleTime(listener);
MkdLockManagerNewer.getInstance().writeIdleTime(60, listener);
```

Successful idle-time reads return:

| Field | Description |
| --- | --- |
| `idleTime` | Idle timeout, in seconds |

Restart or enter sleep immediately:

```java
MkdLockManagerNewer.getInstance().operateReset(listener);
MkdLockManagerNewer.getInstance().operateSleep(listener);
```

Register lock-state reports:

```java
MkdLockManagerNewer.getInstance().regisMkdLockReportListener(new MkdLockManagerListener() {
    @Override
    public void onFailed(MkdLockResult result) {
        // Report failure or an unlocked state.
    }

    @Override
    public void onSuccess(Map<String, String> map) {
        // Lock-closed report received.
    }
});
```

Unregister:

```java
MkdLockManagerNewer.getInstance().unRegisMkdLockReportListener();
```

Monitor USB operation:

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

## AX BLE Lock APIs

AX locks are identified by the BLE name prefix `LOCK-` and use direct phone BLE mode:

```java
MkdLockManagerNewer.getInstance()
        .changeCurrentLockType(MkdLockTypeEnum.MKD_LOCK_TYPE_BLE);
```

### Read the AX Lock Password

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

Success response:

| Field | Description |
| --- | --- |
| `password` | AX lock password as a hex string |

### Configure AX Network Parameters

```java
MkdLockManagerNewer.getInstance()
        .setAXNetworkParameter("120.24.1.1", 1883, listener);
```

### Read AX Network Parameters

```java
MkdLockManagerNewer.getInstance().readAXNetworkParameter(listener);
```

Both successful configuration and read operations return:

| Field | Description |
| --- | --- |
| `ip` | Primary reporting IP address |
| `port` | Primary reporting port |

### Configure AX APN Parameters

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

### Read AX APN Parameters

```java
MkdLockManagerNewer.getInstance().readAXApnParameter(listener);
```

Both successful configuration and read operations return:

| Field | Description |
| --- | --- |
| `apnName` | APN name |
| `apn` | APN |
| `userName` | Username |
| `userPsw` | Password |
| `authType` | Authentication type |
| `apnType` | APN type |
| `apnRever1` | Reserved field |

Note: each AX APN protocol field is exactly 32 bytes. Short values are zero-padded by the underlying implementation.

## NFC Network APIs

Some NFC locks support reading network status, device parameters, MQTT passwords, and SIM identifiers.

```java
MkdLockManagerNewer.getInstance().resetNetwork(listener);
MkdLockManagerNewer.getInstance().readNetworkStatus(listener);
MkdLockManagerNewer.getInstance().readDeviceParameter(listener);
MkdLockManagerNewer.getInstance().readMQTTPassword(listener);
MkdLockManagerNewer.getInstance().readSimCardNumber(listener);
```

Common response fields:

| API | Field | Description |
| --- | --- | --- |
| `readNetworkStatus` | `status` | Network status |
| `readNetworkStatus` | `pw` | Network signal strength |
| `readDeviceParameter` | `defaultReconnectInterval` | Default reconnection interval |
| `readDeviceParameter` | `defaultKeepAliveTime` | Default keep-alive interval |
| `readMQTTPassword` | `password` | MQTT password |
| `readSimCardNumber` | `SimICCID` | SIM ICCID |

## Factory and Debugging APIs

The following APIs are generally intended for factory testing or debugging.

```java
MkdLockManagerNewer.getInstance().readMCUStatus(5, listener);
MkdLockManagerNewer.getInstance().readSensorStatus(listener);
MkdLockManagerNewer.getInstance().readNfcLockRunLog(listener);
MkdLockManagerNewer.getInstance().getSystemClockTime(listener);
```

Common response fields:

| API | Field | Description |
| --- | --- | --- |
| `readMCUStatus` | `mcu_status` | Raw MCU status data |
| `readSensorStatus` | `open` | Door state |
| `readSensorStatus` | `localStatus` | Lock bolt state |
| `readNfcLockRunLog` | `defaultServerAddress` | Whether the default server address is used |
| `readNfcLockRunLog` | `lastNetWorkSuccess` | Whether the last network request succeeded |
| `readNfcLockRunLog` | `lastNetWorkFailATCode` | AT command associated with the last failed network request |
| `getSystemClockTime` | `time` | Time elapsed since system boot |

## Resource Cleanup

When leaving an ordinary BLE page, call `stopScan()`, `removeScanListener()`, `setOnElectronicKeyHeartBeatListener(null)`, and `disConnectDevice()`, as in the complete example. Use `release()` only when all SDK-related operations are shutting down. Initialize successfully first, and ensure no other page is using the shared singleton:

```java
if (MkdLockManagerNewer.getInstance().isInit()) {
    MkdLockManagerNewer.getInstance().release();
}
```

`release()` is not an operation-cancellation API and does not guarantee a reusable, reset-to-initial state. Before using the SDK again, rebuild the session through the full initialization and connection sequence.

## Common Error Codes

Unified lock operations report `MkdLockResult` through `MkdLockManagerListener.onFailed(...)` / `MkdLockManagerProgressListener.onFailed(...)`. Dedicated electronic key listeners use their own operation error codes in `on...Error(int, String)` / `onFail(int, String)`; do not interpret all of them using `MkdLockResult`. Log the entry method, callback type, enum name, numeric code, and description together.

Common `MkdLockResult` values:

| Enum | `getKey()` | Description |
| --- | --- | --- |
| `AuthenticationFail` | `0` | SDK authentication failed |
| `ConnectFail` | `1` | NFC connection failed |
| `WriteDataFail` | `2` | NFC write failed |
| `ChargePowerFail` | `3` | Charging failed |
| `VerifyPwdFail` | `4` | Password verification failed |
| `CheckStatusFail` | `5` | Lock state validation failed; also used for electronic key lock-side context/response errors |
| `PasswordError` | `7` | Incorrect password; some encrypted flows also use this for invalid secret format/parameters |
| `BLENoConnect` | `9` | No BLE device connected |
| `SET_NFC_RES_TIME_OUT` | `11` | Defined as NFC module response timeout; do not use this meaning for the separate electronic key error-code set |
| `NEED_CONNECT_NFC` | `12` | Move closer to the NFC tag |
| `READ_NFC_DATA_FAIL` | `13` | NFC read failed |
| `MCU_START_FAILED` | `19` | New-protocol status read: no change in NFC supply voltage within 25 reads; MCU startup deemed unsuccessful |
| `TAG_LOST` | `25` | NFC tag lost |
| `PERMISSION_ERROR` | `27` | Permission request failed |
| `CheckLockStatusFail` | `28` | Lock-state validation before locking failed |
| `UNSUPPORTED_DEVICE` | `29` | API unsupported for the current device or lock type |
| `RESET_LOCK_STATUS_FAIL` | `30` | Lock-state reset failed |
| `LOCK_STATUS_NOT_SUPPORT_OPERATION` | `31` | Operation not allowed in the current lock state |
| `ELECTRONIC_KEY_NOT_CONNECT_LOCK` | `32` | Electronic key not connected to a lock cylinder |

Retrieve error details as follows:

```java
if (result != null) {
    String name = result.name();
    int code = result.getKey();
    String message = result.getValue();
    // Also log the entry method and callback type, not just the numeric code.
}
```

For dedicated electronic key errors, `MkdElectronicKeyMenu` defines `2` key connection failure, `3` invalid password format, `4` key exchange/cryptographic context error, `5` no lock connected, `6-10` OTA-related errors, and `11` unsupported device type. Some dedicated callbacks also return `MkdLockResult` numeric values or the parsing error `-1`. Interpret the code together with the API and description, not in isolation.

In particular, when an A3 response is parsed as `0xFF`, the current `MkdLockLib` lock/unlock progress callback reports `MkdLockResult.UNSUPPORTED_DEVICE` (`29`), whereas the underlying `MkdElectronicKeyLib` unlock callback reports `11`. Parsing depends on the correct decryption context. Check the complete response on site rather than concluding that a model is unsupported from the number alone.

## Important Notes

- Call `initWithAppID(...)` first; only issue other business calls after successful initialization.
- Call `changeCurrentLockType(...)` before switching between NFC, BLE reader, direct BLE, and USB modes.
- Ensure the device is connected before BLE/USB operations, and the `Tag` is connected before NFC operations.
- Use electronic key features in `MKD_LOCK_TYPE_READER` mode. Do not directly operate both `MkdElectronicKeyManager` and `MkdLockManagerNewer` in the same KY connection session.
- KY53E does not start reader discovery automatically after connection; KY53N and ordinary readers do.
- KY53E continues to return `UNSUPPORTED_DEVICE` for `unlockWithSecretKey(...)` / `lockWithSecretKey(...)`. Use `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)` instead.
- Reader and electronic key commands are serialized for KY53E/KY53N; ordinary readers retain direct sending.
- `CL01/FL23N/PL56N` status reads wait for MCU startup, detected through NFC voltage changes. Legacy-protocol models are unaffected.
- `PL56N/FL23N` do not provide solar or battery voltage values; `solarEnergyElectricity` and `batteryElectricity` always return `"0"`.
- Extended `PL56N/FL23N` status fields are returned only for these models. Do not append default separators or force empty fields into the UI for other models.
- `PL56N/FL23N` lock/unlock and closing-threshold flows depend on `communicationEncryptionMode` in lock status: mode 0 plaintext, mode 1 AES128, mode 2 GM128/SM4. Modes 1/2 require the lock-side `smSecret`; unknown modes do not fall back to plaintext.
- `configLockCloseThreshold(...)` (`0x11`) on `PL56N/FL23N` is available only in modes 1/2. Mode 0 returns `UNSUPPORTED_DEVICE`.
- AX-specific APIs apply only to AX locks whose BLE names start with `LOCK-`.
- SDK callback threads are not fixed. Switch to the main thread before updating the UI.
- This English guide does not localize the SDK itself. Runtime descriptions such as `MkdLockResult.getValue()` may still be in Chinese; use enum names and numeric codes for application-side localization.
- Response fields vary between lock models. Check `map.containsKey(...)` before reading optional fields.

## Integration Troubleshooting and Delivery Checklist

### Common Integration Problems

| Symptom | Check First |
| --- | --- |
| Cannot import `Device` or electronic key listeners/models | Ensure the matching BLE and ElectronicKey AARs are included; local AARs do not resolve internal module dependencies automatically |
| `NoClassDefFoundError` for RxJava, XXPermissions, etc. | Declare external dependencies explicitly; copying only AARs is insufficient |
| `Duplicate class` | Look for source modules plus AARs, multiple versions, or separately included libraries already embedded in a merged AAR |
| Duplicate OpenSSL libraries during JNI merging | Verify that both same-ABI SO files in the actual delivery are identical, then use the filename-specific `pickFirsts` configuration above |
| `UnsatisfiedLinkError` / missing native methods | Check ABI compatibility, complete JNI/OpenSSL libraries, and obfuscation of `NativeLib` / `AlgorithmHelper`. Preserve the full stack trace instead of logging only "initialization failed" |
| `initWithAppID(...) == false` | Ensure authorization matches the final host `applicationId`, including channel/debug suffixes, and that AppID/AppSecret match |
| No key found during scanning | Check Bluetooth, permissions, older-system location services, scan prefixes, empty device names, connections to other phones, and whether `neverForLocation` filters target advertisements |
| Connected but cannot unlock | Verify READER mode, a valid heartbeat, lock cylinder connection value 1, and credentials matching the current lock cylinder |
| KY53E returns `UNSUPPORTED_DEVICE` | Check for an accidental call to ordinary `unlockWithSecretKey`; if the error comes from A3, inspect decryption and key/lock firmware compatibility |
| A3 fails although key information/version reads succeed | Plaintext reads do not validate lock-side encryption parameters. Verify `lockEncryptMode`, the current lock-side `smSecret`, password, random number, and response |
| Intermittent failures, misrouted callbacks, or a stalled queue | Check repeated heartbeat-triggered commands, duplicate taps, concurrent pages, or mixed Managers. Serialize operations first and capture the complete sequence |
| Only the number `11` is displayed | Log callback type, enum name/error description, and library versions. The two error-code sets give `11` different meanings; see Common Error Codes |
| Unknown lock state after timeout | Do not retry automatically. Preserve evidence, reconnect and read status, or verify the physical result manually |

### Minimum On-Site Diagnostic Information

When reporting an issue, provide one complete failure sequence, not just the final error line:

1. Host package name, App version, full filenames/versions/checksums of all three AARs, phone model, Android version, and process ABI.
2. Key model/name/firmware, target lock cylinder model/SN/firmware, and whether the issue affects only a particular key/lock combination.
3. Entry method, current `MkdLockTypeEnum`, call order, and any repeated taps or page switches.
4. Latest heartbeat lock cylinder connection state, lock state, key-side/lock-side encryption modes, and A1/A3 request/response logs.
5. Complete failure callback: `MkdLockResult.name()`, `getKey()`, and `getValue()`, or the electronic key listener's `code + error`. Include full stack traces for JNI exceptions.

Current SDK logs may contain plaintext protocol payloads, including passwords or authorization data. `MkdLog.DEBUG = false` is not a global log-disable switch: the current `MkdLog` output methods do not check that field. Redact logs before collecting/sharing them; do not publish full passwords, secrets, authorization nodes, or other sensitive identity information.

### Supplier AAR Delivery Checklist

Before distributing the SDK to third parties, include:

- Three matching AARs (or a single AAR with its embedded scope clearly documented), version manifest, and SHA-256 for every file.
- This README, supported device/firmware matrix, and instructions for obtaining credentials and secrets. Deliver actual credentials separately through a secure channel.
- External Maven dependencies, supported ABIs, JNI/consumer rules, and SO deduplication instructions.
- If offline integration is required, separately provide externally licensed dependencies that may be redistributed and an offline repository plan. Do not promise that three AARs alone can resolve all Maven dependencies offline.
- Verification records for the actual release artifacts: permissions, scan/connect, heartbeats, lock cylinder insertion/removal, lock/unlock, version reads, disconnect/timeout recovery, an obfuscated release App, and native/16 KB page compatibility on applicable devices.

**Examples in this document have undergone source/API and text-level static checks only. They have not been compiled, built, packaged, or verified on a physical device. The supplier and integrator must verify the actual delivered AARs, host compilation, and physical-device behavior. Configuration examples are not verification reports.**

## Revision History

##### Documentation Update (2026-10-30; No SDK Code Changes)

- Reviewed SDK information against source version `1.7.19`; added third-party AAR dependencies, ABI, Manifest, permissions, JNI, and obfuscation guidance.
- Added the electronic key API reference, key-side/lock-side parameter rules, complete KY53E Java example, and common asynchronous examples. Corrected KY53E support for the generic basic-information API and page cleanup guidance.
- Clarified the two error-code sets, on-site diagnostics, and AAR delivery checks. Explicitly noted that compilation, packaging, and physical-device verification have not been performed.

##### V1.7.17
- Standardized ordinary lock operations on `unlockWithSecretKey(password, smSecret, listener)` / `lockWithSecretKey(password, smSecret, listener)`. Two-argument overloads are deprecated compatibility wrappers forwarding `smSecret=null`.
- Ordinary-lock operations in the Android test pages now consistently use the lock SM secret input. Dedicated electronic key entry points are unchanged.

##### V1.7.16
- `PL56N/FL23N` status queries now read Page16-Page19 through a dedicated command and return `randomHex` (the 4-byte Page16 random number). Phone NFC removes a leading byte only from 17-byte responses starting with `00`.
- Added `unlockWithSecretKey(password, smSecret, listener)` / `lockWithSecretKey(password, smSecret, listener)` overloads with routing by communication encryption mode: mode 0 retains plaintext and permits no `smSecret`; mode 1 AES128 and mode 2 GM128/SM4 use Block5 security.
- Added `configLockCloseThreshold(password, thresholdMv, smSecret, listener)` (Block5 action `0x11`), available in modes 1/2 only. Mode 0 returns `UNSUPPORTED_DEVICE`.
- Block5 security writes 16 ciphertext bytes page by page to Page20-Page23 (4 bytes per page), waits 500ms initially, then polls/decrypts/validates up to 25 responses. Phone NFC and BLE readers share the same mode-routing result.
- Modes 1/2 encrypt/decrypt through JNI `NativeLib` (AES128 / SM4). The lock-side `smSecret` must be 16-byte hex; otherwise `PasswordError` is returned.

##### V1.7.15
- Adjusted CL01/FL-series/PL56N pre-lock validation: `lockStatus` must be `"0"` or `"2"` to allow locking.

##### V1.7.14
- Updated electronic key offline authorization packet construction.

##### V1.7.13
- Updated electronic key heartbeat protocol and expanded heartbeat fields.

##### V1.7.12
- Integrated KY53E/KY53N electronic key operations into `MkdLockLib` reader mode.
- KY53E does not start reader discovery automatically after connection.
- Reader and electronic key commands are serialized for KY devices. A complete response or unsolicited heartbeat releases the next command; ordinary readers keep direct sending.
- KY53E still returns `UNSUPPORTED_DEVICE` for unified lock/unlock APIs. Use `unlockElectronicKeyWithSecretKey(...)` / `lockElectronicKeyWithSecretKey(...)` for electronic key protocol operations.
- Configure key-side encryption/decryption with `setElectronicKeySmSecret(...)`; the mode is cached from heartbeats. KY53E A3 lock/unlock and threshold operations still require an explicit lock-side `smSecret`.
- Added MCU startup detection for `CL01/FL23N/PL56N` status queries: up to 25 reads at 200ms intervals. A voltage change indicates startup; otherwise `MCU_START_FAILED` is returned.
- `PL56N/FL23N` status queries now return communication encryption, sensor configuration, and parameter status. Solar and battery voltage values always return `"0"`.
