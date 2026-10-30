# SDK User Guide

> Public entry: `MkdNFCLockLib/MkdLockLib/MkdLock.h`  
> Target devices: phone NFC locks, external NFC readers, standard Bluetooth locks, KY53E/KY53N electronic keys, and NB locks.

## 1. Integration and Initialization

After adding `MkdLockLib.framework` `MkdBLEConnectLib.framework`and  `MkdNFCReaderWriterLib.framework` to your project, import the header file:

```plain
#import <MkdLockLib/MkdLock.h>
```

The SDK is used through the `MkdLock` singleton. Authentication must be completed first; if authentication fails, operations such as locking/unlocking will fail with `UnlockFailStatusVerifyFail`.

```plain
MkdLock *lock = MkdLock.sharedInstance;
BOOL authorized = [lock initWithAppID:@"<AppID provided by sales>"
                            appSecret:@"<AppSecret provided by sales>"];
if (!authorized) {
    // Stop further operations and check the AppID, AppSecret, and Bundle ID configuration.
}

lock.isLog = YES;                 // Optional: enable SDK logging
lock.connectTimeout = 10;         // Optional: NFC Tag connection timeout, default 10 seconds
lock.unlockMethod = UnlockMethodNFC_Phone;
```

`appID` and `appSecret` are provided by the sales team based on the app's Bundle ID.

| Property                     | Access     | Description                                                                                               |
| ---------------------------- | ---------- | --------------------------------------------------------------------------------------------------------- |
| `version`                    | Read-only  | Current SDK version. Not declared read-only in the header; normally read-only, not recommended to modify. |
| `isLog`                      | Read/Write | Whether to output SDK logs.                                                                               |
| `connectTimeout`             | Read/Write | NFC Tag connection timeout in seconds, default `10`.                                                      |
| `unlockMethod`               | Read/Write | Current connection/unlock mode, see the table below.                                                      |
| `isBLEConnected`             | Read-only  | Current Bluetooth connection status; normally maintained by the SDK on connect/disconnect.                |
| `isNFCConnected`             | Read-only  | Connection status between the external reader and the NFC Tag.                                            |
| `electronicKeyDeviceType`    | Read-only  | Current electronic key type: unknown, KY53E, or KY53N.                                                    |
| `connectedElectronicKeyName` | Read-only  | Bluetooth name of the currently connected electronic key; `nil` when not connected.                       |

### 1.1 Connection Modes

| `unlockMethod`          | Applicable Scenario                               | Prerequisites                                                                                                 |
| ----------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `UnlockMethodNFC_Phone` | iPhone reads an NFC lock directly                 | The system NFC scanning UI pops up when a lock operation is invoked; the device must support NFC.             |
| `UnlockMethodNFC_BLE`   | External NFC reader or KY53E/KY53N electronic key | Scan and connect via Bluetooth first, and make sure the reader has found the Tag (`isNFCConnected` is `YES`). |
| `UnlockMethodBLELock`   | Standard Bluetooth lock                           | Scan and connect via Bluetooth first; no NFC Tag is used.                                                     |

Do not switch `unlockMethod` in the middle of an incomplete lock operation. The Bluetooth connection state is maintained by the SDK in `isBLEConnected`; `isNFCConnected` only reflects the link between the external reader and the NFC Tag.

Values of `electronicKeyDeviceType`: `MkdElectronicKeyDeviceTypeUnknown (0)` means not an electronic key or not yet identified, `MkdElectronicKeyDeviceTypeKY53E (1)` means KY53E, `MkdElectronicKeyDeviceTypeKY53N (2)` means a KY53N/reader combo device.

### 1.2 Common Callback Types

