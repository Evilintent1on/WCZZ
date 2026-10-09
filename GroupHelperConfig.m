//
//  GroupHelperConfig.m
//  群助手（MiYou 式）：合成入口会话 + 分区名单。
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"

#import <objc/runtime.h>
#import <objc/message.h>

NSString * const MMGroupEnabledKey = @"wczz.group.enabled";
NSString * const MMGroupCommonKey  = @"wczz.group.common";
NSString * const MMGroupManualKey  = @"wczz.group.manual";
NSString * const MMGroupTitleKey   = @"wczz.group.title";
NSString * const MMGroupDebugKey   = @"wczz.group.debug";

static NSString * const kMMGroupHelperUserName = @"wczz_group_helper";

#pragma mark - helpers

static id MMGroupValue(id object, NSString *key) {
    if (!object || !key) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *MMGroupUserNameOf(id session) {
    return MMGroupUserNameOfSession(session);
}

#pragma mark - 会话字段读取（KVC + ivar 兜底）

static id MMGroupIvarValue(id object, NSArray<NSString *> *names) {
    if (!object) return nil;
    for (NSString *name in names) {
        Ivar ivar = class_getInstanceVariable([object class], name.UTF8String);
        if (!ivar) continue;
        const char *type = ivar_getTypeEncoding(ivar);
        if (!type || type[0] != '@') continue;   // 只直读对象类型
        id value = object_getIvar(object, ivar);
        if (value) return value;
    }
    return nil;
}

NSString *MMGroupUserNameOfSession(id session) {
    if (!session) return nil;
    for (NSString *key in @[@"m_nsUserName", @"userName", @"nsUserName", @"username", @"m_username"]) {
        id value = MMGroupValue(session, key);
        if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    }
    id value = MMGroupIvarValue(session, @[@"m_nsUserName", @"_m_nsUserName", @"m_username", @"m_userName"]);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

unsigned int MMGroupUnreadOfSession(id session) {
    if (!session) return 0;
    for (NSString *key in @[@"m_uUnReadCount", @"m_uUnreadCount", @"unreadCount", @"m_nUnReadCount"]) {
        id value = MMGroupValue(session, key);
        if ([value respondsToSelector:@selector(unsignedIntValue)]) return [value unsignedIntValue];
    }
    return 0;
}

unsigned int MMGroupSortTimeOfSession(id session) {
    if (!session) return 0;
    for (NSString *key in @[@"sortTime", @"m_uSortTime", @"m_uTopTime", @"m_uUpdateTime"]) {
        id value = MMGroupValue(session, key);
        if ([value respondsToSelector:@selector(unsignedIntValue)]) return [value unsignedIntValue];
    }
    return 0;
}

NSString *MMGroupDescribeSession(id session) {
    if (!session) return @"(nil)";
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"类=%@ ", NSStringFromClass([session class])];
    for (NSString *key in @[@"m_nsUserName", @"m_nsNickName", @"m_uUnReadCount", @"sortTime"]) {
        id value = MMGroupValue(session, key);
        [out appendFormat:@"%@=%@ ", key, value ?: @"(nil)"];
    }
    Ivar ivar = class_getInstanceVariable([session class], "m_nsUserName");
    [out appendFormat:@"| ivar=%@ ", ivar ? (object_getIvar(session, ivar) ?: @"(nil)") : @"(无)"];
    [out appendFormat:@"| 解析=%@", MMGroupUserNameOfSession(session) ?: @"(失败)"];
    return out;
}

#pragma mark - 主界面控制器

UIViewController *MMGroupMainFrameController(void) {
    Class mainFrameClass = objc_getClass("NewMainFrameViewController");
    if (!mainFrameClass) return nil;
    UIWindow *window = nil;
    for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
        if (candidate.isKeyWindow) { window = candidate; break; }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    NSMutableArray<UIViewController *> *stack = [NSMutableArray array];
    if (window.rootViewController) [stack addObject:window.rootViewController];
    NSInteger guard = 0;
    while (stack.count && guard++ < 64) {
        UIViewController *controller = stack.firstObject;
        [stack removeObjectAtIndex:0];
        if ([controller isKindOfClass:mainFrameClass]) return controller;
        if (controller.presentedViewController) [stack addObject:controller.presentedViewController];
        if ([controller isKindOfClass:[UINavigationController class]]) {
            [stack addObjectsFromArray:((UINavigationController *)controller).viewControllers];
        }
        if ([controller isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
            if (selected) [stack addObject:selected];
        }
        [stack addObjectsFromArray:controller.childViewControllers];
    }
    return nil;
}

static MMNewSessionMgr *MMGroupSessionMgr(void) {
    Class centerClass = objc_getClass("MMServiceCenter");
    if (!centerClass) return nil;
    SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSel = NSSelectorFromString(@"getService:");
    if (![centerClass respondsToSelector:defaultCenterSel]) return nil;
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
    if (!center || ![center respondsToSelector:getServiceSel]) return nil;
    // 会话管理器的类名各版本不同，逐个候选试
    for (NSString *name in @[@"MMNewSessionMgr", @"NewSessionMgr", @"MMSessionMgr", @"SessionMgr",
                             @"MMSessionManager", @"NewSessionManager", @"MMSessionMgrLogic"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        id service = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, cls);
        if (service) return (MMNewSessionMgr *)service;
    }
    return nil;
}

static NSMutableArray<NSString *> *MMGroupStoredList(NSString *key) {
    id raw = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id item in raw) {
            if ([item isKindOfClass:[NSString class]] && [item length]) {
                [list addObject:item];
            }
        }
    }
    return list;
}

