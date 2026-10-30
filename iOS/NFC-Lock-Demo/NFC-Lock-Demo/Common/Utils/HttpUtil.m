//
//  HttpUtil.m
//  NFCLockDemo
//
//  Created by 凉皮 on 2023/3/21.
//

#import "HttpUtil.h"
#import "MacroHeader.h"

#define DEF_BASE_URL @"https://platform.makeid.com/makeid_platform_api"
//#define DEF_BASE_URL @"https://mark-apitest-prc.jingjingfun.com/makeid_platform_api"

@implementation HttpUtil
//GET请求
+ (void)getWithUrlString:(NSString *)url parameters:(NSDictionary *)parameters success:(XMSuccessBlock)successBlock failure:(XMFailureBlock)failureBlock {
    
    NSString *fullUrl = [NSString stringWithFormat:@"%@%@", DEF_BASE_URL, url];
    
    NSMutableString *mutableUrl = [[NSMutableString alloc] initWithString:fullUrl];
    if ([parameters allKeys]) {
        [mutableUrl appendString:@"?"];
        for (id key in parameters) {
            NSString *value = [parameters objectForKey:key];//[[parameters objectForKey:key] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
            [mutableUrl appendString:[NSString stringWithFormat:@"%@=%@&", key, value]];
        }
    }
    NSString *urlEnCode = [[mutableUrl substringToIndex:mutableUrl.length - 1] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    
    NSURL *URL = [NSURL URLWithString:urlEnCode];
    
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:URL];
    
    urlRequest.HTTPMethod = @"GET";
    
    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:@"Token"];

    [urlRequest setValue:token forHTTPHeaderField:@"X-Access-Token"];
    
    NSURLSession *urlSession = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [urlSession dataTaskWithRequest:urlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            failureBlock(error);
        } else {
            NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            successBlock(dic);
        }
    }];
    [dataTask resume];
}

//POST请求 使用NSMutableURLRequest可以加入请求头
+ (void)postWithUrlString:(NSString *)url parameters:(NSDictionary *)parameters success:(XMSuccessBlock)successBlock failure:(XMFailureBlock)failureBlock
{
    NSString *fullUrl = [NSString stringWithFormat:@"%@%@", DEF_BASE_URL, url];
    
    NSURL *nsurl = [NSURL URLWithString:fullUrl];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:nsurl];
    //如果想要设置网络超时的时间的话，可以使用下面的方法：
//    NSMutableURLRequest *mutableRequest=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    
    //设置请求类型
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSString *token = [[NSUserDefaults standardUserDefaults] stringForKey:@"Token"];

    [request setValue:token forHTTPHeaderField:@"X-Access-Token"];
    //把参数放到请求体内
    
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:parameters options:NSJSONWritingPrettyPrinted error:nil];
    
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request
                                                completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) { //请求失败
            
            failureBlock(error);
            
        } else {  //请求成功
            
            NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
            
            successBlock(dic);
        }
    }];
    [dataTask resume];  //开始请求
}

//重新封装参数 加入app相关信息
+ (NSString *)parseParams:(NSDictionary *)params
{
    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] initWithDictionary:params];
//    [parameters setValue:@"ios" forKey:@"client"];
//    [parameters setValue:@"请替换版本号" forKey:@"auth_version"];
//    NSString* phoneModel = @"获取手机型号" ;
//    NSString* phoneVersion = [[UIDevice currentDevice] systemVersion];//ios系统版本号
//    NSString *system = [NSString stringWithFormat:@"%@(%@)",phoneModel, phoneVersion];
//    [parameters setValue:system forKey:@"system"];
//    NSDate *date = [NSDate date];
//    NSTimeInterval timeinterval = [date timeIntervalSince1970];
//    [parameters setObject:[NSString stringWithFormat:@"%.0lf",timeinterval] forKey:@"auth_timestamp"];//请求时间戳
//    NSString *devicetoken = @"请替换DeviceToken";
//    [parameters setValue:devicetoken forKey:@"uuid"];
//    NSLog(@"请求参数:%@",parameters);

    NSString *keyValueFormat;
    NSMutableString *result = [NSMutableString new];
    //实例化一个key枚举器用来存放dictionary的key
   
   //加密处理 将所有参数加密后结果当做参数传递
   //parameters = @{@"i":@"加密结果 抽空加入"};
   
    NSEnumerator *keyEnum = [parameters keyEnumerator];
    id key;
    while (key = [keyEnum nextObject]) {
        keyValueFormat = [NSString stringWithFormat:@"%@=%@&", key, [params valueForKey:key]];
        [result appendString:keyValueFormat];
    }
    return result;
}
@end
