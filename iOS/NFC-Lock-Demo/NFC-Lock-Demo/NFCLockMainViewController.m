//
//  NFCLockMainViewController.m
//  MkdIoTToolsDemo
//
//  Created by 凉皮 on 2023/7/6.
//

#import "NFCLockMainViewController.h"
#import <MkdLockLib/MkdLockLib.h>
#import "UIView+Toast.h"
#import "BLEConnectViewController.h"
#import "ACMacros.h"
#import "UIAlertController+Blocks.h"
#import "MBProgressHUD.h"
#import "LockOfflineAuthViewController.h"

//AppID和AppSecret联系商务获取，需要提供Bundle ldentifier
#define AppID @"b96bbeb49044cb3d61007e82b2ded239"
#define AppSecret @"1183152c150565d10d21736366117fdf285471cf"

static NSInteger const LockUnlockMethodPhoneNFCIndex = 0;
static NSInteger const LockUnlockMethodNFCRWIndex = 1;
static NSInteger const LockUnlockMethodRemoteIndex = 2;
static NSInteger const LockUnlockMethodBLELockIndex = 3;
static NSString * const LockNFCRWBLEIdentifierKey = @"NFCReaderWriterBleIdentifier";
static NSString * const LockBLELockIdentifierKey = @"BLELockBleIdentifier";
static NSString * const LockElectronicKeyConnectedSNCacheKey = @"ElectronicKeyConnectedSNCache";

@interface NFCLockMainViewController ()

@property (weak, nonatomic) IBOutlet UITextView *logTextView;
@property (weak, nonatomic) IBOutlet UITextField *snTextFiled;
@property (weak, nonatomic) IBOutlet UITextField *pwTextField;
@property (weak, nonatomic) IBOutlet UITextField *macTextField;
@property (weak, nonatomic) IBOutlet UISegmentedControl *unlockTypeSegment;

@property (nonatomic, strong) UIBarButtonItem *connectButtonItem;

@property (weak, nonatomic) IBOutlet UIButton *versionButton;
@property (weak, nonatomic) IBOutlet UIButton *unlockCountButton;
@property (weak, nonatomic) IBOutlet UIButton *uploadMacButton;
@property (weak, nonatomic) IBOutlet UIButton *lockButton;
@property (weak, nonatomic) IBOutlet UIButton *queryConfigButton;
@property (weak, nonatomic) IBOutlet UIStackView *actionStackView;

@property (weak, nonatomic) IBOutlet UITextField *smSecretTextField;
@property (weak, nonatomic) IBOutlet UITextField *keySmSecretTextField;
@property (weak, nonatomic) IBOutlet UITextField *uidTextField;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *electronicKeyCredentialCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *lockCredentialCache;
@property (nonatomic, copy) NSString *cachedElectronicKeyIdentifier;
@property (nonatomic, copy) NSString *cachedElectronicKeySmSecret;
@property (nonatomic, copy) NSString *cachedElectronicKeySecret;
@property (nonatomic, copy) NSString *cachedLockSN;
@property (nonatomic, copy) NSString *cachedLockSecret;
@property (nonatomic, copy) NSString *cachedLockSmSecret;
@property (nonatomic, copy) NSString *cachedLockUID;
@property (nonatomic, copy) NSString *loadingElectronicKeyIdentifier;
@property (nonatomic, copy) NSString *loadingLockSN;
@property (nonatomic, assign) BOOL loadingElectronicKeyLockInfo;
@property (nonatomic, assign) NSUInteger chargingReadTaskIdentifier;
@property (nonatomic, assign) BOOL chargingReadInProgress;

@end

@implementation NFCLockMainViewController

- (void)dealloc {
    
    NSLog(@"NFCLockMainViewController dealloc");
    
    [[MkdLock sharedInstance] removeObserver:self forKeyPath:@"isBLEConnected"];
    [[MkdLock sharedInstance] removeObserver:self forKeyPath:@"isNFCConnected"];
    [[MkdLock sharedInstance] setOnElectronicKeyHeartBeatListener:nil];
    [[MkdLock sharedInstance] setOnBLELockActiveReportListener:nil];
    
//    [MkdNFCLock.sharedInstance disconnect];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.navigationItem.title = @"NFC Smart Lock";
    
    self.logTextView.layer.borderColor = UIColor.blackColor.CGColor;
    self.logTextView.layer.borderWidth = 0.5;
    
    [MkdLock sharedInstance].isLog = YES;

    NSString *version = [MkdLock sharedInstance].version;
    self.logTextView.text = [NSString stringWithFormat:@"SDK Version: %@", version];
    self.logTextView.text = [[MkdLock sharedInstance] initWithAppID:AppID appSecret:AppSecret] ? @"MakeID SDK authentication succeeded" : @"MakeID SDK authentication failed";
    
    [[MkdLock sharedInstance] addObserver:self forKeyPath:@"isBLEConnected" options:NSKeyValueObservingOptionNew context:nil];
    [[MkdLock sharedInstance] addObserver:self forKeyPath:@"isNFCConnected" options:NSKeyValueObservingOptionNew context:nil];
    
    [MkdLock sharedInstance].isLog = YES;
    [self setupElectronicKeyHeartBeatListener];
    [self setupBLELockActiveReportListener];
    
    [self reloadPageSubviews];
    
    [[MkdLock sharedInstance] setOnPhoneNFCSessionEventListener:^(PhoneNFCSessionEvent event, NSError * _Nullable error) {
        NSLog(event == PhoneNFCSessionEventDidBecomeActive ? @"开启弹窗" : @"关闭弹窗");
        if (event == PhoneNFCSessionEventDidInvalidate && self.chargingReadInProgress) {
            [self stopChargingReadWithMessage:@"Phone NFC reading finished"];
        }
        
    }];
}

+ (NSString *)statusLogTextWithLockInfo:(MkdLockInfo *)info {
    if (!info) {
        return @"Lock info is empty";
    }

    NSString *showInfo;
    
    if (info.isNewProtocol) {
        showInfo = [NSString stringWithFormat:@"Protocol: New\nNFC Power: %dmv\nRaw Status Code: %ld\nStatus Code: %d\nTemperature: %ld℃",
                info.nfcPower,
                (long)info.rawLockStatus,
                info.lockStatus,
                (long)info.temperature];
    } else {
        
        showInfo = [NSString stringWithFormat:@"Protocol: Old\nNFC Power: %dmv\nSolar Power: %dmv\nBattery Power: %dmv\nStatus Code: %d",
                info.nfcPower,
                info.solarEnergyPower,
                info.batteryPower,
                info.lockStatus];

    }
    NSLog(@"%@", showInfo);
    
    return showInfo;
}

+ (NSArray<NSString *> *)configurationActionTitles {
    return @[@"Query Network Config", @"Reset Network Config", @"Query Operation Log", @"Query Device Parameters"];
}

+ (NSString *)offlineAuthModeTextWithValue:(NSInteger)value {
    switch (value) {
        case 1:
            return @"Time";
        case 2:
            return @"Count";
        case 3:
            return @"Hybrid";
        default:
            return [NSString stringWithFormat:@"Unknown (%ld)", (long)value];
    }
}

+ (NSString *)dateTextFromOfflineAuthTimestamp:(NSTimeInterval)timestamp {
    if (timestamp <= 0) {
        return @"-";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp];
    return [formatter stringFromDate:date];
}

+ (NSString *)offlineAuthLogTextWithNodes:(NSArray *)nodes {
    if (![nodes isKindOfClass:NSArray.class] || nodes.count == 0) {
        return @"No offline authorization found";
    }
    
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithCapacity:nodes.count];
    [nodes enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, __unused BOOL * _Nonnull stop) {
        if (![obj isKindOfClass:MkdElectronicKeyOfflineAuth.class]) {
            return;
        }
        
        MkdElectronicKeyOfflineAuth *node = obj;
        NSString *startTime = [self dateTextFromOfflineAuthTimestamp:node.startDatetime];
        NSString *endTime = [self dateTextFromOfflineAuthTimestamp:node.endDatetime];
        
        NSString *text = [NSString stringWithFormat:@"Offline Auth %lu\nNID: %@\nUID: %@\nKID: %@\nLID: %@\nStart Time: %@\nEnd Time: %@\nCount: %@\nEnabled: %@\nAuth Mode: %@\nLock Key: %@\nLock smSecret: %@",
                          (unsigned long)(idx + 1),
                          @(node.nid),
                          node.uid ?: @"",
                          node.kid ?: @"",
                          node.lid ?: @"",
                          startTime,
                          endTime,
                          @(node.count),
                          node.enable ? @"Yes" : @"No",
                          [self offlineAuthModeTextWithValue:node.authMode],
                          node.password ?: @"",
                          node.lockSmSecret ?: @""];
        [items addObject:text];
    }];
    
    if (items.count == 0) {
        return @"No valid offline authorization found";
    }
    return [items componentsJoinedByString:@"\n\n"];
}

