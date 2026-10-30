//
//  LogTextView.m
//  NFCLockDemo
//
//  Created by 凉皮 on 2023/2/2.
//

#import "LogTextView.h"

@implementation LogTextView

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/

- (void)setText:(NSString *)text {
    ///时间格式化
    
    dispatch_async(dispatch_get_main_queue(), ^{

        if (!text) {
            
            [super setText:@""];
            
            return;
        }
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc]init];

        formatter.dateFormat = @"HH:mm:ss.SSS";

        NSString *time = [formatter stringFromDate:[NSDate date]];
        
        NSString *string;
        
        if (self.text.length == 0) {
            
            string = [NSString stringWithFormat:@"%@ %@", time, text];
            
        } else {
            
            string = [NSString stringWithFormat:@"%@\n%@ %@", self.text, time, text];
        }
        
        [super setText:string];
        
        [self scrollRangeToVisible:NSMakeRange(string.length, 0)];

    });
}

@end
