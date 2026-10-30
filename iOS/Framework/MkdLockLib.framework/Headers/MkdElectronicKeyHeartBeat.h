//
//  MkdElectronicKeyHeartBeat.h
//  MkdLockLib
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 电子钥匙主动上报心跳数据。
@interface MkdElectronicKeyHeartBeat : NSObject <NSCopying>

/// 钥匙电量。
@property (nonatomic, assign) NSInteger electronicKeyBattery;
/// 钥匙状态，0正常，1充电。
@property (nonatomic, assign) NSInteger electronicKeyState;
/// 锁芯连接状态，0未连接，1已连接。
@property (nonatomic, assign) NSInteger lockCylinderState;
/// 锁状态，0无状态，1已开锁，2已关锁。
@property (nonatomic, assign) NSInteger lockState;
/// 锁芯SN。
@property (nonatomic, copy) NSString *lockSN;
/// 锁芯MAC，大写十六进制字符串。
@property (nonatomic, copy) NSString *lockMAC;
/// 电子钥匙内部时间，秒级时间戳。
@property (nonatomic, assign) uint32_t electronicKeyTimeSec;
/// 电子钥匙侧加密模式，0x01 AES128，0x02 GM128。
@property (nonatomic, assign) NSInteger electronicKeyEncryptMode;
/// 锁侧加密模式，0x01 AES128，0x02 GM128。
@property (nonatomic, assign) NSInteger lockEncryptMode;
/// 预留字节。
@property (nonatomic, assign) NSInteger reserve;
/// 原始心跳负载。
@property (nonatomic, copy, nullable) NSData *rawPayload;

/// 是否已连接锁芯。
@property (nonatomic, assign, readonly, getter=isLockCylinderConnected) BOOL lockCylinderConnected;

+ (instancetype)heartBeatWithPayload:(NSData *)payload;

@end

NS_ASSUME_NONNULL_END
