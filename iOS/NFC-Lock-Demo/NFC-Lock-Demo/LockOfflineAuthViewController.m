//
//  LockOfflineAuthViewController.m
//  MkdIoTToolsDemo
//

#import "LockOfflineAuthViewController.h"
#import <MkdLockLib/MkdLockLib.h>
#import "MBProgressHUD.h"
#import "UIView+Toast.h"

@interface LockOfflineAuthViewController () <UITextFieldDelegate, UIPickerViewDataSource, UIPickerViewDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UITextField *keySNTextField;
@property (nonatomic, strong) UITextField *keySmSecretTextField;
@property (nonatomic, strong) UITextField *lockSNTextField;
@property (nonatomic, strong) UITextField *uidTextField;
@property (nonatomic, strong) UITextField *lockPasswordTextField;
@property (nonatomic, strong) UITextField *lockSmSecretTextField;
@property (nonatomic, strong) UITextField *startTimeTextField;
@property (nonatomic, strong) UITextField *endTimeTextField;
@property (nonatomic, strong) UITextField *nidTextField;
@property (nonatomic, strong) UITextField *countTextField;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UISegmentedControl *authModeSegment;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIDatePicker *startDatePicker;
@property (nonatomic, strong) UIDatePicker *endDatePicker;
@property (nonatomic, strong) UIPickerView *startSecondPicker;
@property (nonatomic, strong) UIPickerView *endSecondPicker;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, assign) NSInteger startSecond;
@property (nonatomic, assign) NSInteger endSecond;
@property (nonatomic, copy) NSString *loadingKeySN;
@property (nonatomic, copy) NSString *loadingLockSN;

@end

@implementation LockOfflineAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.navigationItem.title = @"Offline Authorization";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    
    [self setupSubviews];
    [self setupDateInputs];
    [self applyInitialValues];
}

- (void)setupSubviews {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];
    
    self.stackView = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.stackView.axis = UILayoutConstraintAxisVertical;
    self.stackView.spacing = 12;
    [self.scrollView addSubview:self.stackView];
    
    self.keySNTextField = [self textFieldWithPlaceholder:@"Key SN/KID"];
    self.keySmSecretTextField = [self textFieldWithPlaceholder:@"Key smSecret (enter manually)"];
    self.lockSNTextField = [self textFieldWithPlaceholder:@"Lock SN/LID"];
    self.uidTextField = [self textFieldWithPlaceholder:@"User ID/UID"];
    self.lockPasswordTextField = [self textFieldWithPlaceholder:@"Lock key (min 8 hex chars)"];
    self.lockSmSecretTextField = [self textFieldWithPlaceholder:@"Lock smSecret (optional)"];
    self.startTimeTextField = [self textFieldWithPlaceholder:@"Start Time"];
    self.endTimeTextField = [self textFieldWithPlaceholder:@"End Time"];
    self.nidTextField = [self textFieldWithPlaceholder:@"Rule ID (NID)"];
    self.countTextField = [self textFieldWithPlaceholder:@"Unlock count"];
    
    self.nidTextField.keyboardType = UIKeyboardTypeNumberPad;
    self.countTextField.keyboardType = UIKeyboardTypeNumberPad;
    
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Key SN" view:self.keySNTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Key smSecret" view:self.keySmSecretTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Lock SN" view:self.lockSNTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"User ID" view:self.uidTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Lock Key" view:self.lockPasswordTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Lock smSecret" view:self.lockSmSecretTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Start Time" view:self.startTimeTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"End Time" view:self.endTimeTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Rule ID" view:self.nidTextField]];
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Count" view:self.countTextField]];
    
    self.enableSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.enableSwitch.on = YES;
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Enabled" view:self.enableSwitch]];
    
    self.authModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Time", @"Count", @"Hybrid"]];
    self.authModeSegment.selectedSegmentIndex = 2;
    [self.stackView addArrangedSubview:[self rowWithTitle:@"Auth Mode" view:self.authModeSegment]];
    
    UIButton *confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmButton.backgroundColor = UIColor.blackColor;
    [confirmButton setTitle:@"Confirm" forState:UIControlStateNormal];
    [confirmButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    confirmButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    confirmButton.layer.cornerRadius = 4;
    [confirmButton addTarget:self action:@selector(clickConfirmButtonAction:) forControlEvents:UIControlEventTouchUpInside];
    [confirmButton.heightAnchor constraintEqualToConstant:46].active = YES;
    [self.stackView addArrangedSubview:confirmButton];
    
    self.logTextView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.logTextView.editable = NO;
    self.logTextView.font = [UIFont systemFontOfSize:12];
    self.logTextView.layer.borderColor = UIColor.blackColor.CGColor;
    self.logTextView.layer.borderWidth = 0.5;
    [self.logTextView.heightAnchor constraintEqualToConstant:120].active = YES;
    [self.stackView addArrangedSubview:self.logTextView];
    
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.stackView.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        [self.stackView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.stackView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:15],
        [self.stackView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-15],
        [self.stackView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-20],
    ]];
}