+ (NSString *)electronicKeyLogActionTextWithValue:(NSInteger)value {
    switch (value) {
        case 0x03:
            return @"Unlock";
        case 0x0C:
            return @"Lock";
        default:
            return [NSString stringWithFormat:@"Unknown (%ld)", (long)value];
    }
}

+ (NSString *)electronicKeyCacheLogTextWithNodes:(NSArray *)nodes {
    if (![nodes isKindOfClass:NSArray.class] || nodes.count == 0) {
        return @"No log read";
    }
    
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithCapacity:nodes.count];
    [nodes enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, __unused BOOL * _Nonnull stop) {
        if (![obj isKindOfClass:NSDictionary.class]) {
            return;
        }
        
        NSDictionary *node = (NSDictionary *)obj;
        NSString *timestamp = [self dateTextFromOfflineAuthTimestamp:[node[@"timestamp"] doubleValue]];
        NSString *text = [NSString stringWithFormat:@"Log %lu\nPacket No.: %@\nTime: %@\nAction: %@\nNID: %@\nUID: %@\nKID: %@\nLID: %@",
                          (unsigned long)(idx + 1),
                          node[@"packetIndex"] ?: @"",
                          timestamp,
                          [self electronicKeyLogActionTextWithValue:[node[@"action"] integerValue]],
                          node[@"nid"] ?: @"",
                          node[@"uid"] ?: @"",
                          node[@"kid"] ?: @"",
                          node[@"lid"] ?: @""];
        [items addObject:text];
    }];
    
    if (items.count == 0) {
        return @"No valid log read";
    }
    return [items componentsJoinedByString:@"\n\n"];
}

+ (NSString *)electronicKeyLockSNTextWithResult:(id)result {
    if ([result isKindOfClass:MkdLockBasicInfo.class]) {
        MkdLockBasicInfo *basicInfo = (MkdLockBasicInfo *)result;
        return [NSString stringWithFormat:@"Connected Lock SN: %@\nConnected Lock MAC: %@",
                basicInfo.sn.length > 0 ? basicInfo.sn : @"-",
                basicInfo.mac.length > 0 ? basicInfo.mac : @"-"];
    }
    
    if (![result isKindOfClass:NSDictionary.class]) {
        return @"Connected lock SN read successfully";
    }
    NSString *serialNo = [result[@"serialNo"] isKindOfClass:NSString.class] ? result[@"serialNo"] : @"";
    NSString *lockRandom = [result[@"lockRandom"] isKindOfClass:NSString.class] ? result[@"lockRandom"] : @"";
    return [NSString stringWithFormat:@"Connected Lock SN: %@\nLock Random Code: %@",
            serialNo.length > 0 ? serialNo : @"-",
            lockRandom.length > 0 ? lockRandom : @"-"];
}

+ (NSString *)electronicKeyLockStateTextWithResult:(NSDictionary *)result {
    if (![result isKindOfClass:NSDictionary.class]) {
        return @"Lock cylinder status is empty";
    }
    
    if (result[@"systemVoltageMv"]) {
        return [NSString stringWithFormat:@"Device: KY53E\nCommand Result: %@\nLock Status: %@\nTemperature: %@℃\nSystem Voltage: %@mv\nHall 1 Threshold: %@mv\nHall 1 Voltage: %@mv\nHall 2 Threshold: %@mv\nHall 2 Voltage: %@mv",
                result[@"cmdRes"] ?: @"",
                [result[@"isOpen"] boolValue] ? @"On" : @"Off",
                result[@"tempNow"] ?: @"",
                result[@"systemVoltageMv"] ?: @"",
                result[@"hall1ThresholdMv"] ?: @"",
                result[@"hall1VoltageMv"] ?: @"",
                result[@"hall2ThresholdMv"] ?: @"",
                result[@"hall2VoltageMv"] ?: @""];
    }
    
    return [NSString stringWithFormat:@"Device: KY53N\nNFC Voltage: %@mv\nNFC Status: %@\nTemperature: %@℃",
            result[@"nfcVolt"] ?: @"",
            result[@"nfcStatus"] ?: @"",
            result[@"tempNow"] ?: @""];
}

+ (NSString *)electronicKeySyncTimeTextWithResult:(NSDictionary *)result {
    if (![result isKindOfClass:NSDictionary.class]) {
        return @"Time synced successfully";
    }
    
    return [NSString stringWithFormat:@"Time Sync %@\nDevice Time: %@",
            [result[@"isSuccess"] boolValue] ? @"Success" : @"Failed",
            [self dateTextFromOfflineAuthTimestamp:[result[@"timestamp"] doubleValue]]];
}

+ (NSString *)electronicKeyOperationTextWithTitle:(NSString *)title result:(id)result {
    if (!result || result == [NSNull null]) {
        return [NSString stringWithFormat:@"%@ succeeded", title];
    }
    
    if ([result isKindOfClass:NSString.class]) {
        return [NSString stringWithFormat:@"%@ succeeded: %@", title, result];
    }
    
    if ([result isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)result;
        NSNumber *isSuccess = [dict[@"isSuccess"] isKindOfClass:NSNumber.class] ? dict[@"isSuccess"] : nil;
        NSNumber *status = [dict[@"status"] isKindOfClass:NSNumber.class] ? dict[@"status"] : nil;
        if (isSuccess || status) {
            return [NSString stringWithFormat:@"%@%@\nStatus: %@",
                    title,
                    isSuccess.boolValue ? @"Success" : @"Done",
                    status ?: @"-"];
        }
    }
    
    return [NSString stringWithFormat:@"%@ succeeded: %@", title, result];
}

+ (NSString *)bleLockActiveReportTextWithReport:(MkdBLELockActiveReport *)report {
    if (![report isKindOfClass:MkdBLELockActiveReport.class]) {
        return @"BLE lock active report data is empty";
    }
    
    return [NSString stringWithFormat:@"BLE Lock Active Report\nSerial No.: %d\nLock Status: %d\nBeam Status: %@\nType-C: %@\nBLE: %@\nOpen/Closed: %@",
            report.serialNumber,
            report.isLockOpen,
            report.isLockBeamDropped ? @"Dropped" : @"Normal",
            report.isTypeCConnected ? @"Connected" : @"Not connected",
            report.isBLEConnected ? @"Connected" : @"Not connected",
            report.isPowerOn ? @"On" : @"Off"];
}


- (NSString *)trimmedText:(NSString *)text {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

- (NSString *)manualLockSmSecret {
    NSString *text = [self trimmedText:self.smSecretTextField.text];
    return text.length > 0 ? text : nil;
}

- (NSString *)manualKeySmSecret {
    NSString *text = [self trimmedText:self.keySmSecretTextField.text];
    return text.length > 0 ? text : nil;
}

- (NSString *)manualUID {
    return [self currentElectronicKeyUID];
}

- (void)syncManualSecretsToSDKIfNeeded {
    NSString *keySmSecret = [self manualKeySmSecret];
    if (keySmSecret.length > 0) {
        self.cachedElectronicKeySmSecret = keySmSecret;
        [MkdLock.sharedInstance setElectronicKeySmSecret:keySmSecret];
    }
    NSString *lockSmSecret = [self manualLockSmSecret];
    if (lockSmSecret.length > 0) {
        self.cachedLockSmSecret = lockSmSecret;
    }
    NSString *secret = [self trimmedText:self.pwTextField.text];
    if (secret.length > 0) {
        self.cachedLockSecret = secret;
    }
    NSString *uid = [self trimmedText:self.uidTextField.text];
    if (uid.length > 0) {
        self.cachedLockUID = uid;
    }
}

- (BOOL)isLocalBLEMode {
    return self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodNFCRWIndex ||
           self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodBLELockIndex;
}

- (BOOL)isRemoteMode {
    return NO;
}

- (NSString *)currentBLEIdentifierKey {
    return self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodBLELockIndex ? LockBLELockIdentifierKey : LockNFCRWBLEIdentifierKey;
}

- (void)autoConnectSavedPeripheralWithIdentifier:(NSString *)identifier
                                         success:(void (^)(void))successBlock {
    if (identifier.length == 0 || MkdLock.sharedInstance.isBLEConnected) {
        return;
    }

    self.logTextView.text = @"Searching for previously connected devices...";

    __block BOOL didStartConnect = NO;
    WEAK;
    [MkdLock.sharedInstance searchDevicesForTimeout:10
                                            success:^(CBPeripheral * _Nonnull peripheral, NSNumber * _Nonnull RSSI) {
        if (didStartConnect || ![peripheral.identifier.UUIDString isEqualToString:identifier]) {
            return;
        }

        didStartConnect = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            NSString *deviceName = peripheral.name.length > 0 ? peripheral.name : identifier;
            self.logTextView.text = [NSString stringWithFormat:@"Found previous device %@, connecting...", deviceName];
        });

        [MkdLock.sharedInstance connectPeripheral:peripheral success:^(id  _Nonnull response) {
            if (successBlock) {
                successBlock();
            }
        } fail:^(id  _Nonnull response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                if (!self) {
                    return;
                }
                self.logTextView.text = [NSString stringWithFormat:@"Auto connect failed: %@", response ?: @"unknown error"];
            });
        }];
    } complete:^(__unused id  _Nonnull response) {
        if (didStartConnect) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            self.logTextView.text = @"No previously connected device found, please connect manually";
        });
    } fail:^(id  _Nonnull response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            self.logTextView.text = [NSString stringWithFormat:@"Failed to search previous devices: %@", response ?: @"unknown error"];
        });
    }];
}

