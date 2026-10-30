//
//  MkdNFCLock.h
//  MakeidNFCLock
//
//  Created by 凉皮 on 2023/1/28.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MkdNFCReaderWriterLib/MkdNFCReaderWriterLib.h>
#import <MkdLockLib/MkdLockLog.h>
#import <MkdLockLib/MkdBLELockActiveReport.h>
#import <MkdLockLib/MkdElectronicKeyHeartBeat.h>
#import <MkdLockLib/MkdElectronicKeyOfflineAuth.h>

NS_ASSUME_NONNULL_BEGIN

@class MkdLockBasicInfo;

#pragma mark - enum
typedef NS_ENUM(NSUInteger, UnlockFailStatus) {
    ///SDK授权失败
    UnlockFailStatusVerifyFail       = 0,
    ///连接Tag失败
    UnlockFailStatusConnectFail      = 1,
    ///写入数据失败
    UnlockFailStatusWriteDataFail    = 2,
    ///给锁充能失败
    UnlockFailStatusChargePowerFail  = 3,
    ///密码错误
    UnlockFailStatusWrongPassWD      = 4,
    ///密码正确但检查锁具状态失败
    UnlockFailStatusCheckFail        = 5,
    ///外置NFC读写器模式下，未连接蓝牙
    UnlockFailStatusNotConnectBLE    = 6,
    ///MCU休眠无法唤醒
    UnlockFailStatusMCUSleep         = 7,
    ///当前设备或协议不支持该操作
    UnlockFailStatusUnsupportedDevice = 8,
    ///MCU启动失败
    UnlockFailStatusMCUStartFail     = 9,
    ///NFC Tag 已断开
    UnlockFailStatusTagLost          = 10,
    ///当前锁状态不支持该操作
    UnlockFailStatusLockStatusNotSupportOperation = 11,
    ///获取锁密钥失败
    UnlockFailStatusFetchSecretKeyFail = 12,
};//开锁失败的状态码

typedef NS_ENUM(NSUInteger, UnlockMethod) {
    ///通过手机NFC
    UnlockMethodNFC_Phone        = 0,
    ///通过蓝牙连接的外置NFC设备（读写器/电子钥匙）
    UnlockMethodNFC_BLE          = 1,
    ///通过普通蓝牙锁
    UnlockMethodBLELock          = 2,
};///开锁方式

typedef NS_ENUM(NSUInteger, MkdElectronicKeyDeviceType) {
    ///非电子钥匙设备或尚未识别
    MkdElectronicKeyDeviceTypeUnknown = 0,
    ///KY53E电子钥匙
    MkdElectronicKeyDeviceTypeKY53E   = 1,
    ///KY53N电子钥匙/读写器复合设备
    MkdElectronicKeyDeviceTypeKY53N   = 2,
};///电子钥匙设备类型

typedef NS_ENUM(uint8_t, MkdElectronicKeyTone) {
    MkdElectronicKeyToneTip = 0x01,
    MkdElectronicKeyToneWarning = 0x02,
    MkdElectronicKeyToneAlarm = 0x03,
    MkdElectronicKeyToneUnlock = 0x04,
    MkdElectronicKeyToneLock = 0x05,
    MkdElectronicKeyToneLockFailed = 0x06,
    MkdElectronicKeyToneLowPower = 0x07,
    MkdElectronicKeyToneRunningLED = 0x08,
    MkdElectronicKeyToneWarningLED = 0x09,
    MkdElectronicKeyToneErrorLED = 0x0A,
    MkdElectronicKeyToneLowPowerLED = 0x0B,
    MkdElectronicKeyToneChargingLED = 0x0C,
    MkdElectronicKeyToneFullPowerLED = 0x0D,
    MkdElectronicKeyToneNormalLED = 0x0E,
    MkdElectronicKeyToneTipLED = 0x0F,
    MkdElectronicKeyToneBusyLED = 0x10,
    MkdElectronicKeyToneBLEConnected = 0x11,
    MkdElectronicKeyToneBLEDisconnected = 0x12,
    MkdElectronicKeyToneUnlockSucceeded = 0x13,
    MkdElectronicKeyToneLockSucceeded = 0x14,
    MkdElectronicKeyToneLockFailedResult = 0x15,
    MkdElectronicKeyToneOperationTimeout = 0x16,
};