- (UITextField *)textFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *textField = [[UITextField alloc] initWithFrame:CGRectZero];
    textField.borderStyle = UITextBorderStyleRoundedRect;
    textField.placeholder = placeholder;
    textField.font = [UIFont systemFontOfSize:14];
    textField.delegate = self;
    textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textField.autocorrectionType = UITextAutocorrectionTypeNo;
    [textField.heightAnchor constraintEqualToConstant:36].active = YES;
    return textField;
}

- (UIView *)rowWithTitle:(NSString *)title view:(UIView *)view {
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.font = [UIFont systemFontOfSize:14];
    label.textColor = UIColor.blackColor;
    label.adjustsFontSizeToFitWidth = YES;
    [label.widthAnchor constraintEqualToConstant:86].active = YES;
    
    [row addArrangedSubview:label];
    [row addArrangedSubview:view];
    if ([view isKindOfClass:UITextField.class] || [view isKindOfClass:UISegmentedControl.class]) {
        [view setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    }
    return row;
}

- (void)setupDateInputs {
    NSDate *now = [NSDate date];
    self.startSecond = [self secondFromDate:now];
    self.endSecond = self.startSecond;
    
    self.startDatePicker = [self datePickerWithDate:now];
    self.endDatePicker = [self datePickerWithDate:[now dateByAddingTimeInterval:24 * 60 * 60]];
    self.startSecondPicker = [self secondPickerWithSecond:self.startSecond];
    self.endSecondPicker = [self secondPickerWithSecond:self.endSecond];
    
    self.startTimeTextField.inputView = [self dateInputViewWithDatePicker:self.startDatePicker secondPicker:self.startSecondPicker];
    self.endTimeTextField.inputView = [self dateInputViewWithDatePicker:self.endDatePicker secondPicker:self.endSecondPicker];
    self.startTimeTextField.inputAccessoryView = [self dateInputAccessoryView];
    self.endTimeTextField.inputAccessoryView = [self dateInputAccessoryView];
    
    [self.startDatePicker addTarget:self action:@selector(datePickerValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.endDatePicker addTarget:self action:@selector(datePickerValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    [self updateStartTimeText];
    [self updateEndTimeText];
}

- (UIDatePicker *)datePickerWithDate:(NSDate *)date {
    UIDatePicker *datePicker = [[UIDatePicker alloc] initWithFrame:CGRectZero];
    datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    datePicker.date = date;
    datePicker.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    if (@available(iOS 13.4, *)) {
        datePicker.preferredDatePickerStyle = UIDatePickerStyleWheels;
    }
    return datePicker;
}

- (UIPickerView *)secondPickerWithSecond:(NSInteger)second {
    UIPickerView *pickerView = [[UIPickerView alloc] initWithFrame:CGRectZero];
    pickerView.dataSource = self;
    pickerView.delegate = self;
    [pickerView selectRow:second inComponent:0 animated:NO];
    return pickerView;
}

- (UIView *)dateInputViewWithDatePicker:(UIDatePicker *)datePicker secondPicker:(UIPickerView *)secondPicker {
    CGFloat width = UIScreen.mainScreen.bounds.size.width;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 216)];
    container.backgroundColor = UIColor.systemBackgroundColor;
    
    datePicker.frame = CGRectMake(0, 0, width - 86, 216);
    secondPicker.frame = CGRectMake(width - 86, 0, 86, 216);
    [container addSubview:datePicker];
    [container addSubview:secondPicker];
    
    return container;
}

- (UIView *)dateInputAccessoryView {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 44)];
    UIBarButtonItem *flexibleItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *doneItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(donePickingDate)];
    toolbar.items = @[flexibleItem, doneItem];
    return toolbar;
}

