//
//  MkdBLELockActiveReport.h
//  MkdLockLib
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 普通蓝牙锁主动上报的状态数据。
@interface MkdBLELockActiveReport : NSObject <NSCopying>

/// 对外锁状态，普通 BLE 锁主动上报取 status 的 bit4(on_off)，1=开。
@property (nonatomic, assign, getter=isLockOpen) int lockOpen;

/// 锁梁状态，1=脱落。
@property (nonatomic, assign, getter=isLockBeamDropped) int lockBeamDropped;

/// Type-C 接口连接状态，1=已连接。
@property (nonatomic, assign, getter=isTypeCConnected) int typeCConnected;

/// 蓝牙连接状态，1=已连接。
@property (nonatomic, assign, getter=isBLEConnected) int bleConnected;

/// 开关状态，1=开机。
@property (nonatomic, assign, getter=isPowerOn) int powerOn;

/// 上报帧中的序列号，取 Dir/Enc/SN 字段低 6 位。
@property (nonatomic, assign) uint8_t serialNumber;

@end

NS_ASSUME_NONNULL_END
