//
//  ACMacros.h
//  WewinLabel2017
//
//  Created by 刘良平 on 2019/5/7.
//  Copyright © 2019 WeWin. All rights reserved.
//

#ifndef ACMacros_h
#define ACMacros_h

/**/
#define WFWindowWidth ([[UIScreen mainScreen] bounds].size.width)

#define WFWindowHeight ([[UIScreen mainScreen] bounds].size.height)

#define WFStatusBarWidth WFWindowWidth

#define WFStatusBarHeight 20

#define WFNavBarWidth WFWindowWidth

#define WFNavBarHeight 44

#define WFTabBarHeight 49

#define WFColor(r, g, b, a) [UIColor colorWithRed:(r)/255.0 green:(g)/255.0 blue:(b)/255.0 alpha:(a)]
// RGB颜色转换（16进制->10进制）
#define UIColorFromRGB(rgbValue)\
\
[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
green:((float)((rgbValue & 0xFF00) >> 8))/255.0 \
blue:((float)(rgbValue & 0xFF))/255.0 \
alpha:1.0]

#define UIColorFromRGBWithAlpha(rgbValue, alphaValue) \
\
[UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 \
green:((float)((rgbValue & 0x00FF00) >> 8))/255.0 \
blue:((float)(rgbValue & 0x0000FF))/255.0 \
alpha:alphaValue]

#define DEF_SHOW_TOAST(messge) [self.view makeToast:messge duration:2 position:CSToastPositionCenter]

#define MainColor UIColorFromRGB(0x0A9773)

#define WFFont(font) [UIFont systemFontOfSize:(font)]

#define APPVersion [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"]

#define BuildVersion [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]

#define TimeStmp [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];

#define WEAK  __weak typeof(self) weakSelf = self
#define STRONG  __strong typeof(weakSelf) self = weakSelf

#define LocalizedString(key) NSLocalizedString(key, nil)

#define WS(weakSelf)  __weak __typeof(&*self)weakSelf = self;

#define iPhone [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone

//iphonex 和 iphonexs 逻辑分辨率相同, iphonexr 和 iphonexsmax 逻辑分辨率相同
#define iPhoneX (([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(375, 812), [[UIScreen mainScreen] bounds].size) : NO) || ([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(414, 896), [[UIScreen mainScreen] bounds].size) : NO))

#define isZh [[NSLocale preferredLanguages][0] hasPrefix:@"zh"]

#define excelDirectory [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"excel"]

#define inboxDirectory [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"Inbox"]

#define CommonlyUsedDirectory [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"LocalUsedImages"]


#define XibView(XibName) [[[NSBundle mainBundle] loadNibNamed:XibName owner:nil options:nil] firstObject]

// View 圆角和加边框
#define ViewBorderRadius(View, Radius, Width, Color)\
\
[View.layer setCornerRadius:(Radius)];\
[View.layer setMasksToBounds:YES];\
[View.layer setBorderWidth:(Width)];\
[View.layer setBorderColor:[Color CGColor]]

// View 圆角
#define ViewRadius(View, Radius)\
\
[View.layer setCornerRadius:(Radius)];\
[View.layer setMasksToBounds:YES];

#define CheckLabelPrinters(deviceName) DEVICENAME_P30(deviceName) || DEVICENAME_P31(deviceName) ||\
                                       DEVICENAME_P20(deviceName) || DEVICENAME_D50(deviceName) || \
                                       DEVICENAME_I70(deviceName)


#endif /* ACMacros_h */