- (void)applyInitialValues {
    NSString *connectedKeyName = MkdLock.sharedInstance.connectedElectronicKeyName ?: @"";
    self.keySNTextField.text = self.keySN.length > 0 ? self.keySN : connectedKeyName;
    self.keySmSecretTextField.text = self.keySmSecret ?: @"";
    self.lockSNTextField.text = self.lockSN ?: @"";
    self.lockPasswordTextField.text = self.lockPassword ?: @"";
    self.lockSmSecretTextField.text = self.lockSmSecret ?: @"";
    self.uidTextField.text = self.uid ?: @"";
    self.nidTextField.text = @"1";
    self.countTextField.text = @"1";
}

- (NSInteger)secondFromDate:(NSDate *)date {
    return [NSCalendar.currentCalendar component:NSCalendarUnitSecond fromDate:date];
}

- (NSDate *)dateByApplyingSecond:(NSInteger)second toDate:(NSDate *)date {
    NSDateComponents *components = [NSCalendar.currentCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:date];
    components.second = second;
    return [NSCalendar.currentCalendar dateFromComponents:components];
}

- (void)updateStartTimeText {
    NSDate *date = [self dateByApplyingSecond:self.startSecond toDate:self.startDatePicker.date];
    self.startTimeTextField.text = [self.dateFormatter stringFromDate:date];
}

- (void)updateEndTimeText {
    NSDate *date = [self dateByApplyingSecond:self.endSecond toDate:self.endDatePicker.date];
    self.endTimeTextField.text = [self.dateFormatter stringFromDate:date];
}

- (void)datePickerValueChanged:(UIDatePicker *)datePicker {
    if (datePicker == self.startDatePicker) {
        [self updateStartTimeText];
    } else if (datePicker == self.endDatePicker) {
        [self updateEndTimeText];
    }
}

- (void)donePickingDate {
    [self.view endEditing:YES];
}

- (void)fetchCredentialForKeySN:(NSString *)sn {
    self.logTextView.text = @"Offline demo: enter the key smSecret manually";
}

- (void)fetchCredentialForLockSN:(NSString *)sn {
    self.logTextView.text = @"Offline demo: enter the lock key and smSecret manually";
}

- (IBAction)clickConfirmButtonAction:(UIButton *)sender {
    [self.view endEditing:YES];
    
    NSString *validationMessage = [self validationMessage];
    if (validationMessage.length > 0) {
        [self.view makeToast:validationMessage duration:3.0f position:CSToastPositionCenter];
        return;
    }
    
    MkdElectronicKeyOfflineAuth *auth = [[MkdElectronicKeyOfflineAuth alloc] init];
    auth.uid = [self trimmedString:self.uidTextField.text];
    auth.kid = [self trimmedString:self.keySNTextField.text];
    auth.lid = [self trimmedString:self.lockSNTextField.text];
    auth.password = [self trimmedString:self.lockPasswordTextField.text];
    auth.startDatetime = (uint32_t)[[self selectedStartDate] timeIntervalSince1970];
    auth.endDatetime = (uint32_t)[[self selectedEndDate] timeIntervalSince1970];
    auth.nid = (uint32_t)self.nidTextField.text.integerValue;
    auth.count = (uint16_t)self.countTextField.text.integerValue;
    auth.enable = self.enableSwitch.isOn ? 1 : 0;
    auth.authMode = (uint8_t)(self.authModeSegment.selectedSegmentIndex + 1);
    auth.lockSmSecret = [self trimmedString:self.lockSmSecretTextField.text];
    
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    __weak typeof(self) weakSelf = self;
    [MkdLock.sharedInstance sendElectronicKeyOfflineAuth:auth
                                                smSecret:[self trimmedString:self.keySmSecretTextField.text]
                                                 success:^(id  _Nullable obj) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Offline authorization sent successfully: %@", obj ?: @""];
            [self.view makeToast:@"Offline authorization sent successfully" duration:2.0f position:CSToastPositionCenter];
        });
    } failure:^(NSString * _Nullable errMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                return;
            }
            [MBProgressHUD hideHUDForView:self.view animated:YES];
            self.logTextView.text = [NSString stringWithFormat:@"Failed to send offline authorization: %@", errMsg ?: @"unknown error"];
        });
    }];
}

