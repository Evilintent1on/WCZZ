//
//  HBFriendGroupController.h
//  群聊 / 好友分组控制器
//
//  两个模式共用同一个控制器：
//    groupChats = YES → 群聊分组
//    groupChats = NO  → 好友分组
//    settingsMode = YES → 设置列表
//

#import <UIKit/UIKit.h>
#import "HBGroupConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface HBFriendGroupController : UITableViewController

/// 会话列表（非设置模式）
@property (nonatomic, strong) NSArray *sessions;
/// 每行对应的 cellData，key = userName
@property (nonatomic, strong) NSMutableDictionary *cellModels;
/// 微信首页控制器（weak）
@property (nonatomic, weak) id homeController;
/// 搜索框
@property (nonatomic, strong) id searchBar;
/// 搜索关键字
@property (nonatomic, copy) NSString *searchText;
/// 当前账号
@property (nonatomic, copy) NSString *account;

/// YES = 群聊分组，NO = 好友分组
@property (nonatomic, assign) BOOL groupChats;
/// YES = 显示设置项列表
@property (nonatomic, assign) BOOL settingsMode;
/// 正在处理编辑（防重入）
@property (nonatomic, assign) BOOL handlingEdit;
/// 待刷新
@property (nonatomic, assign) BOOL pendingReload;
/// 批量操作进行中
@property (nonatomic, assign) BOOL batchRunning;

#pragma mark - 类方法（引擎入口，被微信首页 hook 调用）

+ (BOOL)isEnabled;
+ (BOOL)isChatGroupEnabled;
+ (void)setChatGroupEnabled:(BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled groupChats:(BOOL)groupChats;

+ (void)rebuildSessions:(id _Nullable)manager;
+ (void)rebuildSessions:(id _Nullable)manager groupChats:(BOOL)groupChats;
+ (NSArray *)filteredLaunchSessions:(NSArray *_Nullable)sessions;
+ (NSArray *)filteredLaunchSessions:(NSArray *_Nullable)sessions groupChats:(BOOL)groupChats;

+ (BOOL)isGroupSession:(id _Nullable)session;
+ (id _Nullable)groupAtIndex:(NSUInteger)index top:(BOOL)top manager:(id _Nullable)manager;
+ (id _Nullable)groupCellDataForSession:(id _Nullable)session;

+ (id _Nullable)summaryDataForItem:(id _Nullable)item;
+ (void)finishSummaryForItem:(id _Nullable)item entryData:(id _Nullable)entryData;
+ (void)recordHomeRowHeight:(CGFloat)height;
+ (void)configureHomeCell:(id _Nullable)cell;
+ (void)openFromController:(id _Nullable)controller session:(id _Nullable)session;

+ (NSString * _Nullable)avatarForGroupUsername:(NSString *)userName;
+ (void)applyGroupAvatar:(id _Nullable)view fake:(BOOL)fake;

+ (BOOL)isGroupActionMenu:(id _Nullable)menu;
+ (void)setSelecting:(BOOL)selecting controller:(id _Nullable)controller;
+ (void)refreshForHomeActivation;
+ (void)appendExclusionCellToSection:(id _Nullable)section contact:(id _Nullable)contact owner:(id _Nullable)owner;

@end

NS_ASSUME_NONNULL_END