static void MMGroupStoreList(NSArray<NSString *> *list, NSString *key) {
    [[NSUserDefaults standardUserDefaults] setObject:(list ?: @[]) forKey:key];
}

static void MMGroupStoreUserName(NSString *userName, BOOL present, NSString *key) {
    NSMutableArray<NSString *> *list = MMGroupStoredList(key);
    BOOL contains = [list containsObject:userName];
    if (present && !contains) {
        [list addObject:userName];
        MMGroupStoreList(list, key);
    } else if (!present && contains) {
        [list removeObject:userName];
        MMGroupStoreList(list, key);
    }
}

#pragma mark - logging

BOOL MMGroupDebugEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:MMGroupDebugKey];
}

void MMGroupSetDebugEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:MMGroupDebugKey];
}

void MMGroupLog(NSString *format, ...) {
    if (!MMGroupDebugEnabled()) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[WCZZ/群助手] %@", message);
}

#pragma mark - switches

BOOL MMGroupIsEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupEnabledKey];
    // 默认开启：MiYou 的群助手就是装完即生效，避免「装了没反应」
    return value ? [value boolValue] : YES;
}

void MMGroupSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:MMGroupEnabledKey];
}

#pragma mark - entry session

NSString *MMGroupHelperUserName(void) {
    return kMMGroupHelperUserName;
}

NSString *MMGroupHelperTitle(void) {
    NSString *title = [[NSUserDefaults standardUserDefaults] stringForKey:MMGroupTitleKey];
    return title.length ? title : @"群助手";
}

void MMGroupSetHelperTitle(NSString *title) {
    if (![title isKindOfClass:[NSString class]] || !title.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:title forKey:MMGroupTitleKey];
}

BOOL MMGroupIsHelperSession(NSString *userName) {
    return [userName isKindOfClass:[NSString class]] && [userName isEqualToString:kMMGroupHelperUserName];
}

BOOL MMGroupIsGroupUserName(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return NO;
    return [userName hasSuffix:@"@chatroom"];
}

#pragma mark - 名单

NSArray<NSString *> *MMGroupCommonList(void) {
    return [MMGroupStoredList(MMGroupCommonKey) copy];
}

void MMGroupSetCommonList(NSArray<NSString *> *list) {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in list) {
        if ([item isKindOfClass:[NSString class]] && [item length] && ![clean containsObject:item]) {
            [clean addObject:item];
        }
    }
    MMGroupStoreList(clean, MMGroupCommonKey);
}

BOOL MMGroupIsCommon(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return NO;
    return [MMGroupStoredList(MMGroupCommonKey) containsObject:userName];
}

void MMGroupSetCommon(NSString *userName, BOOL common) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    MMGroupStoreUserName(userName, common, MMGroupCommonKey);
}

void MMGroupClearCommonList(void) {
    MMGroupStoreList(@[], MMGroupCommonKey);
}

NSArray<NSString *> *MMGroupManualList(void) {
    return [MMGroupStoredList(MMGroupManualKey) copy];
}

void MMGroupSetManualList(NSArray<NSString *> *list) {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in list) {
        if ([item isKindOfClass:[NSString class]] && [item length] && ![clean containsObject:item]) {
            [clean addObject:item];
        }
    }
    MMGroupStoreList(clean, MMGroupManualKey);
}

BOOL MMGroupIsManual(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return NO;
    return [MMGroupStoredList(MMGroupManualKey) containsObject:userName];
}

void MMGroupSetManual(NSString *userName, BOOL manual) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    MMGroupStoreUserName(userName, manual, MMGroupManualKey);
}

#pragma mark - 会话与分组

/// 插件自己取原始会话列表时置位，避免被会话列表 hook 里的过滤/插入影响
/// （否则选择页看不到已经进分组的会话，没法取消勾选）。
static BOOL MMGroupBypassListFilter = NO;

BOOL MMGroupIsBypassingListFilter(void) {
    return MMGroupBypassListFilter;
}

void MMGroupSetBypassingListFilter(BOOL bypassing) {
    MMGroupBypassListFilter = bypassing;
}

