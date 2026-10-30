//
//  LockOfflineAuthViewController.h
//  MkdIoTToolsDemo
//

#import "MkdViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface LockOfflineAuthViewController : MkdViewController

@property (nonatomic, copy) NSString *keySN;
@property (nonatomic, copy) NSString *keySmSecret;
@property (nonatomic, copy) NSString *lockSN;
@property (nonatomic, copy) NSString *lockPassword;
@property (nonatomic, copy) NSString *lockSmSecret;
@property (nonatomic, copy) NSString *uid;

@end

NS_ASSUME_NONNULL_END
