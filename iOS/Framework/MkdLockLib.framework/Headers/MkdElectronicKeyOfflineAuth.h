//
//  MkdElectronicKeyOfflineAuth.h
//  MkdLockLib
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 电子钥匙离线授权节点，对应0x09下发的authPayload[96]。
@interface MkdElectronicKeyOfflineAuth : NSObject <NSCopying>

/// 用户ID，UTF-8固定16字节。
@property (nonatomic, copy) NSString *uid;
/// 钥匙ID，UTF-8固定16字节。
@property (nonatomic, copy) NSString *kid;
/// 锁ID，UTF-8固定16字节。
@property (nonatomic, copy) NSString *lid;
/// 锁密，32位HEX字符串，固定16字节。
@property (nonatomic, copy) NSString *password;
/// 授权开始时间，秒级时间戳，小端写入。
@property (nonatomic, assign) uint32_t startDatetime;
/// 授权结束时间，秒级时间戳，小端写入。
@property (nonatomic, assign) uint32_t endDatetime;
/// 规则ID，小端写入。
@property (nonatomic, assign) uint32_t nid;
/// 可开锁次数，小端写入。
@property (nonatomic, assign) uint16_t count;
/// 是否启用规则。
@property (nonatomic, assign) uint8_t enable;
/// 认证模式，1时间、2次数、3混合。
@property (nonatomic, assign) uint8_t authMode;
/// 锁侧smSecret，32位HEX字符串，固定16字节；可为空，空值下发16字节0。
@property (nonatomic, copy, nullable) NSString *lockSmSecret;

@end

NS_ASSUME_NONNULL_END