NSArray *MMGroupAllSessions(void) {
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    SEL sel = NSSelectorFromString(@"GetSessionInfoList");
    if (!mgr || ![mgr respondsToSelector:sel]) return @[];
    MMGroupBypassListFilter = YES;
    id list = ((id (*)(id, SEL))objc_msgSend)(mgr, sel);
    MMGroupBypassListFilter = NO;
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

NSArray *MMGroupAllGroupSessions(void) {
    NSMutableArray *groups = [NSMutableArray array];
    for (id session in MMGroupAllSessions()) {
        if (MMGroupIsGroupUserName(MMGroupUserNameOf(session))) {
            [groups addObject:session];
        }
    }
    return [groups copy];
}

/// 分组内容 =（所有群聊 − 常用群）∪ 手动加入；入口会话本身永远排除。
NSArray *MMGroupGroupedSessionsFromList(NSArray *allSessions) {
    NSMutableArray *out = [NSMutableArray array];
    if (![allSessions isKindOfClass:[NSArray class]] || allSessions.count == 0) return out;

    NSSet<NSString *> *common = [NSSet setWithArray:MMGroupStoredList(MMGroupCommonKey)];
    NSSet<NSString *> *manual = [NSSet setWithArray:MMGroupStoredList(MMGroupManualKey)];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (id session in allSessions) {
        NSString *userName = MMGroupUserNameOf(session);
        if (!userName.length || MMGroupIsHelperSession(userName)) continue;
        if ([seen containsObject:userName]) continue;
        BOOL grouped = [manual containsObject:userName];
        if (!grouped && MMGroupIsGroupUserName(userName) && ![common containsObject:userName]) {
            grouped = YES;
        }
        if (grouped) {
            [out addObject:session];
            [seen addObject:userName];
        }
    }
    return [out copy];
}

NSArray *MMGroupGroupedSessions(void) {
    return MMGroupGroupedSessionsFromList(MMGroupAllSessions());
}

id MMGroupMakeHelperSessionFromGrouped(NSArray *grouped) {
    if (![grouped isKindOfClass:[NSArray class]] || grouped.count == 0) return nil;

    unsigned int unread = 0;
    unsigned int latest = 0;
    for (id session in grouped) {
        unread += MMGroupUnreadOfSession(session);
        unsigned int sortTime = MMGroupSortTimeOfSession(session);
        if (sortTime > latest) latest = sortTime;
    }

    Class infoClass = objc_getClass("MMSessionInfo");
    if (!infoClass) return nil;

    // 不调 genSessionInfoByUserName:（它会回调会话列表 → 递归/崩溃风险），直接造一个空会话再填字段
    id info = [[infoClass alloc] init];
    if (!info) return nil;

    unsigned int now = (unsigned int)[[NSDate date] timeIntervalSince1970];
    void (^setValue)(NSString *, id) = ^(NSString *key, id value) {
        @try {
            [info setValue:value forKey:key];
        } @catch (__unused NSException *exception) {
            // 该版本没有这个字段，忽略
        }
    };
    setValue(@"m_nsUserName", MMGroupHelperUserName());
    setValue(@"m_nsNickName", MMGroupHelperTitle());
    setValue(@"m_uUnReadCount", @(unread));
    setValue(@"m_bShowUnReadAsRedDot", @(NO));
    setValue(@"sortTime", @(MAX(latest, now)));
    setValue(@"m_uTopTime", @(now));
    setValue(@"m_uUnTopTime", @(0));
    MMGroupLog(@"入口会话: %lu 个会话, 未读 %u", (unsigned long)grouped.count, unread);
    return info;
}

id MMGroupMakeHelperSession(void) {
    return MMGroupMakeHelperSessionFromGrouped(MMGroupGroupedSessions());
}

#pragma mark - 会话列表钩子（候选类名探测 + 运行时安装）

typedef id (*MMGroupGetListIMP)(id, SEL);

static MMGroupGetListIMP MMGroupOrigGetSessionInfoList = NULL;
static NSString *MMGroupHookedClassName = nil;

#pragma mark - 钩子调用记录（诊断只读这些，绝不在诊断里去调微信接口）

static NSUInteger MMGroupHookCalls = 0;
static NSUInteger MMGroupHookLastRawCount = 0;
static NSUInteger MMGroupHookLastGroupedCount = 0;
static NSString *MMGroupHookLastSample = nil;      // 原始会话样本
static NSString *MMGroupHookLastGroupedSample = nil;
static NSString *MMGroupHookLastNote = nil;

static NSString *MMGroupSafeDescribe(id session) {
    @try {
        if (!session) return @"(nil)";
        if (![session respondsToSelector:@selector(class)]) return @"(非对象)";
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"类=%@ ", NSStringFromClass([session class])];
        for (NSString *key in @[@"m_nsUserName", @"m_nsNickName", @"m_uUnReadCount", @"sortTime"]) {
            id value = nil;
            @try { value = [session valueForKey:key]; } @catch (__unused NSException *e) { value = nil; }
            [out appendFormat:@"%@=%@ ", key, value ?: @"(nil)"];
        }
        Ivar ivar = class_getInstanceVariable([session class], "m_nsUserName");
        if (ivar && ivar_getTypeEncoding(ivar) && ivar_getTypeEncoding(ivar)[0] == '@') {
            id iv = nil;
            @try { iv = object_getIvar(session, ivar); } @catch (__unused NSException *e) { iv = nil; }
            [out appendFormat:@"| ivar=%@ ", iv ?: @"(nil)"];
        } else {
            [out appendString:@"| ivar=(无) "];
        }
        [out appendFormat:@"| 解析=%@", MMGroupUserNameOfSession(session) ?: @"(失败)"];
        return out;
    } @catch (__unused NSException *exception) {
        return @"(采样异常)";
    }
}

