//
//  MkdNFCDeviceInfo.h
//  MkdNFCReaderWriterLib
//
//  Created by 凉皮 on 2024/3/21.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/**
 NFC读写器设备信息
 */
@interface MkdNFCDeviceInfo : NSObject

///读写器电池电量mv
@property (nonatomic, assign) NSInteger electricity;
///读写器电池电量百分比
@property (nonatomic, assign) NSInteger electricityPercent;
///硬件版本号
@property (nonatomic, copy) NSString *hardwareVersion;
///软件版本号
@property (nonatomic, copy) NSString *softwareVersion;

@end

NS_ASSUME_NONNULL_END