typedef NS_ENUM(NSUInteger, NBLockStatus) {
    ///休眠中
    NBLockStatusHibernate    = 0x00,
    ///已开机
    NBLockStatusPowerOn      = 0x01,
    ///网络自检中
    NBLockStatusSelfTesting  = 0x02,
    ///联网中
    NBLockStatusConnecting   = 0x03,
    ///已连接网络
    NBLockStatusConnected    = 0x04,
};///NB锁的状态

#pragma mark - block
typedef void(^SuccessCallback)(_Nullable id obj);
typedef void(^FailureCallback)(NSString * _Nullable errMsg);
typedef void(^UnlockFailCallback)(UnlockFailStatus status, NSString * _Nullable errMsg);
typedef void(^SearchDeviceCallback)(CBPeripheral *peripheral, NSNumber *RSSI);
typedef void(^NormalCallback)(id response);
typedef void(^BLELockActiveReportCallback)(MkdBLELockActiveReport *report);
typedef void(^ElectronicKeyHeartBeatCallback)(MkdElectronicKeyHeartBeat *heartBeat);
typedef void(^ElectronicKeyProgressCallback)(CGFloat progress);
typedef NS_ENUM(NSUInteger, PhoneNFCSessionEvent) {
    PhoneNFCSessionEventDidBecomeActive = 0,
    PhoneNFCSessionEventDidInvalidate   = 1,
};
typedef void(^PhoneNFCSessionEventCallback)(PhoneNFCSessionEvent event, NSError * _Nullable error);

//操作锁的单例
@interface MkdLock : NSObject

///当前SDK版本号
@property (nonatomic, copy) NSString * _Nonnull version;

///是否输出日志
@property (nonatomic, assign) BOOL isLog;

///NFC tag 连接超时时长，默认10S
@property (nonatomic, assign) NSTimeInterval connectTimeout;

///开锁方式，默认通过手机NFC开锁
@property (nonatomic, assign) UnlockMethod unlockMethod;

///蓝牙是否连接，UnlockMethodNFC_BLE、UnlockMethodBLELock模式下
@property (nonatomic, assign) BOOL isBLEConnected;

///NFC是否连接，UnlockMethodNFC_BLE模式下的读写器寻卡链路使用
@property (nonatomic, assign) BOOL isNFCConnected;

///当前连接的电子钥匙类型。连接KY53E/KY53N后可用于业务分流。
@property (nonatomic, assign, readonly) MkdElectronicKeyDeviceType electronicKeyDeviceType;

///当前连接的电子钥匙蓝牙名称。
@property (nonatomic, copy, readonly, nullable) NSString *connectedElectronicKeyName;

/**
 * 单例
 */
+ (instancetype)sharedInstance;

/// SDK鉴权方法
/// - appID: appID 联系商务提供Bundle ID获取
/// - appSecret: appSecret 联系商务提供Bundle ID获取
- (BOOL)initWithAppID:(NSString *)appID appSecret:(NSString *)appSecret;

#pragma mark - NFC锁和蓝牙锁操作api
/// 读取锁具信息SN
/// - success: 成功回调
/// - failure: 失败回调
- (void)readLockBasicInfoSuccess:(SuccessCallback)success failure:(FailureCallback)failure;

/// 读取锁具状态和电量
/// - success: success
/// - failure: failure
- (void)readStatusAndElectricitySuccess:(SuccessCallback)success failure:(FailureCallback)failure;

