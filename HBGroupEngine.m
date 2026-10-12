//
//  HBGroupEngine.m
//  群聊分组 —— 引擎层实现
//

#import "HBGroupEngine.h"
#import "HBGroupConfig.h"

NSString *const kHBGroupRowPrefix = @"__hb_group_row__";

/// 多候选 KVC 读取：微信不同版本字段名不一样，挨个试
static id HBKVC(id obj, NSArray<NSString *> *keys) {
    if (!obj) return nil;
    for (NSString *key in keys) {
        @try {
            id value = [obj valueForKey:key];
            if (value) return value;
        } @catch (__unused NSException *e) {
            continue;
        }
    }
    return nil;
}

static NSString *HBString(id obj, NSArray<NSString *> *keys) {
    id value = HBKVC(obj, keys);
    if ([value isKindOfClass:[NSString class]]) return value;
    if (value) return [value description];
    return nil;
}

@interface HBGroupEngine ()
+ (void)rebuildSessions:(NSMutableArray *)topSessions
                 normal:(NSMutableArray *)normalSessions
               chatMode:(BOOL)chatMode;
+ (nullable id)groupRowForItem:(HBGroupItem *)item chatMode:(BOOL)chatMode;
+ (void)refreshGroupRow:(id)row item:(HBGroupItem *)item chatMode:(BOOL)chatMode;
+ (nullable id)sessionForUserName:(NSString *)userName chatMode:(BOOL)chatMode;
@end

@implementation HBGroupEngine

+ (instancetype)shared {
    static HBGroupEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HBGroupEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _allTopSessions = [NSMutableArray array];
        _normalSessions = [NSMutableArray array];
        _topSessions = [NSMutableArray array];
        _flattenedSessions = [NSMutableArray array];
        _groupRowCache = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 会话判定

+ (BOOL)isChatRoomSession:(id)session {
    NSString *userName = [self userNameOfSession:session];
    if (!userName.length) return NO;
    return [userName hasSuffix:@"@chatroom"];
}

+ (BOOL)isGroupSession:(id)session chatMode:(BOOL)chatMode {
    if (!session) return NO;
    if (![[HBGroupConfig shared] enabled]) return NO;

    NSString *userName = [self userNameOfSession:session];
    if (!userName.length) return NO;

    // 被排除的对象永远不折叠
    if ([[HBGroupConfig shared].exclusions containsObject:userName]) return NO;

    // 只折叠已加入用户分组的会话：没建分组时不乱收
    for (HBGroupItem *item in [[HBGroupConfig shared] groupsForChatMode:chatMode]) {
        if ([item.members containsObject:userName]) return YES;
    }
    return NO;
}

+ (NSString *)userNameOfSession:(id)session {
    return HBString(session, @[@"m_nsUserName", @"userName", @"m_nsUsrName", @"nsUserName"]);
}

+ (NSString *)displayNameOfSession:(id)session {
    NSString *name = HBString(session, @[@"m_nsNickName", @"nickName", @"m_nsRemark", @"remark", @"displayName"]);
    if (name.length) return name;
    name = HBString(session, @[@"m_nsUserName", @"userName"]);
    return name ?: @"";
}

+ (NSString *)summaryOfSession:(id)session {
    id wrap = HBKVC(session, @[@"m_msgWrap", @"msgWrap", @"m_lastMsgWrap"]);
    NSString *text = HBString(wrap, @[@"m_nsContent", @"content", @"m_nsDesc"]);
    if (text.length) return text;
    return HBString(session, @[@"m_textForMessageLabel", @"textForMessageLabel", @"m_nsSummary"]) ?: @"";
}

+ (NSString *)groupIdentifierForUserName:(NSString *)userName chatMode:(BOOL)chatMode {
    if (!userName.length) return nil;
    for (HBGroupItem *item in [[HBGroupConfig shared] groupsForChatMode:chatMode]) {
        if ([item.members containsObject:userName]) return item.identifier;
    }
    return nil;
}

#pragma mark - 列表重排

+ (void)rebuildSessions:(id)manager chatMode:(BOOL)chatMode {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rebuildSessions:manager chatMode:chatMode];
        });
        return;
    }

    HBGroupConfig *config = [HBGroupConfig shared];
    HBGroupEngine *engine = [self shared];

    if (!config.enabled) return;

    // 1) 从 manager 抓原生会话
    NSArray *allTop = HBKVC(manager, @[@"allTopSessions", @"m_allTopSessions"]);
    NSArray *top = HBKVC(manager, @[@"topSessions", @"m_topSessions"]);
    NSArray *normal = HBKVC(manager, @[@"normalSessions", @"m_normalSessions"]);

    if ([allTop isKindOfClass:[NSArray class]]) engine.allTopSessions = [allTop mutableCopy];
    if ([top isKindOfClass:[NSArray class]]) engine.topSessions = [top mutableCopy];
    if ([normal isKindOfClass:[NSArray class]]) engine.normalSessions = [normal mutableCopy];

    [self rebuildSessions:engine.topSessions normal:engine.normalSessions chatMode:chatMode];
}

