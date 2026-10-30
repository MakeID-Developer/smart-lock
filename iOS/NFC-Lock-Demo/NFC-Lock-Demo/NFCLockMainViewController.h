//
//  NFCLockMainViewController.h
//  MkdIoTToolsDemo
//
//  Created by 凉皮 on 2023/7/6.
//

#import "MkdViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class MkdLockInfo;

@interface NFCLockMainViewController : MkdViewController

+ (NSString *)statusLogTextWithLockInfo:(MkdLockInfo *)info;
+ (NSArray<NSString *> *)configurationActionTitles;

@end

NS_ASSUME_NONNULL_END
