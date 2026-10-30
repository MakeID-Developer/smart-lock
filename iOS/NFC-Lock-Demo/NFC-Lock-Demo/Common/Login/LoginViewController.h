//
//  LoginViewController.h
//  MkdIoTToolsDemo
//
//  Created by 凉皮 on 2023/7/6.
//

#import "MkdViewController.h"
#import "IoTDevice.h"
NS_ASSUME_NONNULL_BEGIN
typedef void(^LoginSuccessCallback)(void);


/// 登录页面
@interface LoginViewController : MkdViewController

@property (nonatomic, copy) LoginSuccessCallback successCallback;

@property (nonatomic, strong) IoTDevice *device;

@end

NS_ASSUME_NONNULL_END