static void MMGroupRecordHookCall(NSArray *raw, NSArray *grouped) {
    MMGroupHookCalls++;
    MMGroupHookLastRawCount = raw.count;
    MMGroupHookLastGroupedCount = grouped.count;
    NSMutableString *sample = [NSMutableString string];
    NSUInteger limit = MIN((NSUInteger)3, raw.count);
    for (NSUInteger i = 0; i < limit; i++) {
        [sample appendFormat:@"[%lu] %@\n", (unsigned long)i, MMGroupSafeDescribe(raw[i])];
    }
    MMGroupHookLastSample = sample.length ? [sample copy] : @"(原始列表为空)";

    NSMutableString *groupedSample = [NSMutableString string];
    NSUInteger glimit = MIN((NSUInteger)3, grouped.count);
    for (NSUInteger i = 0; i < glimit; i++) {
        [groupedSample appendFormat:@"[%lu] %@\n", (unsigned long)i, MMGroupSafeDescribe(grouped[i])];
    }
    MMGroupHookLastGroupedSample = groupedSample.length ? [groupedSample copy] : @"(没有会话进分组)";
    MMGroupHookLastNote = [NSString stringWithFormat:@"%@", [NSDate date]];
}

NSArray<NSString *> *MMGroupSessionMgrCandidates(void) {
    return @[@"MMNewSessionMgr", @"NewSessionMgr", @"MMSessionMgr", @"SessionMgr",
             @"MMSessionManager", @"NewSessionManager", @"MMSessionMgrLogic"];
}

BOOL MMGroupSessionListHookInstalled(void) {
    return MMGroupOrigGetSessionInfoList != NULL;
}

NSString *MMGroupSessionListHookClassName(void) {
    return MMGroupHookedClassName;
}

/// 钩子本体：摘掉分组内会话 + 在最前面插入「群助手」入口会话。
/// 整个实现都在 bypass 标志 + @try 里：微信内部任何再次取列表的调用都不会递归，异常也不会崩微信。
static id MMGroupGetSessionInfoListHook(id self, SEL _cmd) {
    id raw = MMGroupOrigGetSessionInfoList ? MMGroupOrigGetSessionInfoList(self, _cmd) : nil;
    if (MMGroupIsBypassingListFilter()) return raw;
    if (!MMGroupIsEnabled() || ![raw isKindOfClass:[NSArray class]]) return raw;

    BOOL previous = MMGroupIsBypassingListFilter();
    MMGroupSetBypassingListFilter(YES);      // 防止内部回调再次进入本钩子
    id result = raw;
    @try {
        NSArray *list = (NSArray *)raw;
        NSArray *grouped = MMGroupGroupedSessionsFromList(list);
        MMGroupRecordHookCall(list, grouped);
        if (grouped.count > 0) {
            NSMutableSet<NSString *> *hidden = [NSMutableSet set];
            for (id session in grouped) {
                NSString *userName = MMGroupUserNameOfSession(session);
                if (userName.length) [hidden addObject:userName];
            }
            NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:list.count + 1];
            for (id session in list) {
                NSString *userName = MMGroupUserNameOfSession(session);
                if (userName.length && [hidden containsObject:userName]) continue;
                [filtered addObject:session];
            }
            id helper = MMGroupMakeHelperSessionFromGrouped(grouped);
            if (helper) [filtered insertObject:helper atIndex:0];
            MMGroupLog(@"会话列表：收起 %lu 个（原始 %lu），入口 %@",
                       (unsigned long)hidden.count, (unsigned long)list.count, helper ? @"已插入" : @"生成失败");
            result = [filtered copy];
        } else {
            MMGroupLog(@"会话列表：没有需要收起的会话（原始 %lu 个）", (unsigned long)list.count);
        }
    } @catch (NSException *exception) {
        MMGroupLog(@"会话列表钩子异常: %@", exception);
        result = raw;
    }
    MMGroupSetBypassingListFilter(previous);
    return result;
}

BOOL MMGroupInstallSessionListHook(void) {
    if (MMGroupOrigGetSessionInfoList != NULL) return YES;
    SEL sel = NSSelectorFromString(@"GetSessionInfoList");
    for (NSString *name in MMGroupSessionMgrCandidates()) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        Method method = class_getInstanceMethod(cls, sel);
        if (!method) continue;
        MMGroupOrigGetSessionInfoList = (MMGroupGetListIMP)method_getImplementation(method);
        method_setImplementation(method, (IMP)MMGroupGetSessionInfoListHook);
        MMGroupHookedClassName = name;
        MMGroupLog(@"已在 %@ 上安装 GetSessionInfoList 钩子", name);
        return YES;
    }
    MMGroupLog(@"安装 GetSessionInfoList 钩子失败：候选类都不存在");
    return NO;
}

