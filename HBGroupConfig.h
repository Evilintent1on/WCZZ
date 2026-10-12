//
//  HBGroupConfig.h
//  群聊分组 / 好友分组 —— 配置中心
//
//  所有开关落盘到 Preferences plist，进程内做缓存。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kHBGroupChangedNotification;

@interface HBGroupItem : NSObject <NSCopying>

/// 分组唯一标识（uuid）
@property (nonatomic, copy) NSString *identifier;
/// 分组显示名
@property (nonatomic, copy) NSString *name;
/// 分组成员：微信 userName（群为 xxxx@chatroom，好友为 wxid_xxx）
@property (nonatomic, strong) NSMutableArray<NSString *> *members;
/// 分组头像（本地文件路径，可为空）
@property (nonatomic, copy, nullable) NSString *avatarPath;
/// 排序权重，越小越靠前
@property (nonatomic, assign) NSInteger order;

+ (instancetype)itemWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryValue;

@end


@interface HBGroupConfig : NSObject

/// 全局总开关
@property (nonatomic, assign) BOOL enabled;
/// 群聊分组开关（NO = 好友分组）
@property (nonatomic, assign) BOOL chatGroupEnabled;
/// 好友分组开关
@property (nonatomic, assign) BOOL friendGroupEnabled;

/// 分组列表（群聊分组）
@property (nonatomic, strong) NSMutableArray<HBGroupItem *> *chatGroups;
/// 分组列表（好友分组）
@property (nonatomic, strong) NSMutableArray<HBGroupItem *> *friendGroups;

/// 分组行是否置顶
@property (nonatomic, assign) BOOL pinned;
/// 是否排在原生置顶会话之下
@property (nonatomic, assign) BOOL belowNativePinned;
/// 隐藏首页搜索栏
@property (nonatomic, assign) BOOL hideSearchBar;
/// 隐藏摘要里的发送者名字
@property (nonatomic, assign) BOOL hideSummarySender;
/// 摘要格式，%@ = 发送者，%@ = 内容
@property (nonatomic, copy) NSString *summaryFormat;
/// 首页分组行的高度（用于 cell 高度缓存）
@property (nonatomic, assign) CGFloat homeRowHeight;

/// 被排除、不参与折叠的群/好友
@property (nonatomic, strong) NSMutableArray<NSString *> *exclusions;

+ (instancetype)shared;

- (void)reload;
- (void)synchronize;

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def;
- (void)setBool:(BOOL)value forKey:(NSString *)key;

- (NSArray<HBGroupItem *> *)groupsForChatMode:(BOOL)chatMode;
- (void)setGroups:(NSArray<HBGroupItem *> *)groups chatMode:(BOOL)chatMode;

- (void)addMembers:(NSArray<NSString *> *)members toGroup:(NSString *)groupID chatMode:(BOOL)chatMode;
- (void)removeMember:(NSString *)member fromGroup:(NSString *)groupID chatMode:(BOOL)chatMode;

@end

NS_ASSUME_NONNULL_END
