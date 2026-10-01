#import <Foundation/Foundation.h>

// 群聊分组管理器：将会话列表按群聊/普通分组
@interface WCZZSessionGroupManager : NSObject

+ (instancetype)sharedInstance;

// 开关
@property (nonatomic, assign) BOOL chatGrouping;   // 总开关：聊天分组
@property (nonatomic, assign) BOOL groupsOnly;      // 仅显示群组

// 分组后的数据
@property (nonatomic, strong, readonly) NSArray *topSessions;    // 置顶会话（不分组）
@property (nonatomic, strong, readonly) NSArray *groupSessions;  // 群聊会话
@property (nonatomic, strong, readonly) NSArray *normalSessions; // 普通会话
@property (nonatomic, strong) NSSet *excludedGroups;              // 排除的群聊 username 集合

// 核心方法
- (BOOL)isGroupSession:(id)session;
- (NSArray *)filteredLaunchSessions:(NSArray *)sessions groupChats:(BOOL)groupChats;
- (void)rebuildSessions:(NSArray *)sessions groupChats:(BOOL)groupChats;

// 数据源查询（供 hook 的数据源方法调用）
- (NSInteger)numberOfSections;
- (NSInteger)numberOfSessionsInSection:(NSInteger)section;
- (id)sessionAtIndexPath:(NSIndexPath *)indexPath;
- (NSString *)titleForSection:(NSInteger)section;

@end
