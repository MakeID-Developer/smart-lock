//
//  HttpUtil.h
//  NFCLockDemo
//
//  Created by 凉皮 on 2023/3/21.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

typedef void (^XMCompletioBlock)(NSDictionary *dic, NSURLResponse *response, NSError *error);
typedef void (^XMSuccessBlock)(NSDictionary *data);
typedef void (^XMFailureBlock)(NSError *error);

@interface HttpUtil : NSObject

/**
 *  get请求
 */
+ (void)getWithUrlString:(NSString *)url parameters:(NSDictionary *)parameters success:(XMSuccessBlock)successBlock failure:(XMFailureBlock)failureBlock;

/**
 * post请求
 */
+ (void)postWithUrlString:(NSString *)url parameters:(NSDictionary *)parameters success:(XMSuccessBlock)successBlock failure:(XMFailureBlock)failureBlock;


@end

NS_ASSUME_NONNULL_END