- (BOOL)isElectronicKeyMode {
    return self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodNFCRWIndex &&
           [MkdLock sharedInstance].isBLEConnected &&
           [[MkdLock sharedInstance] isCurrentDeviceElectronicKey];
}

- (BOOL)shouldUseElectronicKeyUnlockForCurrentDevice {
    return self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodNFCRWIndex &&
           [MkdLock sharedInstance].electronicKeyDeviceType == MkdElectronicKeyDeviceTypeKY53E;
}

- (NSString *)currentElectronicKeyUnlockSmSecret {
    MkdElectronicKeyDeviceType deviceType = MkdLock.sharedInstance.electronicKeyDeviceType;
    if (deviceType == MkdElectronicKeyDeviceTypeKY53E) {
        return [self manualLockSmSecret] ?: @"";
    }
    if (deviceType == MkdElectronicKeyDeviceTypeKY53N) {
        return [self manualKeySmSecret] ?: @"";
    }
    return @"";
}

- (void)setupElectronicKeyHeartBeatListener {
    WEAK;
    [[MkdLock sharedInstance] setOnElectronicKeyHeartBeatListener:^(MkdElectronicKeyHeartBeat * _Nonnull heartBeat) {
        STRONG;
        if (!self) {
            return;
        }
        [self handleElectronicKeyHeartBeat:heartBeat];
    }];
}

- (void)setupBLELockActiveReportListener {
    WEAK;
    [[MkdLock sharedInstance] setOnBLELockActiveReportListener:^(MkdBLELockActiveReport * _Nonnull report) {
        STRONG;
        if (!self || self.unlockTypeSegment.selectedSegmentIndex != LockUnlockMethodBLELockIndex) {
            return;
        }
        [self appendLogText:[NFCLockMainViewController bleLockActiveReportTextWithReport:report]];
    }];
}

- (void)resetElectronicKeyCredentialCache {
    self.cachedElectronicKeyIdentifier = @"";
    self.cachedElectronicKeySmSecret = @"";
    self.cachedElectronicKeySecret = @"";
    self.loadingElectronicKeyIdentifier = @"";
    [self resetCurrentLockCredentialCache];
}

- (void)resetCurrentLockCredentialCache {
    self.cachedLockSN = @"";
    self.cachedLockSecret = @"";
    self.cachedLockSmSecret = @"";
    self.cachedLockUID = @"";
    self.loadingLockSN = @"";
    self.loadingElectronicKeyLockInfo = NO;
}

- (void)handleElectronicKeyBLEConnectedIfNeeded {
    if (![self isElectronicKeyMode]) {
        return;
    }
    [self syncManualSecretsToSDKIfNeeded];
    [self refreshElectronicKeyLockInfoWithPersistedFallback:YES];
}

- (NSDictionary *)cachedElectronicKeyCredentialForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    NSDictionary *credential = self.electronicKeyCredentialCache[identifier];
    return [credential isKindOfClass:NSDictionary.class] ? credential : nil;
}

- (NSDictionary *)cachedLockCredentialForSN:(NSString *)sn {
    if (sn.length == 0) {
        return nil;
    }
    NSDictionary *credential = self.lockCredentialCache[sn];
    return [credential isKindOfClass:NSDictionary.class] ? credential : nil;
}

- (NSString *)persistedConnectedLockSNForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return @"";
    }
    NSDictionary *snCache = [[NSUserDefaults standardUserDefaults] dictionaryForKey:LockElectronicKeyConnectedSNCacheKey];
    if (![snCache isKindOfClass:NSDictionary.class]) {
        return @"";
    }
    return [snCache[identifier] isKindOfClass:NSString.class] ? snCache[identifier] : @"";
}

- (void)persistConnectedLockSN:(NSString *)sn forIdentifier:(NSString *)identifier {
    if (sn.length == 0 || identifier.length == 0) {
        return;
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *storedCache = [userDefaults dictionaryForKey:LockElectronicKeyConnectedSNCacheKey];
    NSMutableDictionary *snCache = [storedCache isKindOfClass:NSDictionary.class] ? [storedCache mutableCopy] : [NSMutableDictionary dictionary];
    snCache[identifier] = sn;
    [userDefaults setObject:[snCache copy] forKey:LockElectronicKeyConnectedSNCacheKey];
}

- (void)clearPersistedConnectedLockSNCache {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:LockElectronicKeyConnectedSNCacheKey];
}

- (void)applyElectronicKeyCredential:(NSDictionary *)credential identifier:(NSString *)identifier syncToSDK:(BOOL)syncToSDK {
    NSString *secret = [credential[@"secret"] isKindOfClass:NSString.class] ? credential[@"secret"] : @"";
    NSString *smSecret = [credential[@"smSecret"] isKindOfClass:NSString.class] ? credential[@"smSecret"] : @"";
    if (identifier.length > 0) {
        NSMutableDictionary *cache = [NSMutableDictionary dictionary];
        if (secret.length > 0) {
            cache[@"secret"] = secret;
        }
        if (smSecret.length > 0) {
            cache[@"smSecret"] = smSecret;
        }
        if (cache.count > 0) {
            self.electronicKeyCredentialCache[identifier] = [cache copy];
        }
    }
    self.cachedElectronicKeyIdentifier = identifier ?: @"";
    self.cachedElectronicKeySecret = secret;
    self.cachedElectronicKeySmSecret = smSecret;
    if (syncToSDK && smSecret.length > 0) {
        [[MkdLock sharedInstance] setElectronicKeySmSecret:smSecret];
    }
}

- (void)handleElectronicKeyHeartBeat:(MkdElectronicKeyHeartBeat *)heartBeat {
    if (![self isElectronicKeyMode] || ![heartBeat isKindOfClass:MkdElectronicKeyHeartBeat.class]) {
        return;
    }
//    NSLog(@"%@", heartBeat);
    if (!heartBeat.isLockCylinderConnected) {
        [self resetCurrentLockCredentialCache];
        return;
    }
    
    [self refreshElectronicKeyLockInfoWithPersistedFallback:NO];
}

- (BOOL)hasPreparedLockCredentialForSN:(NSString *)sn {
    if (sn.length == 0 || ![sn isEqualToString:self.cachedLockSN]) {
        return NO;
    }
    return (self.cachedLockSecret.length > 0 ||
            self.cachedLockSmSecret.length > 0 ||
            self.cachedLockUID.length > 0);
}

- (void)applyPersistedElectronicKeyLockInfoIfNeeded {
    NSString *identifier = MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
    NSString *lockSN = [self persistedConnectedLockSNForIdentifier:identifier];
    if (lockSN.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.snTextFiled.text = lockSN;
        self.logTextView.text = @"Restored last connected lock SN; please verify the manually entered key and smSecret";
    });
    self.cachedLockSN = lockSN;
    [self syncManualSecretsToSDKIfNeeded];
}