| Type                              | Signature                        | Description                                                                                                                                       |
| --------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Success callback                  | `SuccessCallback`                | `void (^)(id _Nullable obj)`; the return value varies by API.                                                                                     |
| General failure callback          | `FailureCallback`                | `void (^)(NSString * _Nullable errMsg)`.                                                                                                          |
| Lock/unlock failure callback      | `UnlockFailCallback`             | `void (^)(UnlockFailStatus status, NSString * _Nullable errMsg)`.                                                                                 |
| Search callback                   | `SearchDeviceCallback`           | `void (^)(CBPeripheral *peripheral, NSNumber *RSSI)`.                                                                                             |
| Normal callback                   | `NormalCallback`                 | `void (^)(id response)`, used for Bluetooth connection, scan completion, etc.                                                                     |
| BLE lock active report callback   | `BLELockActiveReportCallback`    | `void (^)(MkdBLELockActiveReport *report)`.                                                                                                       |
| Electronic key heartbeat callback | `ElectronicKeyHeartBeatCallback` | `void (^)(MkdElectronicKeyHeartBeat *heartBeat)`.                                                                                                 |
| Progress callback                 | `ElectronicKeyProgressCallback`  | `void (^)(CGFloat progress)`. In the cached-log scenario it is the number of entries read so far; in the OTA scenario it is the upgrade progress. |
| Phone NFC session callback        | `PhoneNFCSessionEventCallback`   | `void (^)(PhoneNFCSessionEvent event, NSError * _Nullable error)`.                                                                                |

## 2. Phone NFC Session

By default, the standard phone NFC APIs manage the system session themselves. If your business needs to keep the system NFC dialog open across multiple reads/writes, explicitly create a session and close it when the flow ends.

```plain
lock.unlockMethod = UnlockMethodNFC_Phone;
[lock beginPhoneNFCSessionSuccess:^(id tag) {
    [lock setPhoneNFCSessionMessage:@"Please keep the phone close to the lock"];
    [lock readLockBasicInfoSuccess:^(MkdLockBasicInfo *info) {
        NSLog(@"SN: %@", info.sn);
        [lock closePhoneNFCSessionWithMessage:@"Reading complete"];
    } failure:^(NSString *error) {
        [lock invalidatePhoneNFCSessionWithMessage:error];
    }];
} failure:^(NSString *error) {
    NSLog(@"NFC connection failed: %@", error);
}];
```

| API                                     | Description                                                                                                                                        |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `beginPhoneNFCSessionSuccess:failure:`  | Opens the system NFC session and connects the Tag; once successful, subsequent phone NFC APIs reuse the session and do not close it automatically. |
| `setPhoneNFCSessionMessage:`            | Updates the text of the system NFC dialog.                                                                                                         |
| `closePhoneNFCSession`                  | Closes the session successfully, using the system default success prompt.                                                                          |
| `closePhoneNFCSessionWithMessage:`      | Closes the session successfully and displays the specified message.                                                                                |
| `invalidatePhoneNFCSessionWithMessage:` | Closes the session with a failure status and displays an error message.                                                                            |
| `setOnPhoneNFCSessionEventListener:`    | Listens for system NFC session activation and invalidation; the invalidation callback carries the original Core NFC error.                         |

Once the session is taken over by the business side, be sure to call one of the close APIs on the success, failure, and page-exit paths; only one active NFC session is allowed at a time.

`PhoneNFCSessionEventDidBecomeActive` means the system NFC session has become active; `error` is `nil` in this case.  
`PhoneNFCSessionEventDidInvalidate` means the session has been invalidated; when the user taps the Cancel button in the system dialog, `error.domain` is `NFCError` and `error.code` is `200`.

```plain
[lock setOnPhoneNFCSessionEventListener:^(PhoneNFCSessionEvent event, NSError *error) {
    if (event == PhoneNFCSessionEventDidBecomeActive) {
        NSLog(@"NFC session activated");
    } else {
        NSLog(@"NFC session invalidated: %@", error.localizedDescription);
    }
}];
```

## 3. General Lock Operations

The following APIs apply to phone NFC, standard external readers, and standard Bluetooth locks. Electronic keys must use the dedicated APIs in Section 6; calling some of the unified lock APIs on KY53E/KY53N returns "unsupported".

### 3.1 Reading Information

| API                                        | `obj` in `success` | Description                                                      |
| ------------------------------------------ | ------------------ | ---------------------------------------------------------------- |
| `readLockBasicInfoSuccess:failure:`        | `MkdLockBasicInfo` | Lock serial number `sn` and MAC `mac`.                           |
| `readStatusAndElectricitySuccess:failure:` | `MkdLockInfo`      | Lock status and the NFC, solar, and battery voltages, all in mV. |
| `readFWVersionSuccess:failure:`            | `NSString`         | Firmware version.                                                |
| `readUnlockTimesSuccess:failure:`          | `NSNumber`         | Cumulative unlock count.                                         |

