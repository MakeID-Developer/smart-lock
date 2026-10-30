//
//  MkdNFCReaderWriter.h
//  MkdNFCReaderWriterLib
//
//  Created by 凉皮 on 2024/3/21.
//

#import <Foundation/Foundation.h>
#import <MkdBLEConnectLib/MkdBLEConnectLib.h>
#import <MkdNFCReaderWriterLib/MkdNFCDeviceInfo.h>
#import <MkdNFCReaderWriterLib/MkdNFCTagModel.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ResponseStatus) {
    ///发送数据成功
    ResponseStatusSuccess = 0x00,
    ///发送数据超时
    ResponseStatusTimeout = 0x01,
};///发送数据的状态


typedef void(^MkdBoolCallback)(BOOL isSuccess);
typedef void(^MkdQueryDeviceInfoCallback)(MkdNFCDeviceInfo *deviceInfo);
typedef void(^MkdResponseCallback)(BOOL isSuccess, NSData  *_Nullable recvData);
typedef void(^MkdSearchNFCCallback)(MkdNFCTagModel *tagModel);

@interface MkdNFCReaderWriter : NSObject
///当前SDK版本号
@property (nonatomic, copy) NSString * _Nonnull version;

///蓝牙连接状态
@property (nonatomic, assign, readonly) BOOL isConnected;

///NFC读写器与NFC标签的连接状态
@property (nonatomic, assign, readonly) BOOL isNFCConnected;

///连接的NFC tag
@property (nonatomic, strong) MkdNFCTagModel *NFCTag;

/**
 * 单例，主线程
 */
+ (instancetype)sharedInstance;

#pragma mark - 蓝牙操作
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
 * 通过identifier重连蓝牙
 * @param identifier peripheral.identifier.UUIDString
 */
- (void)reconnectPeripheralWithIdentifier:(NSString *)identifier
                                  success:(NormalCallback)successCallback
                                     fail:(NormalCallback)failCallback;

/**
 断开连接
 */
- (void)disconnect;

#pragma mark - 业务操作
/**
 查询NFC读写器设备信息
 */
- (void)queryDeviceInfo:(MkdQueryDeviceInfoCallback)callback;

/**
 开启自动寻卡
 @param type 寻卡类型
 @param timeInterval 寻卡的时间间隔，单位ms，建议大于100ms，小于100不生效
 @param callback 寻到卡片或断开的回调
 */
- (void)startAutoSearchCardWithType:(ProtocolType)type timeInterval:(NSInteger)timeInterval searchCardCallback:(MkdSearchNFCCallback)callback;

/**
 停止自动寻卡
 */
- (void)stopAutoSearchCard;

/**
 透传发送数据
 */
- (void)writeDataToNFCTag:(NSData *)data compelte:(MkdResponseCallback)compelteCallback;

@end

NS_ASSUME_NONNULL_END