- (void)handleElectronicKeyLockBasicInfo:(id)result {
    NSString *lockSN = @"";
    NSString *lockMAC = @"";
    if ([result isKindOfClass:MkdLockBasicInfo.class]) {
        MkdLockBasicInfo *basicInfo = (MkdLockBasicInfo *)result;
        lockSN = basicInfo.sn ?: @"";
        lockMAC = basicInfo.mac ?: @"";
    } else if ([result isKindOfClass:NSDictionary.class]) {
        NSDictionary *info = (NSDictionary *)result;
        lockSN = [info[@"serialNo"] isKindOfClass:NSString.class] ? info[@"serialNo"] : @"";
        lockMAC = [info[@"mac"] isKindOfClass:NSString.class] ? info[@"mac"] : @"";
    } else {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (lockSN.length > 0) {
            self.snTextFiled.text = lockSN;
        }
        if (lockMAC.length > 0) {
            self.macTextField.text = lockMAC;
        }
    });
    
    if (lockSN.length == 0) {
        return;
    }
    
    NSString *identifier = MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
    [self persistConnectedLockSN:lockSN forIdentifier:identifier];
    self.cachedLockSN = lockSN;
    [self syncManualSecretsToSDKIfNeeded];
}

- (void)refreshElectronicKeyLockInfoWithPersistedFallback:(BOOL)allowPersistedFallback {
    if (![self isElectronicKeyMode]) {
        return;
    }
    if (self.loadingElectronicKeyLockInfo) {
        return;
    }
    
    self.loadingElectronicKeyLockInfo = YES;
    WEAK;
    [[MkdLock sharedInstance] readElectronicKeyLockSNWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        STRONG;
        self.loadingElectronicKeyLockInfo = NO;
        [self handleElectronicKeyLockBasicInfo:obj];
    } failure:^(NSString * _Nullable errMsg) {
        STRONG;
        self.loadingElectronicKeyLockInfo = NO;
        if (allowPersistedFallback) {
            [self applyPersistedElectronicKeyLockInfoIfNeeded];
        }
    }];
}

- (void)fetchElectronicKeySmSecretIfNeeded {
    [self syncManualSecretsToSDKIfNeeded];
    NSString *smSecret = [self manualKeySmSecret];
    if (smSecret.length == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logTextView.text = @"Please enter the electronic key smSecret manually";
        });
        return;
    }
    self.cachedElectronicKeyIdentifier = MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
    self.cachedElectronicKeySmSecret = smSecret;
    [MkdLock.sharedInstance setElectronicKeySmSecret:smSecret];
}

- (void)applyLockCredential:(NSDictionary *)credential sn:(NSString *)sn updateUI:(BOOL)updateUI {
    NSString *secret = [credential[@"secret"] isKindOfClass:NSString.class] ? credential[@"secret"] : @"";
    NSString *smSecret = [credential[@"smSecret"] isKindOfClass:NSString.class] ? credential[@"smSecret"] : @"";
    NSString *uid = [credential[@"uid"] isKindOfClass:NSString.class] ? credential[@"uid"] : @"";
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    if (secret.length > 0) {
        cache[@"secret"] = secret;
    }
    if (smSecret.length > 0) {
        cache[@"smSecret"] = smSecret;
    }
    if (uid.length > 0) {
        cache[@"uid"] = uid;
    }
    if (sn.length > 0 && cache.count > 0) {
        self.lockCredentialCache[sn] = [cache copy];
    }
    
    self.cachedLockSN = sn ?: @"";
    self.cachedLockSecret = secret;
    self.cachedLockSmSecret = smSecret;
    self.cachedLockUID = uid;
    
    if (!updateUI) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sn.length > 0) {
            self.snTextFiled.text = sn;
        }
        if (secret.length > 0) {
            self.pwTextField.text = secret;
        }
        self.logTextView.text = (secret.length > 0 || smSecret.length > 0) ? @"Key obtained successfully" : @"Lock secret key not obtained";
    });
}

- (void)fetchLockCredentialWithSN:(NSString *)sn updateUI:(BOOL)updateUI {
    if (sn.length == 0) {
        return;
    }
    self.cachedLockSN = sn;
    [self syncManualSecretsToSDKIfNeeded];
    if (!updateUI) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.snTextFiled.text = sn;
        self.logTextView.text = @"SN read; please enter the secret key to continue";
    });
}

- (void)performElectronicKeyUnlock {
    [self syncManualSecretsToSDKIfNeeded];
    if (self.pwTextField.text.length <= 0) {
        [self.view makeToast:@"Enter the lock secret key before unlocking" duration:3.0f position:CSToastPositionCenter];
        return;
    }
    
    NSString *sn = [self trimmedText:self.snTextFiled.text].length > 0 ? [self trimmedText:self.snTextFiled.text] : self.cachedLockSN;
    if (sn.length == 0) {
        [self.view makeToast:@"Read or enter the lock SN first" duration:3.0f position:CSToastPositionCenter];
        return;
    }
    self.cachedLockSN = sn;
    
    NSString *smSecret = [self currentElectronicKeyUnlockSmSecret];
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    WEAK;
    [[MkdLock sharedInstance] unlockElectronicKeyWithUID:[self manualUID]
                                               secretKey:self.pwTextField.text
                                                smSecret:smSecret
                                          chargeProgress:^(CGFloat progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logTextView.text = [NSString stringWithFormat:@"Charging %.0f%%", progress];
        });
    } success:^(id  _Nonnull obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = @"Unlock succeeded";
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = [NSString stringWithFormat:@"Status code: %ld  -  %@", status, errMsg];
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (void)performElectronicKeyLock {
    [self syncManualSecretsToSDKIfNeeded];
    if (self.pwTextField.text.length <= 0) {
        [self.view makeToast:@"Enter the lock secret key before locking" duration:3.0f position:CSToastPositionCenter];
        return;
    }
    
    NSString *sn = [self trimmedText:self.snTextFiled.text].length > 0 ? [self trimmedText:self.snTextFiled.text] : self.cachedLockSN;
    if (sn.length == 0) {
        [self.view makeToast:@"Read or enter the lock SN first" duration:3.0f position:CSToastPositionCenter];
        return;
    }
    self.cachedLockSN = sn;
    
    NSString *smSecret = [self currentElectronicKeyUnlockSmSecret];
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    WEAK;
    [[MkdLock sharedInstance] lockElectronicKeyWithUID:[self manualUID]
                                             secretKey:self.pwTextField.text
                                              smSecret:smSecret
                                               success:^(id  _Nonnull obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = @"Lock succeeded";
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = [NSString stringWithFormat:@"Status code: %ld  -  %@", status, errMsg];
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (void)promptConnectBLEIfNeededWithAction:(void (^)(void))connectedAction {
    if (MkdLock.sharedInstance.isBLEConnected) {
        if (connectedAction) {
            connectedAction();
        }
        return;
    }

    WEAK;
    [UIAlertController showAlertInViewController:self
                                       withTitle:@"Notice"
                                         message:@"Please connect Bluetooth first"
                               cancelButtonTitle:@"Cancel"
                          destructiveButtonTitle:@"Connect"
                               otherButtonTitles:nil
                                        tapBlock:^(UIAlertController * _Nonnull controller,
                                                   UIAlertAction * _Nonnull action,
                                                   NSInteger buttonIndex) {
        if (buttonIndex == 1) {
            STRONG;
            [self goToConnectNFC_WR];
        }
    }];
}

- (BOOL)ensureBLEConnectedIfNeeded {
    if (![self isLocalBLEMode]) {
        return YES;
    }

    if (MkdLock.sharedInstance.isBLEConnected) {
        return YES;
    }

    [self promptConnectBLEIfNeededWithAction:nil];
    return NO;
}

- (void)showHUDForBLEModeIfNeeded {
    if ([self isLocalBLEMode]) {
        [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    }
}

- (void)resetAutoUnlockFlowText {
    self.logTextView.text = @"Auto unlock flow";
}

- (void)appendAutoUnlockFlowText:(NSString *)text {
    if (text.length == 0) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = self.logTextView.text ?: @"";
        NSString *flowText = [NSString stringWithFormat:@"• %@", text];
        self.logTextView.text = currentText.length > 0 ? [currentText stringByAppendingFormat:@"\n%@", flowText] : flowText;
        NSRange bottomRange = NSMakeRange(self.logTextView.text.length, 0);
        [self.logTextView scrollRangeToVisible:bottomRange];
    });
}

- (void)fetchAutoUnlockSecretWithBasicInfo:(MkdLockBasicInfo *)basicInfo
                                completion:(void (^)(NSString * _Nullable secret, NSString * _Nullable errMsg))completion {
    NSString *sn = basicInfo.sn ?: @"";
    NSString *mac = basicInfo.mac ?: @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sn.length > 0) {
            self.snTextFiled.text = sn;
        }
        if (mac.length > 0) {
            self.macTextField.text = mac;
        }
    });

    [self appendAutoUnlockFlowText:[NSString stringWithFormat:@"SN read successfully: %@", sn.length > 0 ? sn : @"-"]];
    if (mac.length > 0) {
        [self appendAutoUnlockFlowText:[NSString stringWithFormat:@"MAC read successfully: %@", mac]];
    }
    self.cachedLockSN = sn;
    [self syncManualSecretsToSDKIfNeeded];

    NSString *secret = [self trimmedText:self.pwTextField.text];
    if (secret.length < 8) {
        if (completion) {
            completion(nil, @"Enter a lock secret key of at least 8 characters first");
        }
        return;
    }
    [self appendAutoUnlockFlowText:@"Unlocking with the manually entered key"];
    if (completion) {
        completion(secret, nil);
    }
}

