#import "WCZZSessionGroupManager.h"
#import <objc/runtime.h>

static NSString *const kWCZZChatGroupingKey = @"WCZZChatGrouping";
static NSString *const kWCZZGroupsOnlyKey = @"WCZZGroupsOnly";

@interface WCZZSessionGroupManager ()
@property (nonatomic, strong) NSArray *topSessions;
@property (nonatomic, strong) NSArray *groupSessions;
@property (nonatomic, strong) NSArray *normalSessions;
@end

@implementation WCZZSessionGroupManager

+ (instancetype)sharedInstance {
    static WCZZSessionGroupManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _chatGrouping = [defaults boolForKey:kWCZZChatGroupingKey];
        _groupsOnly = [defaults boolForKey:kWCZZGroupsOnlyKey];
        _topSessions = @[];
        _groupSessions = @[];
        _normalSessions = @[];
        NSArray *excluded = [defaults arrayForKey:@"WCZZExcludedGroups"];
        _excludedGroups = [NSSet setWithArray:excluded ?: @[]];
    }
    return self;
}

- (void)setExcludedGroups:(NSSet *)excludedGroups {
    _excludedGroups = [excludedGroups copy] ?: [NSSet set];
    [[NSUserDefaults standardUserDefaults] setObject:[_excludedGroups allObjects] forKey:@"WCZZExcludedGroups"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setChatGrouping:(BOOL)chatGrouping {
    _chatGrouping = chatGrouping;
    [[NSUserDefaults standardUserDefaults] setBool:chatGrouping forKey:kWCZZChatGroupingKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setGroupsOnly:(BOOL)groupsOnly {
    _groupsOnly = groupsOnly;
    [[NSUserDefaults standardUserDefaults] setBool:groupsOnly forKey:kWCZZGroupsOnlyKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - 核心方法

// 判断一个会话是否为群聊：username 以 @chatroom 结尾
- (BOOL)isGroupSession:(id)session {
    if (!session) return NO;
    NSString *username = nil;
    @try {
        username = [session valueForKey:@"m_nsUsrName"];
    } @catch (NSException *e) {
        return NO;
    }
    if (![username isKindOfClass:[NSString class]]) return NO;
    return [username hasSuffix:@"@chatroom"];
}

// 初始加载时过滤会话列表
- (NSArray *)filteredLaunchSessions:(NSArray *)sessions groupChats:(BOOL)groupChats {
    if (!self.chatGrouping) return sessions;
    if (!groupChats) return sessions;
    NSMutableArray *filtered = [NSMutableArray array];
    for (id session in sessions) {
        if ([self isGroupSession:session]) {
            [filtered addObject:session];
        }
    }
    return [filtered copy];
}

// 重建分组数据结构
- (void)rebuildSessions:(NSArray *)sessions groupChats:(BOOL)groupChats {
    if (!self.chatGrouping) {
        // 未开启分组：全部作为普通会话
        self.topSessions = @[];
        self.groupSessions = @[];
        self.normalSessions = sessions ?: @[];
        return;
    }

    NSMutableArray *top = [NSMutableArray array];
    NSMutableArray *group = [NSMutableArray array];
    NSMutableArray *normal = [NSMutableArray array];

    for (id session in sessions) {
        // 判断是否置顶：MMSessionInfo 的 m_bIsTop 或 topName 非空
        BOOL isTop = NO;
        @try {
            NSNumber *topFlag = [session valueForKey:@"m_bIsTop"];
            if ([topFlag isKindOfClass:[NSNumber class]]) {
                isTop = [topFlag boolValue];
            } else {
                NSString *topName = [session valueForKey:@"m_nsTopName"];
                isTop = [topName isKindOfClass:[NSString class]] && topName.length > 0;
            }
        } @catch (NSException *e) {
            isTop = NO;
        }

        if (isTop) {
            [top addObject:session];
        } else if (groupChats && [self isGroupSession:session]) {
            // 检查是否在排除列表中
            NSString *username = nil;
            @try { username = [session valueForKey:@"m_nsUsrName"]; } @catch (NSException *e) {}
            if (username && [self.excludedGroups containsObject:username]) {
                [normal addObject:session];
            } else {
                [group addObject:session];
            }
        } else {
            // groupsOnly 模式下只保留群聊
            if (self.groupsOnly && groupChats) continue;
            [normal addObject:session];
        }
    }

    self.topSessions = [top copy];
    self.groupSessions = [group copy];
    self.normalSessions = [normal copy];
}

#pragma mark - 数据源查询

// section 数量：
// 未开启分组 → 1
// 开启分组 → 置顶(如果有) + 群聊 + 普通
- (NSInteger)numberOfSections {
    if (!self.chatGrouping) return 1;
    NSInteger count = 0;
    if (self.topSessions.count > 0) count++;
    if (self.groupSessions.count > 0) count++;
    if (self.normalSessions.count > 0) count++;
    return MAX(count, 1);
}

- (NSInteger)numberOfSessionsInSection:(NSInteger)section {
    if (!self.chatGrouping) {
        return self.normalSessions.count;
    }
    NSInteger idx = 0;
    if (self.topSessions.count > 0) {
        if (section == idx) return self.topSessions.count;
        idx++;
    }
    if (self.groupSessions.count > 0) {
        if (section == idx) return self.groupSessions.count;
        idx++;
    }
    if (self.normalSessions.count > 0) {
        if (section == idx) return self.normalSessions.count;
    }
    return 0;
}

- (id)sessionAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.chatGrouping) {
        NSInteger row = [indexPath indexAtPosition:1];
        if (row < self.normalSessions.count) return self.normalSessions[row];
        return nil;
    }
    NSInteger section = [indexPath indexAtPosition:0];
    NSInteger row = [indexPath indexAtPosition:1];
    NSInteger idx = 0;
    if (self.topSessions.count > 0) {
        if (section == idx) {
            if (row < self.topSessions.count) return self.topSessions[row];
            return nil;
        }
        idx++;
    }
    if (self.groupSessions.count > 0) {
        if (section == idx) {
            if (row < self.groupSessions.count) return self.groupSessions[row];
            return nil;
        }
        idx++;
    }
    if (self.normalSessions.count > 0) {
        if (section == idx) {
            if (row < self.normalSessions.count) return self.normalSessions[row];
            return nil;
        }
    }
    return nil;
}

- (NSString *)titleForSection:(NSInteger)section {
    if (!self.chatGrouping) return nil;
    NSInteger idx = 0;
    if (self.topSessions.count > 0) {
        if (section == idx) return @"置顶";
        idx++;
    }
    if (self.groupSessions.count > 0) {
        if (section == idx) return @"群聊";
        idx++;
    }
    if (self.normalSessions.count > 0) {
        if (section == idx) return @"聊天";
    }
    return nil;
}

@end