- (NSDate *)selectedStartDate {
    return [self dateByApplyingSecond:self.startSecond toDate:self.startDatePicker.date];
}

- (NSDate *)selectedEndDate {
    return [self dateByApplyingSecond:self.endSecond toDate:self.endDatePicker.date];
}

- (NSString *)validationMessage {
    if (!MkdLock.sharedInstance.isBLEConnected) {
        return @"Connect the electronic key via Bluetooth first";
    }
    if ([self trimmedString:self.keySNTextField.text].length == 0) {
        return @"Enter the key SN";
    }
    if (![self isValidHex32:[self trimmedString:self.keySmSecretTextField.text]]) {
        return @"Enter a 32-char hex key smSecret";
    }
    if ([self trimmedString:self.lockSNTextField.text].length == 0) {
        return @"Enter the lock SN";
    }
    if ([self trimmedString:self.uidTextField.text].length == 0) {
        return @"Enter the user ID";
    }
    if (![self isValidLockPassword:[self trimmedString:self.lockPasswordTextField.text]]) {
        return @"Enter a lock key of at least 8 hex chars";
    }
    NSString *lockSmSecret = [self trimmedString:self.lockSmSecretTextField.text];
    if (lockSmSecret.length > 0 && ![self isValidHex32:lockSmSecret]) {
        return @"Enter a 32-char hex lock smSecret";
    }
    if (self.nidTextField.text.integerValue <= 0) {
        return @"Enter a valid rule ID";
    }
    if (self.countTextField.text.integerValue <= 0) {
        return @"Enter a valid unlock count";
    }
    if (self.countTextField.text.integerValue > UINT16_MAX) {
        return @"Unlock count cannot exceed 65535";
    }
    if ([[self selectedStartDate] timeIntervalSinceDate:[self selectedEndDate]] >= 0) {
        return @"End time must be later than start time";
    }
    if ([[self selectedEndDate] timeIntervalSince1970] > UINT32_MAX) {
        return @"End time exceeds the protocol range";
    }
    return @"";
}

- (BOOL)isValidHex32:(NSString *)string {
    if (string.length != 32) {
        return NO;
    }
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [[string stringByTrimmingCharactersInSet:hexSet] isEqualToString:@""];
}

- (BOOL)isValidLockPassword:(NSString *)string {
    if (string.length < 8) {
        return NO;
    }
    NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [[string stringByTrimmingCharactersInSet:hexSet] isEqualToString:@""];
}

- (NSString *)trimmedString:(NSString *)string {
    if (![string isKindOfClass:NSString.class]) {
        return @"";
    }
    return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return 60;
}

#pragma mark - UIPickerViewDelegate

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    return [NSString stringWithFormat:@"%02lds", (long)row];
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    if (pickerView == self.startSecondPicker) {
        self.startSecond = row;
        [self updateStartTimeText];
    } else if (pickerView == self.endSecondPicker) {
        self.endSecond = row;
        [self updateEndTimeText];
    }
}

#pragma mark - getter

- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    }
    return _dateFormatter;
}



@end