```plain
[lock readStatusAndElectricitySuccess:^(MkdLockInfo *info) {
    NSLog(@"status=%d, NFC=%dmV", info.lockStatus, info.nfcPower);
    if (info.isNewProtocol) {
        NSLog(@"rawStatus=%ld, temperature=%ld",
              (long)info.rawLockStatus, (long)info.temperature);
    }
} failure:^(NSString *error) {
    NSLog(@"Read failed: %@", error);
}];
```

Main fields of `MkdLockInfo`:

| Field                                            | Description                                                                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `lockStatus`                                     | Lock status; for the old protocol it is the normalized open/closed state, for the new protocol it is the protocol status code. |
| `lockBeamStatus`                                 | Lock shackle (beam) status.                                                                                                    |
| `nfcPower` / `solarEnergyPower` / `batteryPower` | NFC, solar, and battery voltages in mV.                                                                                        |
| `rawLockStatus` / `temperature`                  | Raw lock status code and temperature for the new protocol.                                                                     |
| `isNewProtocol`                                  | Whether parsed using the new protocol.                                                                                         |

### 3.2 Unlock and Lock

```plain
[lock unlockWithSecretKey:secretKey
                 smSecret:smSecret
           chargeProgress:^(NSInteger progress) {
    // NFC lock charging progress;
}
                  success:^(id result) {
    NSLog(@"Unlock succeeded: %@", result);
}
                  failure:^(UnlockFailStatus status, NSString *message) {
    NSLog(@"Unlock failed (%lu): %@", (unsigned long)status, message);
}];
```

| API                                                               | Description                                                                                                                                                                                                  |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `unlockWithSecretKey:smSecret:chargeProgress:success:failure:`    | Unified unlock entry. The SDK selects the protocol based on the lock SN and the current mode; `secretKey` is the lock secret key, and `smSecret` may be `nil`.                                               |
| `lockWithSecretKey:smSecret:success:failure:`                     | Unified lock entry, supported only by new-protocol NFC locks; old-protocol locks return "unsupported"; `smSecret` may be `nil`.                                                                              |
| `configureLockThresholdWithPassword:thresholdMV:success:failure:` | Configures the open/close Hall threshold of FL23N / PL56N. `password` is the lock password, and `thresholdMV` is in mV with type `uint16_t`; other lock types fail with `UnlockFailStatusUnsupportedDevice`. |

Lock/unlock failure codes:

| Enum                                            | Value | Meaning                                                         |
| ----------------------------------------------- | ----: | --------------------------------------------------------------- |
| `UnlockFailStatusVerifyFail`                    |     0 | SDK authentication failed.                                      |
| `UnlockFailStatusConnectFail`                   |     1 | Failed to connect the Tag or device.                            |
| `UnlockFailStatusWriteDataFail`                 |     2 | Command write or communication failed.                          |
| `UnlockFailStatusChargePowerFail`               |     3 | Failed to charge/power the lock.                                |
| `UnlockFailStatusWrongPassWD`                   |     4 | Incorrect lock secret key.                                      |
| `UnlockFailStatusCheckFail`                     |     5 | Secret key is correct, but the lock status check failed.        |
| `UnlockFailStatusNotConnectBLE`                 |     6 | Bluetooth not connected in external-reader/Bluetooth-lock mode. |
| `UnlockFailStatusMCUSleep`                      |     7 | MCU is asleep and cannot be woken up.                           |
| `UnlockFailStatusUnsupportedDevice`             |     8 | The current device or protocol does not support this operation. |
| `UnlockFailStatusMCUStartFail`                  |     9 | MCU startup failed.                                             |
| `UnlockFailStatusTagLost`                       |    10 | NFC Tag has been disconnected.                                  |
| `UnlockFailStatusLockStatusNotSupportOperation` |    11 | The current lock status does not allow this operation.          |
| `UnlockFailStatusFetchSecretKeyFail`            |    12 | Failed to obtain the lock secret key.                           |


