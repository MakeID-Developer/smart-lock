//
//  MkdNFCTagModel.h
//  MkdNFCReaderWriterLib
//
//  Created by 凉皮 on 2024/3/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ProtocolType) {
    ///自动寻卡
    ProtocolTypeAuto      = 0x00,
    ProtocolTypeISO14443A = 0x01,
    ProtocolTypeISO14443B = 0x02,
    ProtocolTypeISO15693  = 0x03,
};///协议类型

typedef NS_ENUM(NSUInteger, MifareType) {
    ///默认情况，读写无需密码
    MifareTypeDefault = 0x00,
    ///读写前需校验密码
    MifareTypeS50_3   = 0x01,
    ///读写前需校验密码
    MifareTypeS70     = 0x02,
};///NFC 标签类型(针对 14443A 协议)

@interface MkdNFCTagModel : NSObject

///是否寻到卡片
@property (nonatomic, assign) BOOL isSearchCard;
///标签协议类型
@property (nonatomic, assign) ProtocolType type;

@property (nonatomic, assign) MifareType mifareType;
///标签的UID
@property (nonatomic, copy) NSString *uid;

@end

NS_ASSUME_NONNULL_END
