//
//  NFC_Lock_DemoUITestsLaunchTests.m
//  NFC-Lock-DemoUITests
//
//  Created by 凉皮 on 2024/4/25.
//

#import <XCTest/XCTest.h>

@interface NFC_Lock_DemoUITestsLaunchTests : XCTestCase

@end

@implementation NFC_Lock_DemoUITestsLaunchTests

+ (BOOL)runsForEachTargetApplicationUIConfiguration {
    return YES;
}

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testLaunch {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    [app launch];

    // Insert steps here to perform after app launch but before taking a screenshot,
    // such as logging into a test account or navigating somewhere in the app

    XCTAttachment *attachment = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    attachment.name = @"Launch Screen";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

@end