- (void)appendLogText:(NSString *)text {
    if (text.length == 0) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *currentText = self.logTextView.text ?: @"";
        self.logTextView.text = currentText.length > 0 ? [currentText stringByAppendingFormat:@"\n\n%@", text] : text;
        NSRange bottomRange = NSMakeRange(self.logTextView.text.length, 0);
        [self.logTextView scrollRangeToVisible:bottomRange];
    });
}

- (NSString *)currentElectronicKeyUID {
    NSString *uid = [self.uidTextField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (uid.length > 0) {
        return uid;
    }
    return MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
}

- (BOOL)prepareElectronicKeyActionWithSmSecretRequired:(BOOL)smSecretRequired pendingText:(NSString *)pendingText {
    if (self.unlockTypeSegment.selectedSegmentIndex != LockUnlockMethodNFCRWIndex) {
        [self.view makeToast:@"Switch to the external NFC device and connect the electronic key" duration:3.0f position:CSToastPositionCenter];
        return NO;
    }
    if (![self ensureBLEConnectedIfNeeded]) {
        return NO;
    }
    if (![MkdLock.sharedInstance isCurrentDeviceElectronicKey]) {
        [self.view makeToast:@"The connected device is not an electronic key" duration:3.0f position:CSToastPositionCenter];
        return NO;
    }
    [self syncManualSecretsToSDKIfNeeded];
    if (!smSecretRequired) {
        return YES;
    }
    if ([self manualKeySmSecret].length > 0) {
        return YES;
    }
    self.logTextView.text = pendingText.length > 0 ? pendingText : @"Please enter the electronic key smSecret manually";
    [self.view makeToast:@"Please enter the electronic key smSecret manually" duration:3.0f position:CSToastPositionCenter];
    return NO;
}

- (void)pushOfflineAuthViewController {
    [self syncManualSecretsToSDKIfNeeded];
    LockOfflineAuthViewController *offlineAuthVC = [[LockOfflineAuthViewController alloc] init];
    offlineAuthVC.keySN = MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
    offlineAuthVC.keySmSecret = [self manualKeySmSecret] ?: @"";
    offlineAuthVC.lockSN = self.snTextFiled.text.length > 0 ? self.snTextFiled.text : self.cachedLockSN;
    offlineAuthVC.lockPassword = [self trimmedText:self.pwTextField.text];
    offlineAuthVC.lockSmSecret = [self manualLockSmSecret] ?: @"";
    offlineAuthVC.uid = [self trimmedText:self.uidTextField.text];
    [self.navigationController pushViewController:offlineAuthVC animated:YES];
}

- (void)queryAllElectronicKeyOfflineAuth {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry the offline auth query later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Querying offline authorization...";
    
    WEAK;
    [MkdLock.sharedInstance queryAllElectronicKeyOfflineAuthWithSuccess:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController offlineAuthLogTextWithNodes:obj];
        });
    } progress:^(CGFloat progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            self.logTextView.text = [NSString stringWithFormat:@"Querying offline authorization: %.0f", progress];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to query offline authorization: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)deleteAllElectronicKeyOfflineAuth {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry the offline auth deletion later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Deleting all offline authorizations...";
    
    WEAK;
    [MkdLock.sharedInstance deleteAllElectronicKeyOfflineAuthWithSuccess:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyOperationTextWithTitle:@"Delete All Offline Authorizations" result:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to delete all offline authorizations: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)syncElectronicKeyTimeAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry time sync later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Syncing electronic key time...";
    
    WEAK;
    [MkdLock.sharedInstance syncElectronicKeyTime:[NSDate date].timeIntervalSince1970 success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeySyncTimeTextWithResult:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to sync time: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)readElectronicKeyLockSNAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:NO pendingText:nil]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Reading connected lock SN...";
    
    WEAK;
    [MkdLock.sharedInstance readElectronicKeyLockSNWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyLockSNTextWithResult:obj];
            [self handleElectronicKeyLockBasicInfo:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to read connected lock SN: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)readElectronicKeyLockStateAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:NO pendingText:nil]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Reading connected lock cylinder status...";
    
    WEAK;
    [MkdLock.sharedInstance readElectronicKeyLockStateWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyLockStateTextWithResult:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to read lock cylinder status: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)rebootElectronicKeyAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry rebooting the ekey later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Rebooting electronic key...";
    
    WEAK;
    [MkdLock.sharedInstance rebootElectronicKeyWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyOperationTextWithTitle:@"Reboot Electronic Key" result:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to reboot electronic key: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)readElectronicKeyCacheLogAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry log reading later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Reading logs...";
    
    WEAK;
    [MkdLock.sharedInstance readElectronicKeyCacheLogWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyCacheLogTextWithNodes:obj];
        });
    } progress:^(CGFloat progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            self.logTextView.text = [NSString stringWithFormat:@"Reading logs: %.0f", progress];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to read logs: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)clearElectronicKeyCacheLogAction {
    if (![self prepareElectronicKeyActionWithSmSecretRequired:YES pendingText:@"Fetching ekey smSecret; retry log clearing later"]) {
        return;
    }
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    self.logTextView.text = @"Clearing logs...";
    
    WEAK;
    [MkdLock.sharedInstance clearElectronicKeyCacheLogWithUID:[self currentElectronicKeyUID] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NFCLockMainViewController electronicKeyOperationTextWithTitle:@"Clear Logs" result:obj];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to clear logs: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (void)showOfflineAuthActionSheetFromSender:(UIButton *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Offline Authorization"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    WEAK;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Offline Authorization" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self pushOfflineAuthViewController];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Query All Offline Authorizations" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self queryAllElectronicKeyOfflineAuth];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Delete All Offline Authorizations" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self deleteAllElectronicKeyOfflineAuth];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Sync Time" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self syncElectronicKeyTimeAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Read Connected Lock SN" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self readElectronicKeyLockSNAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Lock Cylinder Status" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self readElectronicKeyLockStateAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Reboot Electronic Key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self rebootElectronicKeyAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Read Logs" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self readElectronicKeyCacheLogAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear Logs" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self clearElectronicKeyCacheLogAction];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender ?: self.view;
        popover.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.f, 1.f);
    }
    
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
     
//    if ([MkdLock sharedInstance].isBLEConnected) {
//        [[MkdLock sharedInstance] disconnect];
//    }
}

