//
//  MkdViewController.m
//  MkdIoTToolsDemo
//
//  Created by 凉皮 on 2023/7/6.
//

#import "MkdViewController.h"

@interface MkdViewController ()

@end

@implementation MkdViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.navigationController.navigationBar.tintColor = [UIColor blackColor];

}

- (void)backToUpViewController {
    
    [self.navigationController popViewControllerAnimated:YES];
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