/// 读取固件版本号
/// - success: success
/// - failure: failure
- (void)readFWVersionSuccess:(SuccessCallback)success failure:(FailureCallback)failure;

/// 读取开锁次数
/// - Parameters:
///   - success: success
///   - failure: failure
- (void)readUnlockTimesSuccess:(SuccessCallback)success failure:(FailureCallback)failure;

/// 开锁
/// - secretKey: 锁密钥
/// - smSecret: 锁侧 smSecret，可传 nil
/// - chargeCallback NFC锁充电时的回调，不需要充电时不会回调
/// - success: success
/// - failure: failure
- (void)unlockWithSecretKey:(NSString *)secretKey
                   smSecret:(nullable NSString *)smSecret
             chargeProgress:(void (^)(NSInteger progress))chargeCallback
                    success:(nullable SuccessCallback)success
                    failure:(nullable UnlockFailCallback)failure;
                    
/// 关锁，仅新协议锁支持。当前真机流程待接入，旧协议锁会返回不支持。
/// - secretKey: 锁密钥
/// - smSecret: 锁侧 smSecret，可传 nil
/// - success: success
/// - failure: failure
- (void)lockWithSecretKey:(NSString *)secretKey
                 smSecret:(nullable NSString *)smSecret
                  success:(nullable SuccessCallback)success
                  failure:(nullable UnlockFailCallback)failure;

///配置 FL23N / PL56N 开关锁霍尔阈值。其他锁型返回不支持。
- (void)configureLockThresholdWithPassword:(NSString *)password
                                thresholdMV:(uint16_t)thresholdMV
                                    success:(nullable SuccessCallback)success
                                    failure:(nullable UnlockFailCallback)failure;

#pragma mark - 手机NFC开锁特有api

/// 开启手机NFC会话并连接Tag。调用后系统NFC弹窗由外层业务接管，后续手机NFC接口会复用该会话且成功后不自动关闭弹窗。
/// - success: Tag连接成功回调
/// - failure: 连接失败回调
- (void)beginPhoneNFCSessionSuccess:(nullable SuccessCallback)success
                             failure:(nullable FailureCallback)failure;

/// 设置当前手机NFC系统弹窗显示文案。
/// - message: 弹窗文案
- (void)setPhoneNFCSessionMessage:(nullable NSString *)message;

/// 关闭外层接管的手机NFC会话，系统弹窗显示默认成功文案。
- (void)closePhoneNFCSession;

/// 关闭外层接管的手机NFC会话，并在系统弹窗显示指定成功文案。
/// - message: 关闭前展示的文案
- (void)closePhoneNFCSessionWithMessage:(nullable NSString *)message;

/// 以失败状态关闭外层接管的手机NFC会话，并在系统弹窗显示指定错误文案。
/// - message: 错误文案
- (void)invalidatePhoneNFCSessionWithMessage:(nullable NSString *)message;

/// 注册手机 NFC 会话监听。会话激活或失效时在主线程回调；失效时 error 为 Core NFC 原始错误。
- (void)setOnPhoneNFCSessionEventListener:(nullable PhoneNFCSessionEventCallback)listener;

#pragma mark - 蓝牙锁特有api        
/// 注册普通蓝牙锁主动上报监听。收到 0x6F 状态上报后会回调 MkdBLELockActiveReport 对象。
- (void)setOnBLELockActiveReportListener:(nullable BLELockActiveReportCallback)listener;

#pragma mark - 电子钥匙操作api

///当前连接设备是否为KY53E/KY53N电子钥匙
- (BOOL)isCurrentDeviceElectronicKey;

///注册电子钥匙主动上报心跳监听。设备上报0x01后会解析为MkdElectronicKeyHeartBeat对象。
- (void)setOnElectronicKeyHeartBeatListener:(nullable ElectronicKeyHeartBeatCallback)listener;