## 4. Bluetooth Scanning, Connection, and Standard Bluetooth Locks

Both `UnlockMethodNFC_BLE` and `UnlockMethodBLELock` require scanning and connecting a Bluetooth device first.

```plain
lock.unlockMethod = UnlockMethodBLELock;
[lock searchDevicesForTimeout:10
                       success:^(CBPeripheral *peripheral, NSNumber *RSSI) {
    // Deduplicate and display peripherals; connect after the user makes a selection.
}
                      complete:^(id response) {
    NSLog(@"Scan finished: %@", response);
}
                          fail:^(id response) {
    NSLog(@"Scan failed: %@", response);
}];

// After a device is selected:
[lock connectPeripheral:peripheral success:^(id response) {
    NSLog(@"Connected: %@", response);
} fail:^(id response) {
    NSLog(@"Connection failed: %@", response);
}];
```

| API                                              | Description                                                                                                                                                                                                            |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `searchDevicesForTimeout:success:complete:fail:` | Searches for Bluetooth devices; `success` is invoked once per discovered device.                                                                                                                                       |
| `connectPeripheral:success:fail:`                | Connects the specified `CBPeripheral`; on success `isBLEConnected` becomes `YES`.                                                                                                                                      |
| `stopSearch`                                     | Stops the Bluetooth scan.                                                                                                                                                                                              |
| `disconnect`                                     | Disconnects the current Bluetooth connection and cleans up related state.                                                                                                                                              |
| `setOnBLELockActiveReportListener:`              | Registers a listener for the standard Bluetooth lock `0x6F` active status report; pass `nil` to cancel. If the SDK has already cached the latest report when a new listener registers, it is invoked once immediately. |

`BLELockActiveReportCallback` returns `MkdBLELockActiveReport`, in which `lockOpen`, `lockBeamDropped`, `typeCConnected`, `bleConnected`, and `powerOn` are `0/1` flags, and `serialNumber` is the report frame sequence number.

## 5. NB Lock Operations

NB lock operations are also invoked through `MkdLock`. Execute them only when the correct NFC/reader link has been established.

| API                                  | Success Callback               | Description                                                 |
| ------------------------------------ | ------------------------------ | ----------------------------------------------------------- |
| `resetNetWorkConfigSuccess:fail:`    | `@"OK"`                        | Resets the network configuration.                           |
| `queryNetworkConfigSuccess:fail:`    | `NBLockStatus status, int csq` | Queries network status and signal strength.                 |
| `queryOperationLogSuccess:fail:`     | `MkdLockLog`                   | Queries the operation log.                                  |
| `queryDeviceParametersSuccess:fail:` | `MkdNFCLockParam`              | Queries the network reconnection and keep-alive parameters. |

`NBLockStatus`: `NBLockStatusHibernate (0x00)` hibernating, `NBLockStatusPowerOn (0x01)` powered on, `NBLockStatusSelfTesting (0x02)` self-testing, `NBLockStatusConnecting (0x03)` connecting to the network, `NBLockStatusConnected (0x04)` connected.

`MkdLockLog` contains `serverType`, `networkTag`, and `failNum`; `MkdNFCLockParam` contains `reconTimeInteval` (in hours) and `activeTime` (in seconds).

## 6. Electronic Key APIs (KY53E / KY53N)

The electronic key must be used with `UnlockMethodNFC_BLE`. After the Bluetooth connection is established, confirm the device type via `electronicKeyDeviceType` or `isCurrentDeviceElectronicKey`. `connectedElectronicKeyName` returns the Bluetooth name of the currently connected device.

```plain
lock.unlockMethod = UnlockMethodNFC_BLE;
// After searchDevices / connectPeripheral is done:
if ([lock isCurrentDeviceElectronicKey]) {
    [lock setOnElectronicKeyHeartBeatListener:^(MkdElectronicKeyHeartBeat *heartBeat) {
        NSLog(@"Key battery=%ld, lock SN=%@", (long)heartBeat.electronicKeyBattery, heartBeat.lockSN);
    }];
    [lock setElectronicKeySmSecret:keySideSmSecret];
}
```