void MMGroupForceReloadSessions(void) {
    // 不要调 rebuildAndUpdateSessionInfo（会触发完整重建 → 回调本钩子，容易递归/崩溃）。
    // 安全做法：让主界面把可见的表格重新加载一次。
    @try {
        UIViewController *mainFrame = MMGroupMainFrameController();
        BOOL reloaded = NO;
        if (mainFrame) {
            id tableView = MMGroupValue(mainFrame, @"tableView");
            if ([tableView isKindOfClass:[UITableView class]]) {
                [(UITableView *)tableView reloadData];
                reloaded = YES;
            }
            SEL reloadSel = NSSelectorFromString(@"reloadTableData");
            if ([mainFrame respondsToSelector:reloadSel]) {
                ((void (*)(id, SEL))objc_msgSend)(mainFrame, reloadSel);
                reloaded = YES;
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"MMSessionInfoChanged" object:nil];
        MMGroupLog(@"刷新会话列表：%@", reloaded ? @"已重新加载" : @"没找到主界面，仅发了通知");
    } @catch (NSException *exception) {
        MMGroupLog(@"刷新会话列表异常: %@", exception);
    }
}

#pragma mark - 视图层过滤（微信列表真正读的那一层）

// 实测：只改 GetSessionInfoList 的返回值，微信界面不动（钩子被调用 13 次、算出 28 个群也没变化），
// 因为主界面是按 logicGetCountForSection: / logicGetSessionAtIndexPath: / logicGetCellDataAtIndexPath:
// 逐行取自己缓存的。所以在这一层做「显示映射」。
typedef long long (*MMGroupCountIMP)(id, SEL, long long);
typedef id (*MMGroupIndexIMP)(id, SEL, id);

static MMGroupCountIMP MMGroupOrigLogicCount = NULL;
static MMGroupIndexIMP MMGroupOrigLogicSession = NULL;
static MMGroupIndexIMP MMGroupOrigLogicCellData = NULL;

static NSArray *MMGroupDisplaySlots = nil;        // 元素：@(原始行号) 或 @"__helper__"
static id MMGroupDisplayHelperSession = nil;      // 入口行的伪会话
static id MMGroupDisplayHelperCellData = nil;     // 入口行的 cellData（从真实行克隆后改字段）
static NSUInteger MMGroupDisplaySourceCount = 0;  // 生成映射时的原始行数
static NSTimeInterval MMGroupDisplayBuiltAt = 0;
static BOOL MMGroupBuildingDisplay = NO;
static NSString *MMGroupCellDataProbeText = nil;

static NSString * const kMMGroupHelperSlot = @"__helper__";

static SEL MMGroupCountSel(void) { return NSSelectorFromString(@"logicGetCountForSection:"); }
static SEL MMGroupSessionSel(void) { return NSSelectorFromString(@"logicGetSessionAtIndexPath:"); }
static SEL MMGroupCellDataSel(void) { return NSSelectorFromString(@"logicGetCellDataAtIndexPath:"); }

/// 入口行 cellData：从某个真实会话的 cellData 克隆过来，尽量把标题/用户名/未读改成群助手的。
static void MMGroupPatchHelperCellData(id cellData, unsigned int unread) {
    if (!cellData) return;
    NSMutableString *probe = [NSMutableString string];
    [probe appendFormat:@"类=%@\n", NSStringFromClass([cellData class])];
    for (NSString *key in @[@"m_nsUserName", @"m_nsNickName", @"m_nsTitle", @"m_title",
                            @"m_uUnReadCount", @"m_uUnreadCount", @"m_bShowUnReadAsRedDot"]) {
        id value = nil;
        @try { value = [cellData valueForKey:key]; } @catch (__unused NSException *e) { value = @"(无此字段)"; }
        [probe appendFormat:@"  %@ = %@\n", key, value ?: @"(nil)"];
    }
    MMGroupCellDataProbeText = [probe copy];

    void (^setValue)(NSString *, id) = ^(NSString *key, id value) {
        @try { [cellData setValue:value forKey:key]; } @catch (__unused NSException *e) {}
    };
    setValue(@"m_nsUserName", MMGroupHelperUserName());
    setValue(@"m_nsNickName", MMGroupHelperTitle());
    setValue(@"m_nsTitle", MMGroupHelperTitle());
    setValue(@"m_title", MMGroupHelperTitle());
    setValue(@"m_uUnReadCount", @(unread));
    setValue(@"m_uUnreadCount", @(unread));
    setValue(@"m_bShowUnReadAsRedDot", @(NO));
}

static void MMGroupRebuildDisplayMap(id controller) {
    if (MMGroupBuildingDisplay || !MMGroupOrigLogicCount || !MMGroupOrigLogicSession) return;
    MMGroupBuildingDisplay = YES;
    @try {
        long long n = MMGroupOrigLogicCount(controller, MMGroupCountSel(), 0);
        if (n <= 0) {
            MMGroupDisplaySlots = nil;
            MMGroupDisplayHelperSession = nil;
            MMGroupDisplayHelperCellData = nil;
            MMGroupDisplaySourceCount = 0;
        } else {
            NSMutableArray *slots = [NSMutableArray arrayWithCapacity:(NSUInteger)n + 1];
            NSMutableArray *keptRows = [NSMutableArray array];
            NSMutableArray *grouped = [NSMutableArray array];
            NSSet<NSString *> *common = [NSSet setWithArray:MMGroupCommonList()];
            NSSet<NSString *> *manual = [NSSet setWithArray:MMGroupManualList()];
            NSIndexPath *firstGroupedIndexPath = nil;
            BOOL helperAlreadyListed = NO;

            for (long long i = 0; i < n; i++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                id session = MMGroupOrigLogicSession(controller, MMGroupSessionSel(), indexPath);
                NSString *userName = MMGroupUserNameOfSession(session);
                if (MMGroupIsHelperSession(userName)) {
                    helperAlreadyListed = YES;      // 模型层已经插过入口行了，别重复插
                    [keptRows addObject:@(i)];
                    continue;
                }
                if (!userName.length) {
                    [keptRows addObject:@(i)];
                    continue;
                }
                BOOL shouldGroup = MMGroupIsEnabled() &&
                    ([manual containsObject:userName] ||
                     (MMGroupIsGroupUserName(userName) && ![common containsObject:userName]));
                if (shouldGroup) {
                    [grouped addObject:session];
                    if (!firstGroupedIndexPath) firstGroupedIndexPath = indexPath;
                } else {
                    [keptRows addObject:@(i)];
                }
            }

            unsigned int unread = 0;
            for (id session in grouped) unread += MMGroupUnreadOfSession(session);

            MMGroupDisplayHelperCellData = nil;
            if (grouped.count && firstGroupedIndexPath && MMGroupOrigLogicCellData) {
                id cellData = MMGroupOrigLogicCellData(controller, MMGroupCellDataSel(), firstGroupedIndexPath);
                if (cellData) {
                    MMGroupPatchHelperCellData(cellData, unread);
                    MMGroupDisplayHelperCellData = cellData;
                }
            }
            MMGroupDisplayHelperSession = MMGroupMakeHelperSessionFromGrouped(grouped);

            if (grouped.count && !helperAlreadyListed) {
                [slots addObject:kMMGroupHelperSlot];
            }
            [slots addObjectsFromArray:keptRows];
            MMGroupDisplaySlots = [slots copy];
            MMGroupDisplaySourceCount = (NSUInteger)n;
            MMGroupDisplayBuiltAt = [NSDate timeIntervalSinceReferenceDate];
            MMGroupLog(@"视图层：原始 %lld 行 → 显示 %lu 行（收起 %lu 个，入口%@）",
                       n, (unsigned long)slots.count, (unsigned long)grouped.count,
                       helperAlreadyListed ? @"来自模型层" : (grouped.count ? @"由视图层插入" : @"无"));
        }
    } @catch (NSException *exception) {
        MMGroupLog(@"视图层映射异常: %@", exception);
        MMGroupDisplaySlots = nil;
    }
    MMGroupBuildingDisplay = NO;
}

/// 取显示映射（按原始行数 + 2 秒新鲜度缓存）
static NSArray *MMGroupDisplaySlotsFor(id controller) {
    if (!MMGroupIsEnabled() || !MMGroupOrigLogicCount) return nil;
    long long n = MMGroupOrigLogicCount(controller, MMGroupCountSel(), 0);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!MMGroupDisplaySlots || (NSUInteger)n != MMGroupDisplaySourceCount || now - MMGroupDisplayBuiltAt > 2.0) {
        MMGroupRebuildDisplayMap(controller);
    }
    return MMGroupDisplaySlots;
}