///兼容入口：电子钥匙心跳依赖设备主动上报，当前方法返回最近一次心跳。
///uid为业务自定义字符串，SDK按UTF-8写入固定16字节，超出部分截断，不足补0。
- (void)sendElectronicKeyHeartWithUID:(nullable NSString *)uid
                              success:(nullable SuccessCallback)success
                              failure:(nullable FailureCallback)failure;

///设置钥匙侧smSecret，供电子钥匙链路加解密使用。
- (void)setElectronicKeySmSecret:(NSString *)smSecret;

///显式设置钥匙侧加密模式和key。
- (void)setElectronicKeyCryptoWithEncryptMode:(NSInteger)encryptMode key:(NSString *)key;

///成功仅表示 BLE 写请求已提交，不代表设备已播放音效或切换 LED。
- (void)syncElectronicKeyTone:(MkdElectronicKeyTone)tone
                       success:(nullable SuccessCallback)success
                       failure:(nullable FailureCallback)failure;

///读取电子钥匙自身信息。
- (void)readElectronicKeyInfoWithUID:(nullable NSString *)uid
                              success:(nullable SuccessCallback)success
                              failure:(nullable FailureCallback)failure;

///同步电子钥匙时间，timestamp单位为秒。
- (void)syncElectronicKeyTime:(NSTimeInterval)timestamp
                      success:(nullable SuccessCallback)success
                      failure:(nullable FailureCallback)failure;

///重启电子钥匙。
- (void)rebootElectronicKeyWithUID:(nullable NSString *)uid
                            success:(nullable SuccessCallback)success
                            failure:(nullable FailureCallback)failure;

///读取电子钥匙缓存日志。
- (void)readElectronicKeyCacheLogWithUID:(nullable NSString *)uid
                                 success:(nullable SuccessCallback)success
                                progress:(nullable ElectronicKeyProgressCallback)progress
                                 failure:(nullable FailureCallback)failure;

///清除电子钥匙缓存日志。
- (void)clearElectronicKeyCacheLogWithUID:(nullable NSString *)uid
                                  success:(nullable SuccessCallback)success
                                  failure:(nullable FailureCallback)failure;

///下发电子钥匙离线授权。auth.lockSmSecret为锁侧smSecret，可不传，不传时下发16字节0；smSecret参数为钥匙侧smSecret。
- (void)sendElectronicKeyOfflineAuth:(MkdElectronicKeyOfflineAuth *)auth
                             smSecret:(nullable NSString *)smSecret
                              success:(nullable SuccessCallback)success
                              failure:(nullable FailureCallback)failure;

///查询单个离线授权。success回调obj为MkdElectronicKeyOfflineAuth。
- (void)queryElectronicKeyOfflineAuthWithNID:(NSInteger)nid
                                     success:(nullable SuccessCallback)success
                                     failure:(nullable FailureCallback)failure;

///查询全部离线授权。success回调obj为NSArray<MkdElectronicKeyOfflineAuth *>。
- (void)queryAllElectronicKeyOfflineAuthWithSuccess:(nullable SuccessCallback)success
                                           progress:(nullable ElectronicKeyProgressCallback)progress
                                            failure:(nullable FailureCallback)failure;

///删除单个离线授权。
- (void)deleteElectronicKeyOfflineAuthWithNID:(NSInteger)nid
                                      success:(nullable SuccessCallback)success
                                      failure:(nullable FailureCallback)failure;

///删除全部离线授权。
- (void)deleteAllElectronicKeyOfflineAuthWithSuccess:(nullable SuccessCallback)success
                                             failure:(nullable FailureCallback)failure;

///读取电子钥匙当前连接锁芯SN。
- (void)readElectronicKeyLockSNWithUID:(nullable NSString *)uid
                               success:(nullable SuccessCallback)success
                                failure:(nullable FailureCallback)failure;

///读取电子钥匙当前连接锁芯状态。
- (void)readElectronicKeyLockStateWithUID:(nullable NSString *)uid
                                  success:(nullable SuccessCallback)success
                                   failure:(nullable FailureCallback)failure;