#pragma mark - 按钮点击事件
- (IBAction)clickGetSNButtonAction:(UIButton *)sender {
        
    WEAK;
    
    if ([self isLocalBLEMode]) {
        
        if (!MkdLock.sharedInstance.isBLEConnected) {
            [self promptConnectBLEIfNeededWithAction:nil];
            
            return;
        }
        
        if ([self isLocalBLEMode]) {
            
            [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{

        STRONG;
        self.logTextView.text = @"Getting SN...";
    });

    [[MkdLock sharedInstance] readLockBasicInfoSuccess:^(MkdLockBasicInfo *basicInfo) {
        
        dispatch_async(dispatch_get_main_queue(), ^{

            STRONG;
            self.snTextFiled.text  = basicInfo.sn;
            self.macTextField.text = basicInfo.mac;
            self.logTextView.text  = [NSString stringWithFormat:@"Got SN: %@", basicInfo.sn];
            self.logTextView.text  = [NSString stringWithFormat:@"Got MAC: %@", basicInfo.mac];
                        
            [self getLockSecret:basicInfo.sn];
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            
        });

    } failure:^(NSString * _Nullable error) {

        dispatch_async(dispatch_get_main_queue(), ^{

            STRONG;
            self.logTextView.text = error;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (IBAction)clickUnlockButon:(UIButton *)sender {
    
    WEAK;
    
    NSLog(@"开锁~~~~");
    [self syncManualSecretsToSDKIfNeeded];
    
    if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodNFCRWIndex &&
        ![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    
    if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodPhoneNFCIndex ||
        self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodBLELockIndex) {
        
        if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodBLELockIndex &&
            ![self ensureBLEConnectedIfNeeded]) {
            return;
        }
        
        if (self.pwTextField.text.length <= 0) {
            
            [self.view makeToast:@"Enter the secret key before unlocking" duration:3.0f position:CSToastPositionCenter];
            
            return;
        }

        [[MkdLock sharedInstance] unlockWithSecretKey:self.pwTextField.text
                                             smSecret:[self manualLockSmSecret]
                                       chargeProgress:^(NSInteger progress) {
            
            self.logTextView.text = [NSString stringWithFormat:@"Charging %ld%%", (long)progress];
            
        } success:^(id  _Nonnull obj) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = @"Unlock succeeded";
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
            
        } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
         
            if (status == UnlockFailStatusCheckFail) {
                NSLog(@"检查状态失败");
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = [NSString stringWithFormat:@"Status code: %ld  -  %@", status, errMsg];
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
        }];
        
    } else if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodNFCRWIndex) {//外接NFC开锁
        
        if (!MkdLock.sharedInstance.isBLEConnected) {
            
            [UIAlertController showAlertInViewController:self withTitle:@"Notice" message:@"Please connect Bluetooth first" cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Connect" otherButtonTitles:nil tapBlock:^(UIAlertController * _Nonnull controller, UIAlertAction * _Nonnull action, NSInteger buttonIndex) {
                STRONG;
                if (buttonIndex == 1) {
                    [self goToConnectNFC_WR];
                }
            }];
            
            return;
        }

        if (self.pwTextField.text.length <= 0) {
            
            [self.view makeToast:@"Enter the secret key before unlocking" duration:3.0f position:CSToastPositionCenter];
            
            return;
        }
        
        [MBProgressHUD showHUDAddedTo:self.view animated:YES];
        
        [[MkdLock sharedInstance] unlockWithSecretKey:self.pwTextField.text
                                             smSecret:[self manualLockSmSecret]
                                       chargeProgress:^(NSInteger progress) {
         
            self.logTextView.text = [NSString stringWithFormat:@"Charging %ld%%", (long)progress];
            
        } success:^(id  _Nonnull obj) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = @"Unlock succeeded";
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
            
        } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
         
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = [NSString stringWithFormat:@"Status code: %ld  -  %@", status, errMsg];
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
        }];
        
    } else if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodRemoteIndex) {
        [self.view makeToast:@"Offline demo does not support remote APIs; switch to Phone NFC/Reader/BLE lock and enter the key manually" duration:3.0f position:CSToastPositionCenter];
    }
    
}
//自动开锁
- (IBAction)clickAutoUnlockButon:(UIButton *)sender {
    if ([self isRemoteMode]) {
        [self.view makeToast:@"Auto unlock only supports local NFC/Bluetooth links" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }

    if ([MkdLock.sharedInstance isCurrentDeviceElectronicKey]) {
        [self.view makeToast:@"For electronic keys, use the ekey unlock button" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    [self resetAutoUnlockFlowText];
    [self appendAutoUnlockFlowText:@"Starting auto unlock"];

    WEAK;
    void (^unlockWithSecret)(NSString *, BOOL) = ^(NSString *secret, BOOL shouldManagePhoneNFCSession) {
        STRONG;
        if (!self) {
            return;
        }

        if (secret.length < 8) {
            NSString *message = @"No valid unlock key obtained";
            [self appendAutoUnlockFlowText:message];
            if (shouldManagePhoneNFCSession) {
                [[MkdLock sharedInstance] invalidatePhoneNFCSessionWithMessage:message];
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            return;
        }

        [self appendAutoUnlockFlowText:@"Key obtained; sending unlock command"];
        [[MkdLock sharedInstance] unlockWithSecretKey:secret smSecret:[self manualLockSmSecret] chargeProgress:^(NSInteger progress) {
            STRONG;
            [self appendAutoUnlockFlowText:[NSString stringWithFormat:@"Charging: %ld%%", (long)progress]];
        } success:^(__unused id  _Nullable obj) {
            STRONG;
            [self appendAutoUnlockFlowText:@"Unlock succeeded"];
            if (shouldManagePhoneNFCSession) {
                [[MkdLock sharedInstance] closePhoneNFCSessionWithMessage:@"Unlock succeeded"];
            }
        } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
            STRONG;
            NSString *message = [NSString stringWithFormat:@"Unlock failed: status code %ld, %@", (long)status, errMsg ?: @"unknown error"];
            [self appendAutoUnlockFlowText:message];
            if (shouldManagePhoneNFCSession) {
                [[MkdLock sharedInstance] invalidatePhoneNFCSessionWithMessage:errMsg ?: @"Unlock failed"];
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        }];
    };

    void (^handleBasicInfo)(MkdLockBasicInfo *, BOOL) = ^(MkdLockBasicInfo *basicInfo, BOOL shouldManagePhoneNFCSession) {
        STRONG;
        if (!self) {
            return;
        }

        [self fetchAutoUnlockSecretWithBasicInfo:basicInfo completion:^(NSString * _Nullable secret, NSString * _Nullable errMsg) {
            STRONG;
            if (!self) {
                return;
            }

            if (secret.length < 8) {
                NSString *message = errMsg ?: @"Failed to obtain lock secret key";
                [self appendAutoUnlockFlowText:message];
                if (shouldManagePhoneNFCSession) {
                    [[MkdLock sharedInstance] invalidatePhoneNFCSessionWithMessage:message];
                }
                [MBProgressHUD hideHUDForView:self.view animated:YES];
                return;
            }

            unlockWithSecret(secret, shouldManagePhoneNFCSession);
        }];
    };

    if (self.unlockTypeSegment.selectedSegmentIndex == LockUnlockMethodPhoneNFCIndex) {
        [self appendAutoUnlockFlowText:@"Opening phone NFC session"];
        [[MkdLock sharedInstance] beginPhoneNFCSessionSuccess:^(__unused id  _Nullable obj) {
            STRONG;
            [self appendAutoUnlockFlowText:@"Session connected; reading SN"];
            [[MkdLock sharedInstance] readLockBasicInfoSuccess:^(id  _Nullable obj) {

                MkdLockBasicInfo *basicInfo = [obj isKindOfClass:MkdLockBasicInfo.class] ? obj : nil;
                handleBasicInfo(basicInfo, YES);
            } failure:^(NSString * _Nullable errMsg) {
                STRONG;
                NSString *message = errMsg ?: @"Failed to read SN";
                [self appendAutoUnlockFlowText:message];
                [[MkdLock sharedInstance] invalidatePhoneNFCSessionWithMessage:message];
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            }];
        } failure:^(NSString * _Nullable errMsg) {
            STRONG;
            [self appendAutoUnlockFlowText:[NSString stringWithFormat:@"Session connection failed: %@", errMsg ?: @"unknown error"]];
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        }];
        return;
    }

    [self appendAutoUnlockFlowText:@"Waiting for NFC/lock connection and reading SN"];
    [[MkdLock sharedInstance] readLockBasicInfoSuccess:^(id  _Nullable obj) {

        MkdLockBasicInfo *basicInfo = [obj isKindOfClass:MkdLockBasicInfo.class] ? obj : nil;
        handleBasicInfo(basicInfo, NO);
    } failure:^(NSString * _Nullable errMsg) {
        STRONG;
        [self appendAutoUnlockFlowText:[NSString stringWithFormat:@"Failed to read SN: %@", errMsg ?: @"unknown error"]];
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    }];
}

- (IBAction)clickEkeyUnlockButtonAction:(UIButton *)sender {
    if (self.pwTextField.text.length <= 0) {
        [self.view makeToast:@"Enter the secret key before unlocking" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    if (![self prepareElectronicKeyActionWithSmSecretRequired:(MkdLock.sharedInstance.electronicKeyDeviceType == MkdElectronicKeyDeviceTypeKY53N)
                                                  pendingText:@"Fetching ekey smSecret; retry unlock later"]) {
        return;
    }

    [self performElectronicKeyUnlock];
}

- (IBAction)clickEkeyLockButtonAction:(UIButton *)sender {
    if (self.pwTextField.text.length <= 0) {
        [self.view makeToast:@"Enter the secret key before locking" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    if (![self prepareElectronicKeyActionWithSmSecretRequired:(MkdLock.sharedInstance.electronicKeyDeviceType == MkdElectronicKeyDeviceTypeKY53N)
                                                  pendingText:@"Fetching ekey smSecret; retry lock later"]) {
        return;
    }

    [self performElectronicKeyLock];
}

- (IBAction)clickLockButtonAction:(UIButton *)sender {
    WEAK;

    if ([self isRemoteMode]) {
        [self.view makeToast:@"Remote operation does not support locking yet" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    if ([self isLocalBLEMode]) {
        if (!MkdLock.sharedInstance.isBLEConnected) {
            [self promptConnectBLEIfNeededWithAction:nil];
            return;
        }
    }
    
    if (self.pwTextField.text.length <= 0) {
        [self.view makeToast:@"Enter the secret key before locking" duration:3.0f position:CSToastPositionCenter];
        return;
    }

    [MBProgressHUD showHUDAddedTo:self.view animated:YES];

    [[MkdLock sharedInstance] lockWithSecretKey:self.pwTextField.text smSecret:[self manualLockSmSecret] success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = @"Lock succeeded";
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    } failure:^(UnlockFailStatus status, NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = [NSString stringWithFormat:@"Status code: %ld  -  %@", status, errMsg];
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (IBAction)clickChargingButtonAction:(UIButton *)sender {
    if (self.chargingReadInProgress) {
        return;
    }

    self.chargingReadInProgress = YES;
    self.chargingReadTaskIdentifier += 1;
    NSUInteger taskIdentifier = self.chargingReadTaskIdentifier;
    self.logTextView.text = @"Phone NFC charging read started";

    [MkdLock.sharedInstance beginPhoneNFCSessionSuccess:^(__unused id  _Nullable obj) {
        [self readChargingElectricityWithTaskIdentifier:taskIdentifier];
    } failure:^(NSString * _Nullable errMsg) {
        [self stopChargingReadWithMessage:[NSString stringWithFormat:@"Phone NFC connection failed: %@", errMsg ?: @"unknown error"]];
    }];
}

- (void)readChargingElectricityWithTaskIdentifier:(NSUInteger)taskIdentifier {
    if (!self.chargingReadInProgress || self.chargingReadTaskIdentifier != taskIdentifier) {
        return;
    }

    [[MkdLock sharedInstance] readStatusAndElectricitySuccess:^(MkdLockInfo * _Nullable info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.chargingReadInProgress || self.chargingReadTaskIdentifier != taskIdentifier) {
                return;
            }

            NSString *powerText = [NSString stringWithFormat:@"NFC Power: %dmv", info.nfcPower];
            NSLog(@"%@", powerText);
            self.logTextView.text = [self.logTextView.text stringByAppendingFormat:@"\n%@", powerText];
            [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length, 0)];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self readChargingElectricityWithTaskIdentifier:taskIdentifier];
            });
        });
    } failure:^(NSString * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.chargingReadInProgress || self.chargingReadTaskIdentifier != taskIdentifier) {
                return;
            }

            NSString *errorText = [NSString stringWithFormat:@"Failed to read power: %@", error ?: @"unknown error"];
            NSLog(@"%@", errorText);
            self.logTextView.text = [self.logTextView.text stringByAppendingFormat:@"\n%@", errorText];
            [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length, 0)];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self readChargingElectricityWithTaskIdentifier:taskIdentifier];
            });
        });
    }];
}

