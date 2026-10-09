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
    NSString *userName = MMGroupValue(session, @"m_nsUserName");
    return [userName isKindOfClass:[NSString class]] ? userName : nil;
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
        unread += (unsigned int)[MMGroupValue(session, @"m_uUnReadCount") unsignedIntValue];
        unsigned int sortTime = (unsigned int)[MMGroupValue(session, @"sortTime") unsignedIntValue];
        if (sortTime > latest) latest = sortTime;
    }

    Class infoClass = objc_getClass("MMSessionInfo");
    if (!infoClass) return nil;

    id info = nil;
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    SEL genSel = NSSelectorFromString(@"genSessionInfoByUserName:");
    if (mgr && [mgr respondsToSelector:genSel]) {
        info = ((id (*)(id, SEL, id))objc_msgSend)(mgr, genSel, MMGroupHelperUserName());
    }
    if (![info isKindOfClass:infoClass]) {
        info = [[infoClass alloc] init];
    }
    if (!info) return nil;

    unsigned int now = (unsigned int)[[NSDate date] timeIntervalSince1970];
    @try {
        [info setValue:MMGroupHelperUserName() forKey:@"m_nsUserName"];
        [info setValue:MMGroupHelperTitle() forKey:@"m_nsNickName"];
        [info setValue:@(unread) forKey:@"m_uUnReadCount"];
        [info setValue:@(NO) forKey:@"m_bShowUnReadAsRedDot"];
        [info setValue:@(MAX(latest, now)) forKey:@"sortTime"];
        [info setValue:@(now) forKey:@"m_uTopTime"];
        [info setValue:@(0) forKey:@"m_uUnTopTime"];
    } @catch (NSException *exception) {
        MMGroupLog(@"合成入口会话失败: %@", exception);
    }
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
static id MMGroupGetSessionInfoListHook(id self, SEL _cmd) {
    id raw = MMGroupOrigGetSessionInfoList ? MMGroupOrigGetSessionInfoList(self, _cmd) : nil;
    if (MMGroupIsBypassingListFilter()) return raw;
    if (!MMGroupIsEnabled() || ![raw isKindOfClass:[NSArray class]]) return raw;

    NSArray *list = (NSArray *)raw;          // 显式定型：不要对 id 用点语法
    NSArray *grouped = MMGroupGroupedSessionsFromList(list);
    if (grouped.count == 0) return list;

    NSMutableSet<NSString *> *hidden = [NSMutableSet set];
    for (id session in grouped) {
        NSString *userName = MMGroupValue(session, @"m_nsUserName");
        if ([userName isKindOfClass:[NSString class]] && userName.length) {
            [hidden addObject:userName];
        }
    }

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:list.count + 1];
    for (id session in list) {
        NSString *userName = MMGroupValue(session, @"m_nsUserName");
        if ([userName isKindOfClass:[NSString class]] && [hidden containsObject:userName]) continue;
        [result addObject:session];
    }
    id helper = MMGroupMakeHelperSessionFromGrouped(grouped);
    if (helper) [result insertObject:helper atIndex:0];
    MMGroupLog(@"会话列表：收起 %lu 个，入口 %@", (unsigned long)hidden.count, helper ? @"已插入" : @"生成失败");
    return [result copy];
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
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    SEL sel = NSSelectorFromString(@"rebuildAndUpdateSessionInfo");
    if (mgr && [mgr respondsToSelector:sel]) {
        ((void (*)(id, SEL))objc_msgSend)(mgr, sel);
        MMGroupLog(@"已请求微信重建会话列表");
    } else {
        MMGroupLog(@"rebuildAndUpdateSessionInfo 不存在，无法强制刷新");
    }
}

#pragma mark - 诊断

NSString *MMGroupDiagnostics(void) {
    NSMutableString *out = [NSMutableString string];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    [out appendString:@"WCZZ 群助手诊断\n"];
    [out appendFormat:@"微信版本: %@ (%@)\n", info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
#ifdef PACKAGE_VERSION
    [out appendFormat:@"插件版本: %s\n", PACKAGE_VERSION];
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

    // 决定性信息：不管类名怎么变，找出真正实现了 GetSessionInfoList 的类
    [out appendString:@"\n-- 实现了 GetSessionInfoList 的类（全类扫描）--\n"];
    SEL listSel = NSSelectorFromString(@"GetSessionInfoList");
    unsigned int classCount = 0;
    Class *classList = objc_copyClassList(&classCount);
    NSMutableArray<NSString *> *owners = [NSMutableArray array];
    if (classList) {
        for (unsigned int i = 0; i < classCount; i++) {
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

    [out appendString:@"\n-- 会话数据 --\n"];
    NSArray *all = MMGroupAllSessions();
    NSArray *groups = MMGroupAllGroupSessions();
    NSArray *grouped = MMGroupGroupedSessionsFromList(all);
    [out appendFormat:@"会话总数: %lu（群聊 %lu）\n", (unsigned long)all.count, (unsigned long)groups.count];
    [out appendFormat:@"应进分组: %lu\n", (unsigned long)grouped.count];
    [out appendFormat:@"入口会话可生成: %@\n", MMGroupMakeHelperSessionFromGrouped(grouped) ? @"是" : @"否（分组为空或类缺失）"];
    unsigned int unread = 0;
    for (id session in grouped) unread += (unsigned int)[MMGroupValue(session, @"m_uUnReadCount") unsignedIntValue];
    [out appendFormat:@"分组未读合计: %u\n", unread];
    [out appendFormat:@"\n时间: %@", [NSDate date]];
    return [out copy];
}

#pragma mark - 显示 / 诊断

id MMGroupValueSafe(id object, NSString *key) {
    return MMGroupValue(object, key);
}

NSString *MMGroupRuntimeStatus(void) {
    if (!MMGroupSessionListHookInstalled() && !MMGroupInstallSessionListHook()) {
        return @"不可用：找不到会话管理器类";
    }
    if (!objc_getClass("MMSessionInfo")) return @"不可用：缺少 MMSessionInfo";
    Class helper = objc_getClass("NewMainFrameViewController");
    if (!helper) return @"部分可用：会话列表类缺失";
    NSArray<NSString *> *needed = @[@"GetSessionInfoList", @"logicGetSessionAtIndexPath:", @"onLogicOpenSession:"];
    for (NSString *selectorName in needed) {
        SEL sel = NSSelectorFromString(selectorName);
        if (![helper instancesRespondToSelector:sel] && ![helper respondsToSelector:sel]) {
            return [NSString stringWithFormat:@"部分可用：缺少 %@", selectorName];
        }
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
