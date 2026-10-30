//
//  LoginViewController.m
//  MkdIoTToolsDemo
//
//  Created by 凉皮 on 2023/7/6.
//

#import "LoginViewController.h"
#import "HttpUtil.h"
#import "UIView+Toast.h"
#import "NFCLockMainViewController.h"
#import "AppDelegate.h"

@interface LoginViewController ()
@property (weak, nonatomic) IBOutlet UITextField *usernameTextFiled;
@property (weak, nonatomic) IBOutlet UITextField *passwdTextFiled;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityView;

@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    
    NSString *userName = [[NSUserDefaults standardUserDefaults] stringForKey:@"UserName"];
    NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:@"PassWD"];
    
    if (userName && password) {
        self.usernameTextFiled.text = userName;
        self.passwdTextFiled.text = password;
    }
    
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];

    NSString *applocalVersion = [infoDictionary objectForKey:@"CFBundleShortVersionString"];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];

    [dateFormatter setDateFormat:@"yyyyMMdd"];

    NSString *currentDateStr = [dateFormatter stringFromDate:[NSDate date]];
}

- (IBAction)clickLoginButtonAction:(UIButton *)sender {

    if (self.usernameTextFiled.text.length <= 0) {
        
        [self.view makeToast:@"Please enter a username" duration:3.0f position:CSToastPositionCenter];
        
        return;
    }
    
    if (self.passwdTextFiled.text.length <= 0) {
        
        [self.view makeToast:@"Please enter a password" duration:3.0f position:CSToastPositionCenter];
        
        return;
    }
    
    [self.view endEditing:YES];
    
    NSString *userName = self.usernameTextFiled.text;
    NSString *passWD = self.passwdTextFiled.text;
    
    sender.userInteractionEnabled = NO;
    
    [self.activityView startAnimating];
    
    NSDictionary *parameter = @{@"username": userName, @"password": passWD};
    
    [HttpUtil postWithUrlString:@"/jeecg-system/sys/appLogin" parameters:parameter success:^(NSDictionary * _Nonnull data) {
        
        NSInteger code = [data[@"code"] integerValue];
        
        if (code == 200) {
            
            NSDictionary *resultDict = data[@"result"];
            NSString *token = resultDict[@"token"];
            
            [[NSUserDefaults standardUserDefaults] setValue:userName forKey:@"UserName"];
            [[NSUserDefaults standardUserDefaults] setValue:passWD forKey:@"PassWD"];
            [[NSUserDefaults standardUserDefaults] setValue:token forKey:@"Token"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self.activityView stopAnimating];
                sender.userInteractionEnabled = YES;
                NSString *message = data[@"message"];
                
                [self.view makeToast:message
                            duration:3.0f position:CSToastPositionCenter];
                
                [self dismissViewControllerAnimated:YES completion:nil];
                
                if (self.successCallback) {
                    self.successCallback();
                }
            });
            
        } else {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self.activityView stopAnimating];
                sender.userInteractionEnabled = YES;
                
                NSString *message = data[@"message"];
                
                if ([message isKindOfClass:[NSNull class]]) {
                    return;
                }
                
                if (message) {
                    [self.view makeToast:message
                                duration:3.0f position:CSToastPositionCenter];
                }
            });
        }
        
    } failure:^(NSError * _Nonnull error) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [self.activityView stopAnimating];
            
            sender.enabled = YES;
            sender.userInteractionEnabled = YES;
            
            [self.view makeToast:[NSString stringWithFormat:@"Login failed: %@", error.localizedDescription]
                        duration:3.0f position:CSToastPositionCenter];
        });
    }];
}

- (IBAction)clcikBackButtonAction:(UIButton *)sender {
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)tapBgViewAction:(UITapGestureRecognizer *)sender {
    
    [self.view endEditing:YES];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