- (void)stopChargingReadWithMessage:(NSString *)message {
    if (!self.chargingReadInProgress) {
        return;
    }

    self.chargingReadInProgress = NO;
    self.chargingReadTaskIdentifier += 1;
    if (message.length > 0) {
        self.logTextView.text = [self.logTextView.text stringByAppendingFormat:@"\n%@", message];
        [self.logTextView scrollRangeToVisible:NSMakeRange(self.logTextView.text.length, 0)];
    }
}

- (IBAction)clickGetStatusButtonAction:(UIButton *)sender {
    
    if (! [self isRemoteMode]) {
        
        WEAK;
        if ([self isLocalBLEMode]) {
            
            if (!MkdLock.sharedInstance.isBLEConnected) {
                [self promptConnectBLEIfNeededWithAction:nil];
                
                return;
            }
            
            if ([self isLocalBLEMode]) {
                
                [MBProgressHUD showHUDAddedTo:self.view animated:YES];
            }
        }
        
        self.logTextView.text = @"Getting lock info";
        
        [[MkdLock sharedInstance] readStatusAndElectricitySuccess:^(MkdLockInfo * _Nullable obj) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = [NFCLockMainViewController statusLogTextWithLockInfo:obj];
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
            
        } failure:^(NSString * _Nullable error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                STRONG;
                self.logTextView.text = error;
                
                [MBProgressHUD hideHUDForView:self.view animated:YES];
            });
        }];
    }
}