static long long MMGroupLogicCountHook(id self, SEL _cmd, long long section) {
    long long n = MMGroupOrigLogicCount ? MMGroupOrigLogicCount(self, _cmd, section) : 0;
    if (section != 0 || !MMGroupIsEnabled()) return n;
    NSArray *slots = MMGroupDisplaySlotsFor(self);
    if (!slots.count) return n;
    return (long long)slots.count;
}

static id MMGroupLogicSessionHook(id self, SEL _cmd, id indexPath) {
    NSArray *slots = MMGroupDisplaySlotsFor(self);
    if (!slots.count || !MMGroupOrigLogicSession || !indexPath) {
        return MMGroupOrigLogicSession(self, _cmd, indexPath);
    }
    NSInteger section = [indexPath section];
    NSInteger row = [indexPath row];
    if (section != 0 || row < 0 || row >= (NSInteger)slots.count) {
        return MMGroupOrigLogicSession(self, _cmd, indexPath);
    }
    id slot = slots[(NSUInteger)row];
    if ([slot isKindOfClass:[NSString class]] && [slot isEqualToString:kMMGroupHelperSlot]) {
        return MMGroupDisplayHelperSession;
    }
    NSIndexPath *mapped = [NSIndexPath indexPathForRow:[slot integerValue] inSection:0];
    return MMGroupOrigLogicSession(self, _cmd, mapped);
}

static id MMGroupLogicCellDataHook(id self, SEL _cmd, id indexPath) {
    NSArray *slots = MMGroupDisplaySlotsFor(self);
    if (!slots.count || !MMGroupOrigLogicCellData || !indexPath) {
        return MMGroupOrigLogicCellData ? MMGroupOrigLogicCellData(self, _cmd, indexPath) : nil;
    }
    NSInteger section = [indexPath section];
    NSInteger row = [indexPath row];
    if (section != 0 || row < 0 || row >= (NSInteger)slots.count) {
        return MMGroupOrigLogicCellData(self, _cmd, indexPath);
    }
    id slot = slots[(NSUInteger)row];
    if ([slot isKindOfClass:[NSString class]] && [slot isEqualToString:kMMGroupHelperSlot]) {
        return MMGroupDisplayHelperCellData;    // 入口行
    }
    NSIndexPath *mapped = [NSIndexPath indexPathForRow:[slot integerValue] inSection:0];
    return MMGroupOrigLogicCellData(self, _cmd, mapped);
}