### 6.1 Heartbeat, Encryption, and Device Management

| API                                              | Success Callback                                      | Description                                                                                                                                                                                      |
| ------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `setOnElectronicKeyHeartBeatListener:`           | `MkdElectronicKeyHeartBeat`                           | Registers an active heartbeat listener; pass `nil` to cancel. If a cached heartbeat exists, it is invoked immediately.                                                                           |
| `sendElectronicKeyHeartWithUID:success:failure:` | Latest `MkdElectronicKeyHeartBeat`                    | Compatibility entry; does not actively send a command. Fails if no device heartbeat has been received yet. `uid` is fixed at 16 bytes in UTF-8: truncated if too long, zero-padded if too short. |
| `setElectronicKeySmSecret:`                      | No callback                                           | Sets the key-side `smSecret` for subsequent encryption/decryption.                                                                                                                               |
| `setElectronicKeyCryptoWithEncryptMode:key:`     | No callback                                           | Explicitly sets the encryption mode and key-side key; mode `1` is AES128, `2` is GM128.                                                                                                          |
| `readElectronicKeyInfoWithUID:success:failure:`  | `NSDictionary`                                        | Reads electronic key info; if the JSON cannot be parsed, returns `@{ @"raw": ... }`.                                                                                                             |
| `syncElectronicKeyTime:success:failure:`         | `@{ @"isSuccess": NSNumber, @"timestamp": NSNumber }` | Synchronizes a second-level Unix timestamp.                                                                                                                                                      |
| `rebootElectronicKeyWithUID:success:failure:`    | `@{ @"isSuccess": NSNumber, @"status": NSNumber }`    | Reboots the electronic key.                                                                                                                                                                      |

`MkdElectronicKeyHeartBeat` provides the electronic key's battery level/status, lock cylinder connection status, lock status, lock SN/MAC, key time, and the encryption modes on the key side and the lock side. `isLockCylinderConnected` indicates whether the lock cylinder is connected.

### 6.2 Sound Effects and Indicator Lights

`syncElectronicKeyTone:success:failure:` only indicates that the BLE write request has been submitted, not that the device has actually played the sound or switched the LED. The available `MkdElectronicKeyTone` values are:

| Enum                                                                                                                 |                    Value | Effect                                                             |
| -------------------------------------------------------------------------------------------------------------------- | -----------------------: | ------------------------------------------------------------------ |
| `MkdElectronicKeyToneTip` / `MkdElectronicKeyToneWarning` / `MkdElectronicKeyToneAlarm`                              | `0x01` / `0x02` / `0x03` | Tip sound, warning sound, alarm sound.                             |
| `MkdElectronicKeyToneUnlock` / `MkdElectronicKeyToneLock` / `MkdElectronicKeyToneLockFailed`                         | `0x04` / `0x05` / `0x06` | Unlock, lock, and lock-failed sounds.                              |
| `MkdElectronicKeyToneLowPower`                                                                                       |                   `0x07` | Low-battery sound.                                                 |
| `MkdElectronicKeyToneRunningLED` / `MkdElectronicKeyToneWarningLED` / `MkdElectronicKeyToneErrorLED`                 | `0x08` / `0x09` / `0x0A` | Running, warning, and error LEDs.                                  |
| `MkdElectronicKeyToneLowPowerLED` / `MkdElectronicKeyToneChargingLED` / `MkdElectronicKeyToneFullPowerLED`           | `0x0B` / `0x0C` / `0x0D` | Low-power, charging, and full-power LEDs.                          |
| `MkdElectronicKeyToneNormalLED` / `MkdElectronicKeyToneTipLED` / `MkdElectronicKeyToneBusyLED`                       | `0x0E` / `0x0F` / `0x10` | Normal, tip, and busy LEDs.                                        |
| `MkdElectronicKeyToneBLEConnected` / `MkdElectronicKeyToneBLEDisconnected`                                           |          `0x11` / `0x12` | Bluetooth connected/disconnected indications.                      |
| `MkdElectronicKeyToneUnlockSucceeded` / `MkdElectronicKeyToneLockSucceeded` / `MkdElectronicKeyToneLockFailedResult` | `0x13` / `0x14` / `0x15` | Unlock success, lock success, and lock failure result indications. |
| `MkdElectronicKeyToneOperationTimeout`                                                                               |                   `0x16` | Operation timeout indication.                                      |