- (IBAction)clickGetVersionButtonAction:(UIButton *)sender {
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    self.logTextView.text = @"Getting FW version";
    
    [[MkdLock sharedInstance] readFWVersionSuccess:^(id  _Nullable obj) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = [NSString stringWithFormat:@"FW version: %@", obj];
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
    } failure:^(NSString * _Nullable error) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = error;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (IBAction)clickReadUnlockTimesAction:(UIButton *)sender {
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    [[MkdLock sharedInstance] readUnlockTimesSuccess:^(NSNumber * _Nullable times) {
            
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = [NSString stringWithFormat:@"Unlock count: %@", times];
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
    } failure:^(NSString * _Nullable errMsg) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            self.logTextView.text = errMsg;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (IBAction)clickUploadMacButtonAction:(UIButton *)sender {
    
    if (self.snTextFiled.text.length <= 0 ||
        self.macTextField.text.length <= 0) {
        
        [self.view makeToast:@"Get the SN and MAC first" duration:3.0f position:CSToastPositionCenter];
        
        return;
    }
    
    self.uploadMacButton.enabled = NO;
    
    [self uploadMACAddress:self.snTextFiled.text mac:self.macTextField.text];
}

- (IBAction)tapBgViewGesture:(UITapGestureRecognizer *)sender {
    
    [self.view endEditing:YES];
}

- (IBAction)ClickClearButtonAction:(UIButton *)sender {
    
    self.logTextView.text  = nil;
    self.snTextFiled.text  = nil;
    self.macTextField.text = nil;
    self.pwTextField.text  = nil;
    self.smSecretTextField.text = nil;
    self.keySmSecretTextField.text = nil;
    self.uidTextField.text = nil;
    [self.electronicKeyCredentialCache removeAllObjects];
    [self.lockCredentialCache removeAllObjects];
    [self clearPersistedConnectedLockSNCache];
    [self resetElectronicKeyCredentialCache];
}

- (IBAction)clickUnlockMethodSegmentAction:(UISegmentedControl *)sender {
        
    if (sender.selectedSegmentIndex == LockUnlockMethodPhoneNFCIndex) {
        
        self.navigationItem.rightBarButtonItem = nil;
        
        [MkdLock.sharedInstance disconnect];
        
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_Phone;
                
    } else if (sender.selectedSegmentIndex == LockUnlockMethodNFCRWIndex) {
        
        self.navigationItem.rightBarButtonItem = self.connectButtonItem;
        
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_BLE;
        
        DEF_SHOW_TOAST(@"Please connect Bluetooth");
        
    } else if (sender.selectedSegmentIndex == LockUnlockMethodRemoteIndex) {
        [MkdLock.sharedInstance disconnect];
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_Phone;
        DEF_SHOW_TOAST(@"Offline demo: enter the key manually");
    } else if (sender.selectedSegmentIndex == LockUnlockMethodBLELockIndex) {
        
        self.navigationItem.rightBarButtonItem = self.connectButtonItem;
        
        MkdLock.sharedInstance.unlockMethod = UnlockMethodBLELock;
        
        DEF_SHOW_TOAST(@"Please connect the BLE lock");
    }
    
    [[NSUserDefaults standardUserDefaults] setInteger:sender.selectedSegmentIndex forKey:@"NFCUnlockMethod"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [self reloadPageSubviews];
}

- (IBAction)clickQueryConfigButtonAction:(UIButton *)sender {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Query Config"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSString *> *titles = [NFCLockMainViewController configurationActionTitles];
    WEAK;
    [sheet addAction:[UIAlertAction actionWithTitle:titles[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self clickQueryNetConfigButtonAction:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:titles[1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self clickResetNetConfigButtonAction:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:titles[2] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self clickQueryOperationLogButtonAction:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:titles[3] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * _Nonnull action) {
        STRONG;
        [self clickQueryDeviceParamButtonAction:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender ?: self.view;
        popover.sourceRect = sender ? sender.bounds : CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1.f, 1.f);
    }

    [self presentViewController:sheet animated:YES completion:nil];
}
//查询网络配置
- (IBAction)clickQueryNetConfigButtonAction:(UIButton *)sender {
    
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    [MkdLock.sharedInstance queryNetworkConfigSuccess:^(NBLockStatus status, int csq) {
                            
        switch (status) {
            case NBLockStatusHibernate: {
                self.logTextView.text = @"NB lock status: hibernating";
                break;
            }
            case NBLockStatusPowerOn: {
                self.logTextView.text = @"NB lock status: powered on";
                break;
            }
            case NBLockStatusSelfTesting: {
                self.logTextView.text = @"NB lock status: self-testing";
                break;
            }
            case NBLockStatusConnecting: {
                self.logTextView.text = @"NB lock status: connecting";
                break;
            }
            case NBLockStatusConnected: {
                self.logTextView.text = @"NB lock status: connected";
                break;
            }
                
            default:
                break;
        }
        
        self.logTextView.text = [NSString stringWithFormat:@"Network signal strength: %d", csq];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
    } fail:^(NSString * _Nullable errMsg) {
       
        self.logTextView.text = errMsg;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

//重置网络配置
- (IBAction)clickResetNetConfigButtonAction:(UIButton *)sender {
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    [MkdLock.sharedInstance resetNetWorkConfigSuccess:^(id  _Nullable obj) {
       
        self.logTextView.text = @"Reset succeeded";
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
    } fail:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
        self.logTextView.text = errMsg;
    }];
}

//查询操作日志
- (IBAction)clickQueryOperationLogButtonAction:(UIButton *)sender {
    
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    [MkdLock.sharedInstance queryOperationLogSuccess:^(MkdLockLog * _Nonnull log) {
       
        self.logTextView.text = [NSString stringWithFormat:@"Current server address: %@", log.serverType == 0 ? @"Default address" : @"Configured address"];
        self.logTextView.text = [NSString stringWithFormat:@"Last network connection result: %@", log.networkTag == 0 ? @"Success" : @"Failed"];
        self.logTextView.text = [NSString stringWithFormat:@"AT command number of last network failure: %d", log.failNum];
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    } fail:^(NSString * _Nullable errMsg) {
        
        self.logTextView.text = errMsg;
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}
//查询设备参数
- (IBAction)clickQueryDeviceParamButtonAction:(UIButton *)sender {
    WEAK;
    if (![self ensureBLEConnectedIfNeeded]) {
        return;
    }
    [self showHUDForBLEModeIfNeeded];
    
    [MkdLock.sharedInstance queryDeviceParametersSuccess:^(MkdNFCLockParam * _Nonnull param) {
        
        self.logTextView.text = [NSString stringWithFormat:@"Network reconnection interval: %d", param.reconTimeInteval];
        self.logTextView.text = [NSString stringWithFormat:@"Network keep-alive time: %d", param.activeTime];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
        
    } fail:^(NSString * _Nullable errMsg) {
        self.logTextView.text = errMsg;
        dispatch_async(dispatch_get_main_queue(), ^{
            STRONG;
            
            [MBProgressHUD hideHUDForView:self.view animated:YES];
        });
    }];
}

- (IBAction)clickOfflineAuthAction:(UIButton *)sender {
    [self showOfflineAuthActionSheetFromSender:sender];
}

#pragma mark - observe
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        });
        return;
    }
    
    if ([keyPath isEqualToString:@"isBLEConnected"]) {
        
        if ([self isLocalBLEMode]) {
            
            BOOL isConnected = [MkdLock sharedInstance].isBLEConnected;
        
            
            NSString *connectStatus = isConnected ? @"BLE connected" : @"BLE Not Connected";
                                
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [self.connectButtonItem setTitle:connectStatus];
                self.connectButtonItem.tintColor = isConnected ? UIColorFromRGB(0x32CD32) : UIColor.blackColor;
                
                self.logTextView.text = connectStatus;
                
                if (!isConnected) {
                    [self resetElectronicKeyCredentialCache];
                    [MBProgressHUD hideHUDForView:self.view animated:YES];
                }
            });
            
            if (isConnected) {
                [self handleElectronicKeyBLEConnectedIfNeeded];
            }
        }
    } else if ([keyPath isEqualToString:@"isNFCConnected"]) {
        
        if (MkdLock.sharedInstance.unlockMethod == UnlockMethodNFC_BLE) {
            
            BOOL isNFCConnected = [MkdLock sharedInstance].isNFCConnected;
                                
            dispatch_async(dispatch_get_main_queue(), ^{
                
                self.logTextView.text = isNFCConnected ? @"NFC discover - connected" : @"NFC discover - disconnected";
            });
        }
    }
}
#pragma mark -Other Method
/**
 获取sn对应的密钥
 */
- (void)getLockSecret:(NSString *)sn {
    if (!sn) {
        NSLog(@"SN为空");
        return;
    }
    self.cachedLockSN = sn;
    [self syncManualSecretsToSDKIfNeeded];
}
/**
 上传sn对应的mac
 */
- (void)uploadMACAddress:(NSString *)sn mac:(NSString *)mac {
    self.uploadMacButton.enabled = YES;
    self.logTextView.text = @"Offline demo does not upload MAC; save the SN/MAC locally";
}

- (void)goToConnectNFC_WR {
    
    if ([MkdLock sharedInstance].isBLEConnected) {
        
        [UIAlertController showAlertInViewController:self withTitle:@"Notice" 
                                             message:@"Disconnect and search?"
                                   cancelButtonTitle:@"Cancel"
                              destructiveButtonTitle:@"OK"
                                   otherButtonTitles:nil
                                            tapBlock:^(UIAlertController * _Nonnull controller, UIAlertAction * _Nonnull action, NSInteger buttonIndex) {
           
            if (buttonIndex == 1) {
                
                [[MkdLock sharedInstance] disconnect];
                
                BLEConnectViewController *bleConnectVC = [[BLEConnectViewController alloc] init];
                
                
                [self.navigationController pushViewController:bleConnectVC animated:YES];
            }
        }];
        
        return;
    }
    
    BLEConnectViewController *bleConnectVC = [[BLEConnectViewController alloc] init];
    
    
    [self.navigationController pushViewController:bleConnectVC animated:YES];
}

- (void)reloadPageSubviews {
    
    UnlockMethod method = [[NSUserDefaults standardUserDefaults] integerForKey:@"NFCUnlockMethod"];
    
    [self.unlockTypeSegment setSelectedSegmentIndex:method];
    
    NSInteger selectedIndex = self.unlockTypeSegment.selectedSegmentIndex;
    
    if (selectedIndex == LockUnlockMethodPhoneNFCIndex) {
        
        self.navigationItem.rightBarButtonItem = nil;
                
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_Phone;
        
    } else if (selectedIndex == LockUnlockMethodNFCRWIndex) {
        
        self.navigationItem.rightBarButtonItem = self.connectButtonItem;
        
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_BLE;
        
        NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:LockNFCRWBLEIdentifierKey];
        
        if (identifier.length > 0) {
            [self autoConnectSavedPeripheralWithIdentifier:identifier success:^{
                [self handleElectronicKeyBLEConnectedIfNeeded];
            }];
        }
    } else if (selectedIndex == LockUnlockMethodRemoteIndex) {
        self.navigationItem.rightBarButtonItem = nil;
        MkdLock.sharedInstance.unlockMethod = UnlockMethodNFC_Phone;
        self.logTextView.text = @"Offline demo does not support remote APIs; enter the key manually and unlock locally";
    } else if (selectedIndex == LockUnlockMethodBLELockIndex) {
        
        self.navigationItem.rightBarButtonItem = self.connectButtonItem;
        
        MkdLock.sharedInstance.unlockMethod = UnlockMethodBLELock;
        
        NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:LockBLELockIdentifierKey];
        
        if (identifier.length > 0) {
            [self autoConnectSavedPeripheralWithIdentifier:identifier success:nil];
        }
    }
}

#pragma mark -Setter/Getter
- (UIBarButtonItem *)connectButtonItem {
    if (!_connectButtonItem) {
        _connectButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"BLE Not Connected" style:UIBarButtonItemStylePlain target:self action:@selector(goToConnectNFC_WR)];
        _connectButtonItem.tintColor = UIColor.blackColor;
    }
    return _connectButtonItem;
}

- (NSMutableDictionary<NSString *,NSDictionary *> *)electronicKeyCredentialCache {
    if (!_electronicKeyCredentialCache) {
        _electronicKeyCredentialCache = [NSMutableDictionary dictionary];
    }
    return _electronicKeyCredentialCache;
}

- (NSMutableDictionary<NSString *,NSDictionary *> *)lockCredentialCache {
    if (!_lockCredentialCache) {
        _lockCredentialCache = [NSMutableDictionary dictionary];
    }
    return _lockCredentialCache;
}

@end