+ (void)rebuildSessions:(NSMutableArray *)topSessions
                 normal:(NSMutableArray *)normalSessions
               chatMode:(BOOL)chatMode {

    HBGroupConfig *config = [HBGroupConfig shared];
    HBGroupEngine *engine = [self shared];

    engine.flattenedSessions = [NSMutableArray array];

    NSMutableArray *keptTop = [NSMutableArray array];
    NSMutableArray *keptNormal = [NSMutableArray array];

    // 原生置顶：按开关决定分组行插哪
    for (id session in topSessions) {
        if ([self isGroupSession:session chatMode:chatMode]) continue;   // 折叠掉
        [keptTop addObject:session];
    }
    for (id session in normalSessions) {
        if ([self isGroupSession:session chatMode:chatMode]) continue;
        [keptNormal addObject:session];
    }

    // 分组行（每个有成员的组一行）
    NSMutableArray *groupRows = [NSMutableArray array];
    for (HBGroupItem *item in [config groupsForChatMode:chatMode]) {
        if (!item.members.count) continue;
        id row = [self groupRowForItem:item chatMode:chatMode];
        if (row) [groupRows addObject:row];
    }

    if (config.pinned) {
        if (config.belowNativePinned) {
            [engine.flattenedSessions addObjectsFromArray:keptTop];
            [engine.flattenedSessions addObjectsFromArray:groupRows];
        } else {
            [engine.flattenedSessions addObjectsFromArray:groupRows];
            [engine.flattenedSessions addObjectsFromArray:keptTop];
        }
    } else {
        [engine.flattenedSessions addObjectsFromArray:keptTop];
    }
    [engine.flattenedSessions addObjectsFromArray:keptNormal];

    engine.topSessions = keptTop;
    engine.normalSessions = keptNormal;
    engine.totalTopSessionCount = engine.flattenedSessions.count;
}

+ (NSArray *)filteredLaunchSessions:(NSArray *)sessions chatMode:(BOOL)chatMode {
    if (![sessions isKindOfClass:[NSArray class]]) return @[];
    if (![HBGroupConfig shared].enabled) return sessions;

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:sessions.count];
    NSMutableArray *grouped = [NSMutableArray array];

    for (id session in sessions) {
        if ([self isGroupSession:session chatMode:chatMode]) {
            [grouped addObject:session];
            continue;
        }
        [result addObject:session];
    }

    // 分组行放到最前面（受置顶开关控制）
    if (grouped.count && [HBGroupConfig shared].pinned) {
        for (HBGroupItem *item in [[HBGroupConfig shared] groupsForChatMode:chatMode]) {
            if (!item.members.count) continue;
            id row = [self groupRowForItem:item chatMode:chatMode];
            if (row) [result insertObject:row atIndex:0];
        }
    }
    return result;
}

+ (id)groupRowForItem:(HBGroupItem *)item chatMode:(BOOL)chatMode {
    HBGroupEngine *engine = [self shared];
    id cached = engine.groupRowCache[item.identifier];
    if (cached) {
        [self refreshGroupRow:cached item:item chatMode:chatMode];
        return cached;
    }

    // 复用微信的 SessionCellData（各版本类名不同，做多候选）
    Class cellDataClass = NSClassFromString(@"MMSessionInfo");
    if (!cellDataClass) cellDataClass = NSClassFromString(@"SessionCellData");
    if (!cellDataClass) cellDataClass = NSClassFromString(@"MMSessionCellData");
    id row = nil;
    if (cellDataClass) {
        @try { row = [[cellDataClass alloc] init]; } @catch (__unused NSException *e) { row = nil; }
    }
    if (!row) row = [[NSObject alloc] init];

    @try {
        [row setValue:[kHBGroupRowPrefix stringByAppendingString:item.identifier] forKey:@"m_nsUserName"];
    } @catch (__unused NSException *e) { }

    [self refreshGroupRow:row item:item chatMode:chatMode];
    engine.groupRowCache[item.identifier] = row;
    return row;
}