### 6.3 Logs and Offline Authorization

| API                                                             | Success Callback                         | Description                                                                                                        |
| --------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `readElectronicKeyCacheLogWithUID:success:progress:failure:`    | `NSArray<NSDictionary *>`                | Reads cached logs; `progress` is the number of log entries read.                                                   |
| `clearElectronicKeyCacheLogWithUID:success:failure:`            | Status dictionary                        | Clears cached logs.                                                                                                |
| `sendElectronicKeyOfflineAuth:smSecret:success:failure:`        | Status dictionary                        | Sends an offline authorization; if `smSecret` is not passed, the value set by `setElectronicKeySmSecret:` is used. |
| `queryElectronicKeyOfflineAuthWithNID:success:failure:`         | `MkdElectronicKeyOfflineAuth`            | Queries the specified rule.                                                                                        |
| `queryAllElectronicKeyOfflineAuthWithSuccess:progress:failure:` | `NSArray<MkdElectronicKeyOfflineAuth *>` | Queries all rules; `progress` is the number of rules retrieved.                                                    |
| `deleteElectronicKeyOfflineAuthWithNID:success:failure:`        | Status dictionary                        | Deletes the specified rule.                                                                                        |
| `deleteAllElectronicKeyOfflineAuthWithSuccess:failure:`         | Status dictionary                        | Deletes all rules.                                                                                                 |

In `MkdElectronicKeyOfflineAuth`, `uid`, `kid`, and `lid` are each fixed at 16 bytes of UTF-8; `password` and the optional `lockSmSecret` are 32-character HEX strings. The time fields `startDatetime` / `endDatetime` are second-level timestamps; `authMode`: `1` by time, `2` by count, `3` hybrid.

### 6.4 Operating the Lock Cylinder via the Electronic Key

| API                                                                                        | Success Callback                               | Description                                                                                                  |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `readElectronicKeyLockSNWithUID:success:failure:`                                          | Lock SN info dictionary                        | Reads the SN of the currently connected lock cylinder; if a heartbeat cache exists, the cache is used first. |
| `readElectronicKeyLockStateWithUID:success:failure:`                                       | Lock status dictionary                         | Reads the current lock cylinder status.                                                                      |
| `readElectronicKeyLockProtocolVersionSuccess:failure:`                                     | Protocol version dictionary                    | Reads the lock cylinder protocol version.                                                                    |
| `unlockElectronicKeyWithUID:secretKey:smSecret:chargeProgress:success:failure:`            | Unlock result dictionary                       | Unlock dedicated to the electronic key.                                                                      |
| `lockElectronicKeyWithUID:secretKey:smSecret:success:failure:`                             | Lock result dictionary                         | Lock dedicated to the electronic key.                                                                        |
| `configElectronicKeyCloseThresholdWithUID:secretKey:thresholdMV:smSecret:success:failure:` | `@{ @"isSuccess": @YES, @"thresholdMV": ... }` | Configures the KY53E lock-close Hall threshold, in mV.                                                       |

The meaning of `smSecret` depends on the device: for KY53E, the dedicated lock/unlock and threshold configuration take the **lock-side** `smSecret`; for KY53N, the dedicated lock/unlock take a key-side override value, falling back to the configured key-side `smSecret` when not passed. Do not mix the two.

## 7. Recommended Call Sequence and Notes

1. After successful authentication, set `unlockMethod` and keep it unchanged throughout the operation flow.
2. In phone NFC mode, APIs can be called directly; for continuous operations, use the session takeover APIs in Section 2.
3. For external readers, standard Bluetooth locks, and electronic keys, scan and connect first, then initiate the corresponding operations.
4. Use the unified read/write and lock/unlock APIs for standard locks; prefer the electronic-key-specific APIs for KY53E/KY53N.
5. Send only one SDK command to a device at a time; wait for the success or failure callback before sending the next one.
6. When leaving a page or when the user cancels, stop scanning, close the phone NFC session, or call `disconnect` to avoid keeping invalid connections alive.
