//
//  MkdLockLog.h
//  MkdLockLib
//
//  Created by 凉皮 on 2024/11/5.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

//锁运行日志信息
@interface MkdLockLog : NSObject

///当前服务器地址        0：默认地址    1：配置地址
@property (nonatomic, assign) int serverType;
///设备上次联网失败标志    0：成功    1：失败
@property (nonatomic, assign) int networkTag;
///设备上次联网失败AT指令编号
@property (nonatomic, assign) int failNum;

@end

@interface MkdNFCLockParam : NSObject
///定时重连网络间隔时间      单位：小时
@property (nonatomic, assign) int reconTimeInteval;
///每次连接服务器后，网络保活时间    单位：秒
@property (nonatomic, assign) int activeTime;

@end

NS_ASSUME_NONNULL_END
