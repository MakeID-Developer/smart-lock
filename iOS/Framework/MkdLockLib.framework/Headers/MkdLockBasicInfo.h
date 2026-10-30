//
//  MakeidLockBasicInfo.h
//  MakeidLock
//
//  Created by 凉皮 on 2023/4/17.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 锁基本信息
 */
@interface MkdLockBasicInfo : NSObject
///sn序列号
@property (nonatomic, copy) NSString *sn;
///mac地址
@property (nonatomic, copy) NSString *mac;

@end

NS_ASSUME_NONNULL_END
