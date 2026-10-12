//
//  HBGroupEngine.h
//  群聊分组 —— 引擎层
//
//  职责：
//   1) 判断一个会话是不是群聊；
//   2) 把微信首页会话列表按「分组」重排（原生置顶 / 分组行 / 普通会话）；
//   3) 生成分组行的 cellData（标题、摘要、时间、头像）；
//   4) 给首页 cell 打补丁（去掉菜单、换头像、算高度）。
//
//  会话对象（MMSessionInfo / SessionCellData 之类）字段名在各版本微信里不完全一致，
//  因此全部通过 KVC 多候选名读取，取到哪个用哪个，取不到就静默跳过。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "HBGroupConfig.h"

NS_ASSUME_NONNULL_BEGIN

/// 分组行的逻辑标记：分组行 uid 前缀
extern NSString *const kHBGroupRowPrefix;

typedef NS_ENUM(NSInteger, HBGroupAction) {
    HBGroupActionNone = 0,
    HBGroupActionRead,      // 全部已读
    HBGroupActionDelete,    // 删除
    HBGroupActionHide,      // 隐藏
};

@interface HBGroupEngine : NSObject

+ (instancetype)shared;

#pragma mark - 会话判定

/// 群聊判定：userName 以 @chatroom 结尾
+ (BOOL)isChatRoomSession:(id _Nullable)session;
/// 当前分组模式下该会话是否属于要折叠的对象
+ (BOOL)isGroupSession:(id _Nullable)session chatMode:(BOOL)chatMode;

/// 从会话对象里取 userName（多候选 key）
+ (nullable NSString *)userNameOfSession:(id _Nullable)session;
/// 从会话对象里取展示名
+ (nullable NSString *)displayNameOfSession:(id _Nullable)session;
/// 取最后一条消息摘要文本
+ (nullable NSString *)summaryOfSession:(id _Nullable)session;

#pragma mark - 列表重排

/// 原生置顶会话
@property (nonatomic, strong) NSMutableArray *allTopSessions;
/// 原生普通会话
@property (nonatomic, strong) NSMutableArray *normalSessions;
/// 重排后的置顶会话
@property (nonatomic, strong) NSMutableArray *topSessions;
/// 置顶总数（原生 + 分组行）
@property (nonatomic, assign) NSUInteger totalTopSessionCount;

/// 上一次重建的完整列表（顶部 + 普通，已按显示顺序拍平）
@property (nonatomic, strong) NSMutableArray *flattenedSessions;

/// 分组行占位对象缓存，key = 分组 identifier
@property (nonatomic, strong) NSMutableDictionary *groupRowCache;

/// 重建会话列表：从 manager 里取原生会话，做分组折叠
+ (void)rebuildSessions:(id _Nullable)manager chatMode:(BOOL)chatMode;
/// 生成「折叠后」的会话数组（不含分组行）
+ (NSArray *)filteredLaunchSessions:(NSArray *_Nullable)sessions chatMode:(BOOL)chatMode;
/// 取第 index 个会话（index 是折叠后的下标）
+ (nullable id)groupAtIndex:(NSUInteger)index top:(BOOL)top manager:(id _Nullable)manager;
/// 该 userName 是否在某个分组里
+ (nullable NSString *)groupIdentifierForUserName:(NSString *)userName chatMode:(BOOL)chatMode;

#pragma mark - 显示

/// 为某个群会话生成首页 cellData
+ (nullable id)groupCellDataForSession:(id _Nullable)session;
/// 计算分组行摘要文本
+ (NSString *)summaryTextForGroup:(HBGroupItem *)item chatMode:(BOOL)chatMode;
/// 记录首页行高，供 heightForRow 使用
+ (void)recordHomeRowHeight:(CGFloat)height;
/// 取分组头像
+ (nullable UIImage *)avatarForGroupItem:(HBGroupItem *)item;

@end

NS_ASSUME_NONNULL_END
