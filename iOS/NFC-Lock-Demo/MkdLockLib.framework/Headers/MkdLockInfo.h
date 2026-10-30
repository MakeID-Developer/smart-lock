//
//  MkdLockInfo.h
//  MakeIDLock
//
//  Created by 凉皮 on 2023/3/16.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 锁信息
 */

@interface MkdLockInfo : NSObject
///锁具状态。旧协议返回归一化后的开关状态（原始0/1互换），新协议返回协议状态码
@property (nonatomic, assign) int lockStatus;
///锁梁状态，实际解析到的状态值
@property (nonatomic, assign) int lockBeamStatus;
///NFC电量mv
@property (nonatomic, assign) int nfcPower;
///太阳能电量mv
@property (nonatomic, assign) int solarEnergyPower;
///电池电量mv
@property (nonatomic, assign) int batteryPower;
///原始锁状态码
@property (nonatomic, assign) NSInteger rawLockStatus;
///新协议温度
@property (nonatomic, assign) NSInteger temperature;
///是否按新协议解析
@property (nonatomic, assign) BOOL isNewProtocol;
///是否为 FL23N / PL56N 专用 NFC 状态。为 YES 时以下字段有效。
@property (nonatomic, assign) BOOL isFL23NPL56NProtocol;
///FL23N / PL56N Page16 随机数，8 位大写十六进制字符串。
@property (nonatomic, copy, nullable) NSString *randomHex;
///FL23N / PL56N 通信加密方式：0 NONE，1 AES128，2 GM128/SM4。
@property (nonatomic, assign) uint8_t cryptoMode;
///FL23N / PL56N 门磁霍尔配置。
@property (nonatomic, assign) BOOL doorMagneticHall;
///FL23N / PL56N 参数状态。
@property (nonatomic, assign) uint8_t parameterStatus;

@end

NS_ASSUME_NONNULL_END