BOOL MMGroupViewHooksInstalled(void) {
    return MMGroupOrigLogicCount != NULL && MMGroupOrigLogicSession != NULL;
}

BOOL MMGroupInstallViewHooks(void) {
    if (MMGroupViewHooksInstalled()) return YES;
    Class cls = objc_getClass("NewMainFrameViewController");
    if (!cls) return NO;
    Method countMethod = class_getInstanceMethod(cls, MMGroupCountSel());
    Method sessionMethod = class_getInstanceMethod(cls, MMGroupSessionSel());
    if (!countMethod || !sessionMethod) {
        MMGroupLog(@"安装视图层钩子失败：主界面缺少 logicGet 方法");
        return NO;
    }
    MMGroupOrigLogicCount = (MMGroupCountIMP)method_getImplementation(countMethod);
    MMGroupOrigLogicSession = (MMGroupIndexIMP)method_getImplementation(sessionMethod);
    method_setImplementation(countMethod, (IMP)MMGroupLogicCountHook);
    method_setImplementation(sessionMethod, (IMP)MMGroupLogicSessionHook);

    Method cellDataMethod = class_getInstanceMethod(cls, MMGroupCellDataSel());
    if (cellDataMethod) {
        MMGroupOrigLogicCellData = (MMGroupIndexIMP)method_getImplementation(cellDataMethod);
        method_setImplementation(cellDataMethod, (IMP)MMGroupLogicCellDataHook);
    }
    MMGroupLog(@"已在 NewMainFrameViewController 安装视图层过滤钩子（cellData 钩子 %@）",
               cellDataMethod ? @"已装" : @"缺失");
    return YES;
}

NSString *MMGroupCellDataProbe(void) {
    return MMGroupCellDataProbeText ?: @"(还没有取过入口行 cellData)";
}

#pragma mark - 诊断

NSString *MMGroupDiagnostics(void) {
    NSMutableString *out = [NSMutableString string];
    @try {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    [out appendString:@"WCZZ 群助手诊断\n"];
    [out appendFormat:@"微信版本: %@ (%@)\n", info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
#ifdef PACKAGE_VERSION
    [out appendFormat:@"插件版本: %@\n", PACKAGE_VERSION];
#endif
    [out appendString:@"\n-- 开关 --\n"];
    [out appendFormat:@"启用: %@\n", MMGroupIsEnabled() ? @"是" : @"否（功能不会生效，去设置页打开）"];
    [out appendFormat:@"常用群: %lu 个\n", (unsigned long)MMGroupCommonList().count];
    [out appendFormat:@"手动加入: %lu 个\n", (unsigned long)MMGroupManualList().count];

    [out appendString:@"\n-- 会话管理器候选类 --\n"];
    for (NSString *name in MMGroupSessionMgrCandidates()) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) {
            [out appendFormat:@"%@: 无\n", name];
            continue;
        }
        BOOL hasSel = class_getInstanceMethod(cls, NSSelectorFromString(@"GetSessionInfoList")) != NULL;
        [out appendFormat:@"%@: 存在%@\n", name, hasSel ? @" / 有 GetSessionInfoList" : @" / 无 GetSessionInfoList"];
    }
    [out appendFormat:@"钩子: %@", MMGroupSessionListHookInstalled() ? @"已安装" : @"未安装"];
    if (MMGroupSessionListHookInstalled()) [out appendFormat:@" (%@)", MMGroupSessionListHookClassName() ?: @"?"];
    [out appendString:@"\n"];

    // 决定性信息：不管类名怎么变，找出真正实现了 GetSessionInfoList 的类（限 20 条，纯运行时查询）
    [out appendString:@"\n-- 实现了 GetSessionInfoList 的类（全类扫描，最多列 20 个）--\n"];
    @try {
        SEL listSel = NSSelectorFromString(@"GetSessionInfoList");
        unsigned int classCount = 0;
        Class *classList = objc_copyClassList(&classCount);
        NSMutableArray<NSString *> *owners = [NSMutableArray array];
        if (classList) {
            for (unsigned int i = 0; i < classCount && owners.count < 20; i++) {
                Class cls = classList[i];
                if (!cls) continue;
                if (class_getInstanceMethod(cls, listSel)) {
                    [owners addObject:NSStringFromClass(cls)];
                }
            }
            free(classList);
        }
        if (owners.count == 0) {
            [out appendString:@"一个都没有（说明这个方法名在这个版本不存在）\n"];
        } else {
            for (NSString *name in [owners sortedArrayUsingSelector:@selector(compare:)]) {
                [out appendFormat:@"%@\n", name];
            }
        }
    } @catch (NSException *exception) {
        [out appendFormat:@"扫描异常: %@\n", exception];
    }

    [out appendString:@"\n-- 其它关键类 --\n"];
    NSArray<NSString *> *classes = @[@"NewMainFrameViewController", @"MainFrameLogicController",
                                     @"MainFrameCellDataManager", @"ChatRoomInfoViewController",
                                     @"MMSessionInfo", @"MMServiceCenter", @"CContactMgr"];
    for (NSString *name in classes) {
        [out appendFormat:@"%@: %@\n", name, objc_getClass(name.UTF8String) ? @"存在" : @"无"];
    }
    Class mainFrame = objc_getClass("NewMainFrameViewController");
    if (mainFrame) {
        [out appendFormat:@"logicGetSessionAtIndexPath: %@\n",
         [mainFrame instancesRespondToSelector:NSSelectorFromString(@"logicGetSessionAtIndexPath:")] ? @"有" : @"无"];
        [out appendFormat:@"onLogicOpenSession: %@\n",
         [mainFrame instancesRespondToSelector:NSSelectorFromString(@"onLogicOpenSession:")] ? @"有" : @"无"];
    }

    [out appendString:@"\n-- 会话数据（来自钩子被调用时的记录，诊断本身不碰微信接口）--\n"];
    if (MMGroupHookCalls == 0) {
        [out appendString:@"GetSessionInfoList 一次都没被调用过\n"];
        [out appendString:@"→ 说明微信的会话列表不走这个方法，需要改成视图层方案\n"];
    } else {
        [out appendFormat:@"GetSessionInfoList 调用次数: %lu\n", (unsigned long)MMGroupHookCalls];
        [out appendFormat:@"最近一次: 原始 %lu 个会话，算出应进分组 %lu 个\n",
         (unsigned long)MMGroupHookLastRawCount, (unsigned long)MMGroupHookLastGroupedCount];
        [out appendFormat:@"最近记录时间: %@\n", MMGroupHookLastNote ?: @"?"];
        [out appendString:@"原始会话样本:\n"];
        [out appendString:MMGroupHookLastSample ?: @"(无)\n"];
        [out appendString:@"\n进分组的会话样本:\n"];
        [out appendString:MMGroupHookLastGroupedSample ?: @"(无)\n"];
    }

    [out appendString:@"\n-- 视图层（微信列表真正读的一层）--\n"];
    [out appendFormat:@"logicGet* 钩子: %@\n", MMGroupViewHooksInstalled() ? @"已安装" : @"未安装"];
    if (MMGroupDisplaySlots.count) {
        [out appendFormat:@"显示映射: 原始 %lu 行 → 显示 %lu 行\n",
         (unsigned long)MMGroupDisplaySourceCount, (unsigned long)MMGroupDisplaySlots.count];
    } else {
        [out appendString:@"显示映射: 还没有生成（没进过会话列表？）\n"];
    }
    [out appendFormat:@"入口行 cellData 探测:\n%@\n", MMGroupCellDataProbe()];

    [out appendFormat:@"\n时间: %@", [NSDate date]];
    } @catch (NSException *exception) {
        [out appendFormat:@"\n诊断采集异常: %@\n", exception];
    }
    return [out copy];
}

