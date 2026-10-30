//
//  BLEConnectViewController.m
//  NFC-Lock-Demo
//

#import "BLEConnectViewController.h"
#import <MkdLockLib/MkdLock.h>
#import "MBProgressHUD.h"
#import "ToastUtils.h"
#import "ACMacros.h"

static NSString * const BLEConnectNFCRWIdentifierKey = @"NFCReaderWriterBleIdentifier";
static NSString * const BLEConnectBLELockIdentifierKey = @"BLELockBleIdentifier";

@interface BLEConnectViewController ()

@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *deviceArray;

@end

@implementation BLEConnectViewController

- (void)dealloc {
    NSLog(@"BLEConnectViewController 释放");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"BLE Connection";
    [self searchDevices];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.deviceArray.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60.f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"BLEConnectCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    NSDictionary *deviceInfo = self.deviceArray[indexPath.row];
    CBPeripheral *peripheral = deviceInfo[@"peripheral"];
    NSNumber *RSSI = deviceInfo[@"RSSI"];
    cell.textLabel.text = [NSString stringWithFormat:@"Device Name: %@", peripheral.name];
    UILabel *rssiLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 70.f, 20.f)];
    rssiLabel.font = [UIFont systemFontOfSize:12.f];
    rssiLabel.textColor = UIColor.darkGrayColor;
    rssiLabel.textAlignment = NSTextAlignmentRight;
    rssiLabel.text = [NSString stringWithFormat:@"%@ dBm", RSSI];
    cell.accessoryView = rssiLabel;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    NSDictionary *deviceInfo = self.deviceArray[indexPath.row];
    CBPeripheral *peripheral = deviceInfo[@"peripheral"];
    [self connectToPeripheral:peripheral];
}

- (IBAction)clickSearchButtonAction:(UIButton *)sender {
    [self searchDevices];
}

- (void)searchDevices {
    [self.deviceArray removeAllObjects];
    [self.tableView reloadData];

    WS(weakSelf);
    [MkdLock.sharedInstance searchDevicesForTimeout:5 success:^(CBPeripheral * _Nonnull peripheral, NSNumber * _Nonnull RSSI) {
        [weakSelf.deviceArray addObject:@{@"peripheral":peripheral, @"RSSI":RSSI ?: @0}];
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
        });
    } complete:^(id  _Nonnull response) {
        NSLog(@"搜索完成");
    } fail:^(id  _Nonnull response) {
        [ToastUtils show:response];
    }];
}

- (void)connectToPeripheral:(CBPeripheral *)peripheral {
    WS(weakSelf);
    [MkdLock.sharedInstance connectPeripheral:peripheral success:^(id  _Nonnull response) {
        NSString *identifierKey = MkdLock.sharedInstance.unlockMethod == UnlockMethodBLELock ? BLEConnectBLELockIdentifierKey : BLEConnectNFCRWIdentifierKey;
        [[NSUserDefaults standardUserDefaults] setValue:peripheral.identifier.UUIDString forKey:identifierKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
    } fail:^(id  _Nonnull response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [MBProgressHUD hideHUDForView:weakSelf.view animated:YES];
            [ToastUtils show:response ?: @"Connection failed"];
        });
    }];
}

- (NSMutableArray *)deviceArray {
    if (!_deviceArray) {
        _deviceArray = [[NSMutableArray alloc] init];
    }
    return _deviceArray;
}

@end