+ (void)refreshGroupRow:(id)row item:(HBGroupItem *)item chatMode:(BOOL)chatMode {
    NSString *title = item.name.length ? item.name : (chatMode ? @"群聊分组" : @"好友分组");
    NSString *summary = [self summaryTextForGroup:item chatMode:chatMode];

    @try { [row setValue:title forKey:@"m_textForNameLabel"]; } @catch (__unused NSException *e) { }
    @try { [row setValue:summary forKey:@"m_textForMessageLabel"]; } @catch (__unused NSException *e) { }
    @try { [row setValue:@(NO) forKey:@"m_bIsTop"]; } @catch (__unused NSException *e) { }
    @try { [row setValue:@(0) forKey:@"m_uUnReadCount"]; } @catch (__unused NSException *e) { }
    @try { [row setValue:@(0) forKey:@"m_uAtAllCount"]; } @catch (__unused NSException *e) { }
    @try { [row setValue:@(YES) forKey:@"m_bIsNeedSaveCellData"]; } @catch (__unused NSException *e) { }
}

+ (id)groupAtIndex:(NSUInteger)index top:(BOOL)top manager:(id)manager {
    NSArray *source = top ? [self shared].topSessions : [self shared].normalSessions;
    if (index >= source.count) return nil;
    return source[index];
}

+ (NSString *)summaryTextForGroup:(HBGroupItem *)item chatMode:(BOOL)chatMode {
    HBGroupConfig *config = [HBGroupConfig shared];
    NSMutableArray *lines = [NSMutableArray array];

    NSUInteger unread = 0;
    NSString *lastText = nil;
    NSString *lastSender = nil;

    for (NSString *userName in item.members) {
        id session = [self sessionForUserName:userName chatMode:chatMode];
        if (!session) continue;

        id unreadValue = HBKVC(session, @[@"m_uUnReadCount", @"unReadCount"]);
        if ([unreadValue respondsToSelector:@selector(unsignedIntegerValue)]) {
            unread += [unreadValue unsignedIntegerValue];
        }
        NSString *text = [self summaryOfSession:session];
        if (text.length) {
            lastText = text;
            lastSender = [self displayNameOfSession:session];
            break;
        }
    }

    NSString *body = lastText ?: @"";
    if (!config.hideSummarySender && lastSender.length && body.length) {
        body = [NSString stringWithFormat:config.summaryFormat ?: @"%@: %@", lastSender, body];
    }
    if (body.length) [lines addObject:body];

    if (unread > 0) [lines addObject:[NSString stringWithFormat:@"%lu 条未读", (unsigned long)unread]];

    if (!lines.count) [lines addObject:[NSString stringWithFormat:@"%lu 个会话", (unsigned long)item.members.count]];
    return [lines componentsJoinedByString:@" · "];
}

+ (id)sessionForUserName:(NSString *)userName chatMode:(BOOL)chatMode {
    if (!userName.length) return nil;
    HBGroupEngine *engine = [self shared];
    for (id session in engine.flattenedSessions) {
        if ([[self userNameOfSession:session] isEqualToString:userName]) return session;
    }
    for (id session in engine.allTopSessions) {
        if ([[self userNameOfSession:session] isEqualToString:userName]) return session;
    }
    for (id session in engine.normalSessions) {
        if ([[self userNameOfSession:session] isEqualToString:userName]) return session;
    }
    return nil;
}

#pragma mark - 显示

+ (id)groupCellDataForSession:(id)session {
    if (!session) return nil;
    NSString *userName = [self userNameOfSession:session];
    if (!userName.length) return nil;

    BOOL chatMode = [userName hasSuffix:@"@chatroom"];
    NSString *groupID = [self groupIdentifierForUserName:userName chatMode:chatMode];
    if (!groupID) return session;

    // 单条会话在分组里只做「标记」，真正展示交给分组行
    @try { [session setValue:userName forKey:@"m_nsHeadImgUsrName"]; } @catch (__unused NSException *e) { }
    return session;
}

+ (void)recordHomeRowHeight:(CGFloat)height {
    if (height <= 0) return;
    [HBGroupConfig shared].homeRowHeight = height;
}

+ (UIImage *)avatarForGroupItem:(HBGroupItem *)item {
    if (item.avatarPath.length) {
        UIImage *image = [UIImage imageWithContentsOfFile:item.avatarPath];
        if (image) return image;
    }
    // 没有自定义头像就用第一个成员的头像
    return nil;
}

@end