#pragma mark - 显示 / 诊断

id MMGroupValueSafe(id object, NSString *key) {
    return MMGroupValue(object, key);
}

NSString *MMGroupRuntimeStatus(void) {
    // 会话管理器：钩子装上了就是可用（类名不写死）
    if (!MMGroupSessionListHookInstalled() && !MMGroupInstallSessionListHook()) {
        return @"不可用：找不到会话管理器类";
    }
    if (!objc_getClass("MMSessionInfo")) return @"不可用：缺少 MMSessionInfo";

    Class mainFrame = objc_getClass("NewMainFrameViewController");
    if (!mainFrame) return @"不可用：缺少会话列表类";
    for (NSString *selectorName in @[@"logicGetSessionAtIndexPath:", @"onLogicOpenSession:"]) {
        if (![mainFrame instancesRespondToSelector:NSSelectorFromString(selectorName)]) {
            return [NSString stringWithFormat:@"部分可用：主界面缺少 %@", selectorName];
        }
    }
    if (!objc_getClass("ChatRoomInfoViewController")) {
        return @"部分可用：群聊信息页开关缺失";
    }
    return @"可用";
}

NSString *MMGroupDisplayName(NSString *userName, NSString *fallback) {
    if (MMGroupIsHelperSession(userName)) return MMGroupHelperTitle();
    if (![userName isKindOfClass:[NSString class]] || !userName.length) {
        return [fallback isKindOfClass:[NSString class]] ? fallback : @"";
    }
    Class centerClass = objc_getClass("MMServiceCenter");
    Class contactMgrClass = objc_getClass("CContactMgr");
    if (centerClass && contactMgrClass) {
        SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
        SEL getServiceSel = NSSelectorFromString(@"getService:");
        SEL getContactSel = NSSelectorFromString(@"getContactByName:");
        id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
        id contactMgr = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, contactMgrClass);
        if ([contactMgr respondsToSelector:getContactSel]) {
            id contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, getContactSel, userName);
            NSString *remark = MMGroupValue(contact, @"m_nsRemark");
            NSString *nick = MMGroupValue(contact, @"m_nsNickName");
            if ([remark isKindOfClass:[NSString class]] && remark.length) return remark;
            if ([nick isKindOfClass:[NSString class]] && nick.length) return nick;
        }
    }
    return [fallback isKindOfClass:[NSString class]] && fallback.length ? fallback : userName;
}