///读取电子钥匙当前连接锁芯协议版本。
- (void)readElectronicKeyLockProtocolVersionSuccess:(nullable SuccessCallback)success
                                            failure:(nullable FailureCallback)failure;

///电子钥匙专用开锁。KY53E的smSecret为锁侧smSecret；KY53N的smSecret为钥匙侧smSecret覆盖值。
- (void)unlockElectronicKeyWithUID:(nullable NSString *)uid
                          secretKey:(NSString *)secretKey
                           smSecret:(nullable NSString *)smSecret
                     chargeProgress:(nullable ElectronicKeyProgressCallback)chargeCallback
                            success:(nullable SuccessCallback)success
                            failure:(nullable UnlockFailCallback)failure;

///电子钥匙专用关锁。KY53E的smSecret为锁侧smSecret；KY53N的smSecret为钥匙侧smSecret覆盖值。
- (void)lockElectronicKeyWithUID:(nullable NSString *)uid
                        secretKey:(NSString *)secretKey
                         smSecret:(nullable NSString *)smSecret
                          success:(nullable SuccessCallback)success
                          failure:(nullable UnlockFailCallback)failure;

///配置KY53E关锁霍尔阈值，thresholdMV单位为mV。
- (void)configElectronicKeyCloseThresholdWithUID:(nullable NSString *)uid
                                       secretKey:(NSString *)secretKey
                                     thresholdMV:(NSInteger)thresholdMV
                                        smSecret:(NSString *)smSecret
                                         success:(nullable SuccessCallback)success
                                         failure:(nullable FailureCallback)failure;

///电子钥匙固件升级。
- (void)upgradeElectronicKeyFirmwareAtURL:(NSURL *)firmwareURL
                                  progress:(nullable ElectronicKeyProgressCallback)progress
                                   success:(nullable SuccessCallback)success
                                   failure:(nullable FailureCallback)failure;

///电子钥匙固件升级，softwareVersion/hardwareVersion各最多写入4字节；为空时使用"1.0"。
- (void)upgradeElectronicKeyFirmwareAtURL:(NSURL *)firmwareURL
                           softwareVersion:(nullable NSString *)softwareVersion
                           hardwareVersion:(nullable NSString *)hardwareVersion
                                  progress:(nullable ElectronicKeyProgressCallback)progress
                                   success:(nullable SuccessCallback)success
                                   failure:(nullable FailureCallback)failure;

#pragma mark - NB锁操作api

//重置NB锁的网络配置
- (void)resetNetWorkConfigSuccess:(SuccessCallback)successCallback fail:(FailureCallback)failure;

//查询NB锁的网络配置情况
- (void)queryNetworkConfigSuccess:(void (^)(NBLockStatus status, int csq))successCallback fail:(FailureCallback)failure;

//查询操作日志
- (void)queryOperationLogSuccess:(void (^)(MkdLockLog *log))successCallback fail:(FailureCallback)failure;

//查询NB锁设备参数
- (void)queryDeviceParametersSuccess:(void (^)(MkdNFCLockParam *param))successCallback fail:(FailureCallback)failure;

#pragma mark - 蓝牙锁、外置NFC读写器、电子钥匙蓝牙操作api
/**
 * 搜索蓝牙设备
 * @param timeout 搜索超时时间
 */
- (void)searchDevicesForTimeout:(NSTimeInterval)timeout
                        success:(SearchDeviceCallback)successCallback
                       complete:(NormalCallback)completeCallback
                           fail:(NormalCallback)failCallback;

/**
 * 连接蓝牙
 * @param peripheral 需要连接的peripheral
 */
- (void)connectPeripheral:(CBPeripheral *)peripheral
                  success:(NormalCallback)successCallback
                     fail:(NormalCallback)failCallback;

/**
 * 停止蓝牙扫描
 */
- (void)stopSearch;

/**
 断开连接
 */
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END
