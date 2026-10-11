//
//  GroupHelperConfig.m
//  群助手 —— MiYou (微信助手) 3.9-5 GroupTool 语义复刻。
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"

#import <objc/runtime.h>
#import <objc/message.h>

NSString * const MMGroupEnabledKey    = @"wczz.group.enabled";
NSString * const MMGroupShowHelperKey = @"wczz.group.showHelper";
NSString * const MMGroupHelperTopKey  = @"wczz.group.helperTop";
NSString * const MMGroupHelperIdxKey  = @"wczz.group.helperIdx";
NSString * const MMGroupIncoTypeKey   = @"wczz.group.incoType";
NSString * const MMGroupRoomListKey   = @"wczz.group.roomList";
NSString * const MMGroupTitleKey      = @"wczz.group.title";
NSString * const MMGroupDebugKey      = @"wczz.group.debug";

static NSString * const kMMGroupHelperUserName = @"MGRoomHelper";   // MiYou 的真实入口 username
static NSString * const kMMGroupHelperSlot = @"__helper__";

/// inRoomList（运行时状态，对应 MiYou 注入到 NewMainFrameViewController 的同名属性）
static BOOL MMGroupInsideHelper = NO;
/// 插件自己取原始会话列表时置位，避免被钩子过滤
static BOOL MMGroupBypassListFilter = NO;
/// 会话列表钩子重入保护
static BOOL MMGroupBuildingDisplay = NO;

#pragma mark - 基础取值

static id MMGroupValue(id object, NSString *key) {
    if (!object || !key) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id MMGroupIvarValue(id object, NSArray<NSString *> *names) {
    if (!object) return nil;
    for (NSString *name in names) {
        Ivar ivar = class_getInstanceVariable([object class], name.UTF8String);
        if (!ivar) continue;
        const char *type = ivar_getTypeEncoding(ivar);
        if (!type || type[0] != '@') continue;
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

id MMGroupValueSafe(id object, NSString *key) {
    return MMGroupValue(object, key);
}

NSString *MMGroupDescribeSession(id session) {
    if (!session) return @"(nil)";
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"类=%@ ", NSStringFromClass([session class])];
    for (NSString *key in @[@"m_nsUserName", @"m_nsNickName", @"m_uUnReadCount", @"sortTime"]) {
        id value = MMGroupValue(session, key);
        [out appendFormat:@"%@=%@ ", key, value ?: @"(nil)"];
    }
    [out appendFormat:@"| 解析=%@", MMGroupUserNameOfSession(session) ?: @"(失败)"];
    return out;
}

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

static NSMutableArray<NSString *> *MMGroupStoredList(NSString *key) {
    id raw = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
    NSMutableArray<NSString *> *list = [NSMutableArray array];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id item in raw) {
            if ([item isKindOfClass:[NSString class]] && [item length]) [list addObject:item];
        }
    }
    return list;
}

static void MMGroupStoreList(NSArray<NSString *> *list, NSString *key) {
    [[NSUserDefaults standardUserDefaults] setObject:(list ?: @[]) forKey:key];
}

static MMNewSessionMgr *MMGroupSessionMgr(void) {
    Class centerClass = objc_getClass("MMServiceCenter");
    if (!centerClass) return nil;
    SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSel = NSSelectorFromString(@"getService:");
    if (![centerClass respondsToSelector:defaultCenterSel]) return nil;
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
    if (!center || ![center respondsToSelector:getServiceSel]) return nil;
    for (NSString *name in @[@"MMNewSessionMgr", @"NewSessionMgr", @"MMSessionMgr", @"SessionMgr"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (!cls) continue;
        id service = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, cls);
        if (service) return (MMNewSessionMgr *)service;
    }
    return nil;
}

#pragma mark - 调试日志

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

#pragma mark - 开关（GroupTool 的 isOpen*）

BOOL MMGroupIsEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupEnabledKey];
    return value ? [value boolValue] : YES;      // MiYou 装完即生效
}

void MMGroupSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:MMGroupEnabledKey];
}

BOOL MMGroupShowHelper(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupShowHelperKey];
    return value ? [value boolValue] : YES;      // isOpenRoomHelper
}

void MMGroupSetShowHelper(BOOL show) {
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:MMGroupShowHelperKey];
}

BOOL MMGroupHelperTop(void) {                    // isHelperTop
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupHelperTopKey];
    return value ? [value boolValue] : YES;
}

void MMGroupSetHelperTop(BOOL top) {
    [[NSUserDefaults standardUserDefaults] setBool:top forKey:MMGroupHelperTopKey];
}

NSInteger MMGroupHelperIndex(void) {             // roomIdx
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupHelperIdxKey];
    return value ? [value integerValue] : 0;
}

void MMGroupSetHelperIndex(NSInteger index) {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(0, index) forKey:MMGroupHelperIdxKey];
}

NSInteger MMGroupHelperIncoType(void) {          // helperIncoType：0=数字 1=红点
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupIncoTypeKey];
    return value ? [value integerValue] : 0;
}

void MMGroupSetHelperIncoType(NSInteger type) {
    [[NSUserDefaults standardUserDefaults] setInteger:type forKey:MMGroupIncoTypeKey];
}

#pragma mark - RoomList（白名单）

/// 当前登录账号（MiYou 的 RoomList 是按账号分别存的：mHideRoomList[自己的username]）
NSString *MMGroupAccountName(void) {
    // MiYou 用 +[SettingUtil getCurUsrName] 取当前账号（实测 GetSessionInfoList trace）
    Class settingUtil = objc_getClass("SettingUtil");
    SEL getCurSel = NSSelectorFromString(@"getCurUsrName");
    if (settingUtil && [settingUtil respondsToSelector:getCurSel]) {
        id name = ((id (*)(id, SEL))objc_msgSend)(settingUtil, getCurSel);
        if ([name isKindOfClass:[NSString class]] && [name length]) return name;
    }
    Class centerClass = objc_getClass("MMServiceCenter");
    Class contactMgrClass = objc_getClass("CContactMgr");
    if (!centerClass || !contactMgrClass) return @"default";
    SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSel = NSSelectorFromString(@"getService:");
    SEL getSelfSel = NSSelectorFromString(@"getSelfContact");
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
    id contactMgr = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, contactMgrClass);
    if (![contactMgr respondsToSelector:getSelfSel]) return @"default";
    id selfContact = ((id (*)(id, SEL))objc_msgSend)(contactMgr, getSelfSel);
    NSString *userName = MMGroupUserNameOfSession(selfContact);
    return userName.length ? userName : @"default";
}

/// 整份 RoomList 表：{ 账号: [username, ...] }
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *MMGroupRoomTable(void) {
    id raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:MMGroupRoomListKey];
    NSMutableDictionary *table = [NSMutableDictionary dictionary];
    if ([raw isKindOfClass:[NSDictionary class]]) {
        for (id key in raw) {
            id value = raw[key];
            if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSArray class]]) {
                table[key] = value;
            }
        }
    }
    return table;
}

static void MMGroupStoreRoomTable(NSDictionary *table) {
    [[NSUserDefaults standardUserDefaults] setObject:(table ?: @{}) forKey:MMGroupRoomListKey];
}

NSArray<NSString *> *MMGroupRoomList(void) {
    id mine = MMGroupRoomTable()[MMGroupAccountName()];
    if ([mine isKindOfClass:[NSArray class]]) return [mine copy];               // 兼容旧格式
    if ([mine isKindOfClass:[NSDictionary class]]) return [(NSDictionary *)mine allKeys];
    return @[];
}

void MMGroupSetRoomList(NSArray<NSString *> *list) {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in list) {
        if ([item isKindOfClass:[NSString class]] && [item length] && ![clean containsObject:item]) {
            [clean addObject:item];
        }
    }
    NSMutableDictionary *table = MMGroupRoomTable();
    // MiYou 的内层是字典（username → 值），这里保持同样的形状
    NSMutableDictionary *inner = [NSMutableDictionary dictionary];
    for (NSString *userName in clean) inner[userName] = @(YES);
    table[MMGroupAccountName()] = inner;
    MMGroupStoreRoomTable(table);
}

BOOL MMGroupIsInRoomList(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return NO;
    return [MMGroupStoredList(MMGroupRoomListKey) containsObject:userName];
}

void MMGroupSetInRoomList(NSString *userName, BOOL inList) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    NSMutableArray<NSString *> *list = MMGroupStoredList(MMGroupRoomListKey);
    BOOL contains = [list containsObject:userName];
    if (inList && !contains) {
        [list addObject:userName];
    } else if (!inList && contains) {
        [list removeObject:userName];
    } else {
        return;
    }
    MMGroupStoreList(list, MMGroupRoomListKey);
    MMGroupLog(@"RoomList %@: %@（共 %lu 个）", inList ? @"加入" : @"移出", userName, (unsigned long)list.count);
}

void MMGroupClearRoomList(void) {
    MMGroupStoreList(@[], MMGroupRoomListKey);
}

#pragma mark - 入口会话

NSString *MMGroupHelperUserName(void) {
    return kMMGroupHelperUserName;
}

NSString *MMGroupHelperTitle(void) {             // roomName
    NSString *title = [[NSUserDefaults standardUserDefaults] stringForKey:MMGroupTitleKey];
    return title.length ? title : @"微信群助手";   // MiYou 的默认标题
}

void MMGroupSetHelperTitle(NSString *title) {
    if (![title isKindOfClass:[NSString class]] || !title.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:title forKey:MMGroupTitleKey];
}

BOOL MMGroupIsHelperSession(NSString *userName) {
    return [userName isKindOfClass:[NSString class]] && [userName isEqualToString:kMMGroupHelperUserName];
}

BOOL MMGroupIsInsideHelper(void) {
    return MMGroupInsideHelper;
}

void MMGroupSetInsideHelper(BOOL inside) {
    MMGroupInsideHelper = inside;
    MMGroupLog(@"inRoomList = %@", inside ? @"YES（显示组内）" : @"NO（显示全部）");
}

unsigned int MMGroupRoomReadCount(void) {
    unsigned int total = 0;
    for (id session in MMGroupGroupedSessionsFromList(MMGroupAllSessions())) {
        total += MMGroupUnreadOfSession(session);
    }
    return total;
}

id MMGroupCreateHelperSession(void) {
    // 实测复刻 +[GroupTool createSessionWithUserName:nickName:showRedDot:readAsRedDot:]（IMP 0x42ac7c）：
    //   CContact  *contact = [[CContact alloc] init];
    //   contact.m_nsNickName = nickName; contact.m_nsUsrName = userName; contact.m_isShowRedDot = showRedDot;
    //   MMSessionInfo *s = [[MMSessionInfo alloc] init];
    //   s.m_contact = contact; s.m_nsUserName = userName; s.m_bShowUnReadAsRedDot = readAsRedDot;
    Class contactClass = objc_getClass("CContact");
    Class infoClass = objc_getClass("MMSessionInfo");
    if (!contactClass || !infoClass) return nil;

    NSArray *grouped = MMGroupGroupedSessionsFromList(MMGroupAllSessions());
    if (grouped.count == 0) return nil;

    unsigned int unread = 0;
    unsigned int latest = 0;
    for (id session in grouped) {
        unread += MMGroupUnreadOfSession(session);
        unsigned int sortTime = MMGroupSortTimeOfSession(session);
        if (sortTime > latest) latest = sortTime;
    }

    void (^setValue)(id, NSString *, id) = ^(id object, NSString *key, id value) {
        @try { [object setValue:value forKey:key]; } @catch (__unused NSException *e) {}
    };
    BOOL showRedDot = (MMGroupHelperIncoType() == 1);   // readAsRedDot

    // 假联系人（入口行的名字靠它的 m_nsNickName 渲染）
    id contact = [[contactClass alloc] init];
    setValue(contact, @"m_nsNickName", MMGroupHelperTitle());
    setValue(contact, @"m_nsUsrName", MMGroupHelperUserName());
    setValue(contact, @"m_isShowRedDot", @(showRedDot));

    // 合成会话
    id info = [[infoClass alloc] init];
    setValue(info, @"m_contact", contact);
    setValue(info, @"m_nsUserName", MMGroupHelperUserName());
    setValue(info, @"m_bShowUnReadAsRedDot", @(showRedDot));
    // 实测（block @0x6231d8）：工厂返回后 MiYou 紧接着做两件事
    //   [entry setM_msgWrap:[<msgMgr> GetLastMsgFromUsr:...]]      ← 挂一条"最后消息"
    //   [entry setM_uUnReadCount:[[GroupTool sharedConfig] roomReadCount]]
    id lastMsgWrap = nil;
    for (id session in grouped) {
        id wrap = MMGroupValue(session, @"m_msgWrap");
        if (wrap) { lastMsgWrap = wrap; break; }
    }
    if (lastMsgWrap) setValue(info, @"m_msgWrap", lastMsgWrap);

    unsigned int now = (unsigned int)[[NSDate date] timeIntervalSince1970];
    setValue(info, @"m_uUnReadCount", @(unread));   // = roomReadCount
    setValue(info, @"sortTime", @(MAX(latest, now)));
    setValue(info, @"m_uTopTime", @(now));
    setValue(info, @"m_uUnTopTime", @(0));
    MMGroupLog(@"入口会话: username=%@ 名称=%@ 组内 %lu 个 未读 %u", MMGroupHelperUserName(),
               MMGroupHelperTitle(), (unsigned long)grouped.count, unread);
    return info;
}

BOOL MMGroupIsBypassingListFilter(void) { return MMGroupBypassListFilter; }
void MMGroupSetBypassingListFilter(BOOL bypassing) { MMGroupBypassListFilter = bypassing; }

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
        if ([MMGroupUserNameOfSession(session) hasSuffix:@"@chatroom"]) [groups addObject:session];
    }
    return [groups copy];
}

/// 组内会话 = 原始列表 ∩ RoomList（保持列表原顺序）
NSArray *MMGroupGroupedSessionsFromList(NSArray *allSessions) {
    NSMutableArray *out = [NSMutableArray array];
    if (![allSessions isKindOfClass:[NSArray class]]) return out;
    NSSet<NSString *> *roomList = [NSSet setWithArray:MMGroupStoredList(MMGroupRoomListKey)];
    if (roomList.count == 0) return out;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id session in allSessions) {
        NSString *userName = MMGroupUserNameOfSession(session);
        if (!userName.length || MMGroupIsHelperSession(userName)) continue;
        if (![roomList containsObject:userName]) continue;
        if ([seen containsObject:userName]) continue;
        [out addObject:session];
        [seen addObject:userName];
    }
    return [out copy];
}

#pragma mark - 会话列表钩子（多候选类名探测）

typedef id (*MMGroupGetListIMP)(id, SEL);

static MMGroupGetListIMP MMGroupOrigGetSessionInfoList = NULL;
static NSString *MMGroupHookedClassName = nil;

// 钩子调用记录（诊断只读这些）
static NSUInteger MMGroupHookCalls = 0;
static NSUInteger MMGroupHookLastRawCount = 0;
static NSUInteger MMGroupHookLastGroupedCount = 0;
static NSString *MMGroupHookLastSample = nil;
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
    MMGroupHookLastGroupedSample = groupedSample.length ? [groupedSample copy] : @"(组内为空)";
    MMGroupHookLastNote = [NSString stringWithFormat:@"%@", [NSDate date]];
}

NSArray<NSString *> *MMGroupSessionMgrCandidates(void) {
    return @[@"MMNewSessionMgr", @"NewSessionMgr", @"MMSessionMgr", @"SessionMgr",
             @"MMSessionManager", @"NewSessionManager", @"MMSessionMgrLogic"];
}

BOOL MMGroupSessionListHookInstalled(void) { return MMGroupOrigGetSessionInfoList != NULL; }
NSString *MMGroupSessionListHookClassName(void) { return MMGroupHookedClassName; }

/// 钩子本体：正常模式 → 摘掉组内会话 + 插入入口行；inRoomList 模式 → 只返回组内会话。
static id MMGroupGetSessionInfoListHook(id self, SEL _cmd) {
    id raw = MMGroupOrigGetSessionInfoList ? MMGroupOrigGetSessionInfoList(self, _cmd) : nil;
    if (MMGroupIsBypassingListFilter()) return raw;
    if (!MMGroupIsEnabled() || ![raw isKindOfClass:[NSArray class]]) return raw;

    BOOL previous = MMGroupBypassListFilter;
    MMGroupBypassListFilter = YES;
    id result = raw;
    @try {
        NSArray *list = (NSArray *)raw;
        NSArray *grouped = MMGroupGroupedSessionsFromList(list);
        MMGroupRecordHookCall(list, grouped);
        if (grouped.count == 0) {
            result = list;
        } else if (MMGroupIsInsideHelper()) {
            result = grouped;                       // 组内视图：只显示组内会话
            MMGroupLog(@"会话列表（组内）：%lu 个", (unsigned long)grouped.count);
        } else {
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
            if (MMGroupShowHelper()) {
                id helper = MMGroupCreateHelperSession();
                if (helper) {
                    NSUInteger index = MMGroupHelperTop() ? 0
                        : (NSUInteger)MAX(0, MIN((NSInteger)filtered.count, MMGroupHelperIndex()));
                    [filtered insertObject:helper atIndex:MIN(index, filtered.count)];
                }
            }
            result = [filtered copy];
        }
    } @catch (NSException *exception) {
        MMGroupLog(@"会话列表钩子异常: %@", exception);
        result = raw;
    }
    MMGroupBypassListFilter = previous;
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
    return NO;
}

#pragma mark - 视图层过滤（微信列表真正读的那一层）

typedef long long (*MMGroupCountIMP)(id, SEL, long long);
typedef id (*MMGroupIndexIMP)(id, SEL, id);

static MMGroupCountIMP MMGroupOrigVCCount = NULL;
static MMGroupIndexIMP MMGroupOrigVCSession = NULL;
static MMGroupIndexIMP MMGroupOrigVCCellData = NULL;
static MMGroupCountIMP MMGroupOrigLogicCount = NULL;
static MMGroupIndexIMP MMGroupOrigLogicSession = NULL;
static MMGroupIndexIMP MMGroupOrigLogicCellData = NULL;

@interface MMGroupDisplayCache : NSObject
@property (nonatomic, copy) NSArray *slots;
@property (nonatomic, assign) NSUInteger sourceCount;
@property (nonatomic, assign) NSTimeInterval builtAt;
@property (nonatomic, assign) BOOL insideMode;
@property (nonatomic, strong) id helperSession;
@property (nonatomic, strong) id helperCellData;
@end

@implementation MMGroupDisplayCache
@end

static NSMapTable *MMGroupDisplayCaches = nil;

// instrumentation
static NSUInteger MMGroupCountVC = 0, MMGroupSessionVC = 0, MMGroupCellDataVC = 0;
static NSUInteger MMGroupCountLogic = 0, MMGroupSessionLogic = 0, MMGroupCellDataLogic = 0;
static NSUInteger MMGroupCellDataMgrCalls = 0;
static NSString *MMGroupSectionsSeen = nil;
static NSString *MMGroupTargetSectionText = nil;
static NSString *MMGroupCellDataMgrSample = nil;
static NSString *MMGroupCellDataProbeText = nil;
static long long MMGroupTargetSection = -1;
static NSMutableDictionary<NSNumber *, NSNumber *> *MMGroupSectionCounts = nil;

static SEL MMGroupVCCountSel(void) { return NSSelectorFromString(@"logicGetCountForSection:"); }
static SEL MMGroupVCSessionSel(void) { return NSSelectorFromString(@"logicGetSessionAtIndexPath:"); }
static SEL MMGroupVCCellDataSel(void) { return NSSelectorFromString(@"logicGetCellDataAtIndexPath:"); }
static SEL MMGroupLogicCountSel(void) { return NSSelectorFromString(@"getSessionCountForSection:"); }
static SEL MMGroupLogicSessionSel(void) { return NSSelectorFromString(@"getSessionInfoAtIndexPath:"); }
static SEL MMGroupLogicCellDataSel(void) { return NSSelectorFromString(@"getCellDataAtIndexPath:"); }

static void MMGroupNoteSection(long long section, long long count) {
    @try {
        if (!MMGroupSectionCounts) MMGroupSectionCounts = [NSMutableDictionary dictionary];
        MMGroupSectionCounts[@(section)] = @(count);
        NSMutableString *text = [NSMutableString string];
        for (NSNumber *key in [MMGroupSectionCounts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (text.length) [text appendString:@", "];
            [text appendFormat:@"%@=%@", key, MMGroupSectionCounts[key]];
        }
        MMGroupSectionsSeen = [text copy];
        if (count >= 3 && count > MMGroupTargetSection) {
            MMGroupTargetSection = section;
            MMGroupTargetSectionText = [NSString stringWithFormat:@"section %lld（原始 %lld 行）", section, count];
        }
    } @catch (__unused NSException *e) {}
}

/// 入口行 cellData：克隆某个真实行的 cellData，并把能改的字段改成群助手的
static void MMGroupPatchHelperCellData(id cellData, unsigned int unread) {
    if (!cellData) return;
    NSMutableString *probe = [NSMutableString string];
    [probe appendFormat:@"类=%@\n", NSStringFromClass([cellData class])];
    @try {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([cellData class], &count);
        if (ivars) {
            [probe appendString:@"  ivars: "];
            for (unsigned int i = 0; i < count && i < 40; i++) {
                [probe appendFormat:@"%s ", ivar_getName(ivars[i])];
            }
            [probe appendString:@"\n"];
            free(ivars);
        }
        unsigned int pcount = 0;
        objc_property_t *props = class_copyPropertyList([cellData class], &pcount);
        if (props) {
            [probe appendString:@"  props: "];
            for (unsigned int i = 0; i < pcount && i < 40; i++) {
                [probe appendFormat:@"%s ", property_getName(props[i])];
            }
            [probe appendString:@"\n"];
            free(props);
        }
    } @catch (__unused NSException *e) {}
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
    setValue(@"m_bShowUnReadAsRedDot", @(MMGroupHelperIncoType() == 1));
}

static NSMapTable *MMGroupCaches(void) {
    if (!MMGroupDisplayCaches) MMGroupDisplayCaches = [NSMapTable weakToStrongObjectsMapTable];
    return MMGroupDisplayCaches;
}

static MMGroupDisplayCache *MMGroupBuildCache(id host, BOOL logicLayer) {
    MMGroupCountIMP origCount = logicLayer ? MMGroupOrigLogicCount : MMGroupOrigVCCount;
    MMGroupIndexIMP origSession = logicLayer ? MMGroupOrigLogicSession : MMGroupOrigVCSession;
    MMGroupIndexIMP origCellData = logicLayer ? MMGroupOrigLogicCellData : MMGroupOrigVCCellData;
    SEL countSel = logicLayer ? MMGroupLogicCountSel() : MMGroupVCCountSel();
    SEL sessionSel = logicLayer ? MMGroupLogicSessionSel() : MMGroupVCSessionSel();
    SEL cellDataSel = logicLayer ? MMGroupLogicCellDataSel() : MMGroupVCCellDataSel();

    MMGroupDisplayCache *cache = [[MMGroupDisplayCache alloc] init];
    cache.insideMode = MMGroupIsInsideHelper();
    if (!origCount || !origSession) return cache;

    long long section = MMGroupTargetSection < 0 ? 0 : MMGroupTargetSection;
    long long n = origCount(host, countSel, section);
    cache.sourceCount = (NSUInteger)MAX(n, 0);
    if (n <= 0) return cache;

    NSSet<NSString *> *roomList = [NSSet setWithArray:MMGroupRoomList()];
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:(NSUInteger)n + 1];
    NSMutableArray *keptRows = [NSMutableArray array];
    NSMutableArray *groupedRows = [NSMutableArray array];
    NSMutableArray *groupedSessions = [NSMutableArray array];
    NSIndexPath *firstGroupedIndexPath = nil;
    BOOL helperAlreadyListed = NO;

    for (long long i = 0; i < n; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:section];
        id session = origSession(host, sessionSel, indexPath);
        NSString *userName = MMGroupUserNameOfSession(session);
        if (MMGroupIsHelperSession(userName)) {
            helperAlreadyListed = YES;
            [keptRows addObject:@(i)];
            continue;
        }
        BOOL isMember = userName.length && [roomList containsObject:userName];
        if (!MMGroupIsEnabled() || !isMember) {
            [keptRows addObject:@(i)];
            continue;
        }
        [groupedRows addObject:@(i)];
        [groupedSessions addObject:session];
        if (!firstGroupedIndexPath) firstGroupedIndexPath = indexPath;
    }

    unsigned int unread = 0;
    for (id session in groupedSessions) unread += MMGroupUnreadOfSession(session);

    if (cache.insideMode) {
        // 组内视图：只显示组内会话，不显示入口行
        [slots addObjectsFromArray:groupedRows];
    } else {
        if (groupedRows.count && !helperAlreadyListed && MMGroupShowHelper()) {
            NSUInteger index = MMGroupHelperTop() ? 0
                : (NSUInteger)MAX(0, MIN((NSInteger)keptRows.count, MMGroupHelperIndex()));
            if (index > keptRows.count) index = keptRows.count;
            [slots addObjectsFromArray:[keptRows subarrayWithRange:NSMakeRange(0, index)]];
            [slots addObject:kMMGroupHelperSlot];
            [slots addObjectsFromArray:[keptRows subarrayWithRange:NSMakeRange(index, keptRows.count - index)]];
        } else {
            [slots addObjectsFromArray:keptRows];
        }
        if (groupedRows.count && firstGroupedIndexPath && origCellData) {
            id cellData = origCellData(host, cellDataSel, firstGroupedIndexPath);
            if (cellData) {
                MMGroupPatchHelperCellData(cellData, unread);
                cache.helperCellData = cellData;
            }
        }
        cache.helperSession = MMGroupCreateHelperSession();
    }
    cache.slots = [slots copy];
    cache.builtAt = [NSDate timeIntervalSinceReferenceDate];
    MMGroupLog(@"%@映射：section %lld 原始 %lld 行 → 显示 %lu 行（组内 %lu 个，模式 %@）",
               logicLayer ? @"逻辑层" : @"VC 层", section, n, (unsigned long)slots.count,
               (unsigned long)groupedSessions.count, cache.insideMode ? @"组内" : @"全部");
    return cache;
}

static MMGroupDisplayCache *MMGroupCacheFor(id host, BOOL logicLayer) {
    if (!host) return nil;
    NSMapTable *caches = MMGroupCaches();
    MMGroupDisplayCache *cache = [caches objectForKey:host];
    MMGroupCountIMP origCount = logicLayer ? MMGroupOrigLogicCount : MMGroupOrigVCCount;
    if (!origCount) return cache;
    SEL countSel = logicLayer ? MMGroupLogicCountSel() : MMGroupVCCountSel();
    long long n = origCount(host, countSel, MMGroupTargetSection < 0 ? 0 : MMGroupTargetSection);
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL stale = !cache || cache.sourceCount != (NSUInteger)MAX(n, 0) ||
                 cache.insideMode != MMGroupIsInsideHelper() || now - cache.builtAt > 3.0;
    if (stale) {
        if (MMGroupBuildingDisplay) return cache;
        MMGroupBuildingDisplay = YES;
        @try {
            cache = MMGroupBuildCache(host, logicLayer);
            [caches setObject:cache forKey:host];
        } @catch (NSException *exception) {
            MMGroupLog(@"显示映射异常: %@", exception);
        }
        MMGroupBuildingDisplay = NO;
    }
    return cache;
}

static id MMGroupMappedRow(id host, id indexPath, BOOL logicLayer, BOOL wantCellData) {
    if (!MMGroupIsEnabled() || !indexPath) return nil;
    MMGroupIndexIMP orig = logicLayer ? MMGroupOrigLogicSession : MMGroupOrigVCSession;
    MMGroupIndexIMP origCellData = logicLayer ? MMGroupOrigLogicCellData : MMGroupOrigVCCellData;
    MMGroupDisplayCache *cache = MMGroupCacheFor(host, logicLayer);
    NSInteger section = [indexPath section];
    NSInteger row = [indexPath row];
    if (!cache.slots.count || section != MMGroupTargetSection ||
        row < 0 || row >= (NSInteger)cache.slots.count) {
        return nil;
    }
    id slot = cache.slots[(NSUInteger)row];
    if ([slot isKindOfClass:[NSString class]] && [slot isEqualToString:kMMGroupHelperSlot]) {
        return wantCellData ? cache.helperCellData : cache.helperSession;
    }
    NSIndexPath *mapped = [NSIndexPath indexPathForRow:[slot integerValue] inSection:section];
    if (wantCellData) {
        return origCellData ? origCellData(host, logicLayer ? MMGroupLogicCellDataSel() : MMGroupVCCellDataSel(), mapped) : nil;
    }
    return orig ? orig(host, logicLayer ? MMGroupLogicSessionSel() : MMGroupVCSessionSel(), mapped) : nil;
}

static long long MMGroupCountHookCommon(id self, SEL _cmd, long long section, BOOL logicLayer) {
    MMGroupCountIMP orig = logicLayer ? MMGroupOrigLogicCount : MMGroupOrigVCCount;
    long long n = orig ? orig(self, _cmd, section) : 0;
    MMGroupNoteSection(section, n);
    if (section != MMGroupTargetSection || !MMGroupIsEnabled()) return n;
    MMGroupDisplayCache *cache = MMGroupCacheFor(self, logicLayer);
    return cache.slots.count ? (long long)cache.slots.count : n;
}

static long long MMGroupVCCountHook(id self, SEL _cmd, long long section) {
    MMGroupCountVC++;
    return MMGroupCountHookCommon(self, _cmd, section, NO);
}
static id MMGroupVCSessionHook(id self, SEL _cmd, id indexPath) {
    MMGroupSessionVC++;
    id mapped = MMGroupMappedRow(self, indexPath, NO, NO);
    return mapped ?: (MMGroupOrigVCSession ? MMGroupOrigVCSession(self, _cmd, indexPath) : nil);
}
static id MMGroupVCCellDataHook(id self, SEL _cmd, id indexPath) {
    MMGroupCellDataVC++;
    id mapped = MMGroupMappedRow(self, indexPath, NO, YES);
    return mapped ?: (MMGroupOrigVCCellData ? MMGroupOrigVCCellData(self, _cmd, indexPath) : nil);
}
static long long MMGroupLogicCountHook(id self, SEL _cmd, long long section) {
    MMGroupCountLogic++;
    return MMGroupCountHookCommon(self, _cmd, section, YES);
}
static id MMGroupLogicSessionHook(id self, SEL _cmd, id indexPath) {
    MMGroupSessionLogic++;
    id mapped = MMGroupMappedRow(self, indexPath, YES, NO);
    return mapped ?: (MMGroupOrigLogicSession ? MMGroupOrigLogicSession(self, _cmd, indexPath) : nil);
}
static id MMGroupLogicCellDataHook(id self, SEL _cmd, id indexPath) {
    MMGroupCellDataLogic++;
    id mapped = MMGroupMappedRow(self, indexPath, YES, YES);
    return mapped ?: (MMGroupOrigLogicCellData ? MMGroupOrigLogicCellData(self, _cmd, indexPath) : nil);
}

BOOL MMGroupViewHooksInstalled(void) {
    return (MMGroupOrigVCCount != NULL && MMGroupOrigVCSession != NULL) ||
           (MMGroupOrigLogicCount != NULL && MMGroupOrigLogicSession != NULL);
}

static void MMGroupSwizzle(Class cls, SEL sel, IMP replacement, void **originalSlot) {
    if (!cls || !sel) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    if (originalSlot && *originalSlot == NULL) *originalSlot = (void *)method_getImplementation(method);
    method_setImplementation(method, replacement);
}

BOOL MMGroupInstallViewHooks(void) {
    Class vcClass = objc_getClass("NewMainFrameViewController");
    if (vcClass) {
        MMGroupSwizzle(vcClass, MMGroupVCCountSel(), (IMP)MMGroupVCCountHook, (void **)&MMGroupOrigVCCount);
        MMGroupSwizzle(vcClass, MMGroupVCSessionSel(), (IMP)MMGroupVCSessionHook, (void **)&MMGroupOrigVCSession);
        MMGroupSwizzle(vcClass, MMGroupVCCellDataSel(), (IMP)MMGroupVCCellDataHook, (void **)&MMGroupOrigVCCellData);
    }
    Class logicClass = objc_getClass("MainFrameLogicController");
    if (logicClass) {
        MMGroupSwizzle(logicClass, MMGroupLogicCountSel(), (IMP)MMGroupLogicCountHook, (void **)&MMGroupOrigLogicCount);
        MMGroupSwizzle(logicClass, MMGroupLogicSessionSel(), (IMP)MMGroupLogicSessionHook, (void **)&MMGroupOrigLogicSession);
        MMGroupSwizzle(logicClass, MMGroupLogicCellDataSel(), (IMP)MMGroupLogicCellDataHook, (void **)&MMGroupOrigLogicCellData);
    }
    MMGroupLog(@"视图层钩子：VC %@ / 逻辑层 %@",
               MMGroupOrigVCCount ? @"✓" : @"✗", MMGroupOrigLogicCount ? @"✓" : @"✗");
    return MMGroupViewHooksInstalled();
}

void MMGroupForceReloadSessions(void) {
    @try {
        UIViewController *mainFrame = MMGroupMainFrameController();
        if (mainFrame) {
            id tableView = MMGroupValue(mainFrame, @"tableView");
            if ([tableView isKindOfClass:[UITableView class]]) [(UITableView *)tableView reloadData];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"MMSessionInfoChanged" object:nil];
    } @catch (NSException *exception) {
        MMGroupLog(@"刷新会话列表异常: %@", exception);
    }
}

#pragma mark - 诊断

void MMGroupNoteCellDataManagerCall(NSString *userName, id cellData) {
    MMGroupCellDataMgrCalls++;
    @try {
        MMGroupCellDataMgrSample = [NSString stringWithFormat:@"userName=%@ 返回=%@",
                                    userName ?: @"(nil)", cellData ? NSStringFromClass([cellData class]) : @"nil"];
    } @catch (__unused NSException *e) {}
}

NSString *MMGroupCellDataProbe(void) {
    return MMGroupCellDataProbeText ?: @"(还没有取过入口行 cellData)";
}

NSString *MMGroupViewLayerReport(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"VC 层 logicGet* 调用: count %lu / session %lu / cellData %lu\n",
     (unsigned long)MMGroupCountVC, (unsigned long)MMGroupSessionVC, (unsigned long)MMGroupCellDataVC];
    [out appendFormat:@"逻辑层 get* 调用: count %lu / session %lu / cellData %lu\n",
     (unsigned long)MMGroupCountLogic, (unsigned long)MMGroupSessionLogic, (unsigned long)MMGroupCellDataLogic];
    [out appendFormat:@"CellDataManager 调用: %lu%@\n", (unsigned long)MMGroupCellDataMgrCalls,
     MMGroupCellDataMgrSample.length ? [@"  最近: " stringByAppendingString:MMGroupCellDataMgrSample] : @""];
    [out appendFormat:@"见过的 section/行数: %@\n", MMGroupSectionsSeen.length ? MMGroupSectionsSeen : @"(未调用)"];
    [out appendFormat:@"判定为会话列表: %@\n", MMGroupTargetSectionText ?: @"(未判定)"];
    [out appendFormat:@"inRoomList: %@   RoomList: %lu 个\n",
     MMGroupIsInsideHelper() ? @"YES（组内视图）" : @"NO", (unsigned long)MMGroupRoomList().count];
    MMGroupDisplayCache *cache = MMGroupDisplayCaches ? [MMGroupDisplayCaches objectForKey:MMGroupMainFrameController()] : nil;
    if (cache.slots.count) {
        [out appendFormat:@"显示映射: 原始 %lu 行 → 显示 %lu 行（%@）\n",
         (unsigned long)cache.sourceCount, (unsigned long)cache.slots.count,
         cache.insideMode ? @"组内" : @"全部"];
    } else {
        [out appendString:@"显示映射: 未生成\n"];
    }
    [out appendFormat:@"入口行 cellData 探测:\n%@", MMGroupCellDataProbe()];
    return [out copy];
}

static NSString *MMGroupSelectorDump(NSString *className) {
    NSMutableString *out = [NSMutableString string];
    @try {
        Class cls = objc_getClass(className.UTF8String);
        if (!cls) return [NSString stringWithFormat:@"%@: 类不存在\n", className];
        NSArray<NSString *> *keywords = @[@"session", @"Session", @"resort", @"normal", @"rebuild", @"fold"];
        NSMutableSet<NSString *> *names = [NSMutableSet set];
        Class walk = cls;
        int guard = 0;
        while (walk && walk != [NSObject class] && guard++ < 6) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(walk, &count);
            if (methods) {
                for (unsigned int i = 0; i < count; i++) {
                    NSString *name = NSStringFromSelector(method_getName(methods[i]));
                    for (NSString *keyword in keywords) {
                        if ([name containsString:keyword]) { [names addObject:name]; break; }
                    }
                }
                free(methods);
            }
            walk = class_getSuperclass(walk);
        }
        NSArray<NSString *> *sorted = [[names allObjects] sortedArrayUsingSelector:@selector(compare:)];
        [out appendFormat:@"%@: %lu 个\n", className, (unsigned long)sorted.count];
        NSUInteger shown = MIN((NSUInteger)40, sorted.count);
        for (NSUInteger i = 0; i < shown; i++) [out appendFormat:@"   %@\n", sorted[i]];
    } @catch (NSException *exception) {
        [out appendFormat:@"%@: 枚举异常 %@\n", className, exception];
    }
    return [out copy];
}

NSString *MMGroupDiagnostics(void) {
    NSMutableString *out = [NSMutableString string];
    @try {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        [out appendString:@"WCZZ 群助手诊断（MiYou 语义）\n"];
        [out appendFormat:@"微信版本: %@ (%@)\n", info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
#ifdef PACKAGE_VERSION
        [out appendFormat:@"插件版本: %@\n", PACKAGE_VERSION];
#endif
        [out appendString:@"\n-- GroupTool 状态 --\n"];
        [out appendFormat:@"isOpenRoomEnable: %@\n", MMGroupIsEnabled() ? @"YES" : @"NO"];
        [out appendFormat:@"isOpenRoomHelper: %@\n", MMGroupShowHelper() ? @"YES" : @"NO"];
        [out appendFormat:@"isHelperTop: %@  roomIdx: %ld  helperIncoType: %ld\n",
         MMGroupHelperTop() ? @"YES" : @"NO", (long)MMGroupHelperIndex(), (long)MMGroupHelperIncoType()];
        [out appendFormat:@"roomName: %@\n", MMGroupHelperTitle()];
        [out appendFormat:@"RoomList: %lu 个\n", (unsigned long)MMGroupRoomList().count];
        [out appendFormat:@"roomReadCount: %u\n", MMGroupRoomReadCount()];

        [out appendString:@"\n-- 会话列表钩子 --\n"];
        for (NSString *name in MMGroupSessionMgrCandidates()) {
            Class cls = objc_getClass(name.UTF8String);
            if (!cls) { [out appendFormat:@"%@: 无\n", name]; continue; }
            BOOL has = class_getInstanceMethod(cls, NSSelectorFromString(@"GetSessionInfoList")) != NULL;
            [out appendFormat:@"%@: 存在%@\n", name, has ? @" / 有 GetSessionInfoList" : @""];
        }
        [out appendFormat:@"钩子: %@%@\n", MMGroupSessionListHookInstalled() ? @"已安装" : @"未安装",
         MMGroupSessionListHookInstalled() ? [NSString stringWithFormat:@" (%@)", MMGroupSessionListHookClassName() ?: @"?"] : @""];
        if (MMGroupHookCalls == 0) {
            [out appendString:@"GetSessionInfoList 未被调用过\n"];
        } else {
            [out appendFormat:@"调用次数: %lu，最近: 原始 %lu 个 / 组内 %lu 个（%@）\n",
             (unsigned long)MMGroupHookCalls, (unsigned long)MMGroupHookLastRawCount,
             (unsigned long)MMGroupHookLastGroupedCount, MMGroupHookLastNote ?: @"?"];
            [out appendFormat:@"原始样本:\n%@", MMGroupHookLastSample ?: @"(无)\n"];
            [out appendFormat:@"组内样本:\n%@", MMGroupHookLastGroupedSample ?: @"(无)\n"];
        }

        [out appendString:@"\n-- 视图层 --\n"];
        [out appendFormat:@"钩子: %@\n", MMGroupViewHooksInstalled() ? @"已安装" : @"未安装"];
        [out appendString:MMGroupViewLayerReport()];
        [out appendString:@"\n"];

        Class mainFrame = objc_getClass("NewMainFrameViewController");
        if (mainFrame) {
            [out appendFormat:@"logicGetSessionAtIndexPath: %@  onLogicOpenSession: %@\n",
             [mainFrame instancesRespondToSelector:NSSelectorFromString(@"logicGetSessionAtIndexPath:")] ? @"有" : @"无",
             [mainFrame instancesRespondToSelector:NSSelectorFromString(@"onLogicOpenSession:")] ? @"有" : @"无"];
        }

        [out appendString:@"\n-- 真实方法名 --\n"];
        [out appendString:MMGroupSelectorDump(@"MainFrameLogicController")];
        [out appendString:MMGroupSelectorDump(@"MMNewSessionMgr")];

        [out appendFormat:@"\n时间: %@", [NSDate date]];
    } @catch (NSException *exception) {
        [out appendFormat:@"\n诊断采集异常: %@\n", exception];
    }
    return [out copy];
}

#pragma mark - 自检 / 显示

NSString *MMGroupRuntimeStatus(void) {
    if (!MMGroupSessionListHookInstalled() && !MMGroupInstallSessionListHook()) {
        return @"不可用：找不到会话管理器类";
    }
    if (!objc_getClass("MMSessionInfo")) return @"不可用：缺少 MMSessionInfo";
    Class mainFrame = objc_getClass("NewMainFrameViewController");
    if (!mainFrame) return @"不可用：缺少会话列表类";
    if (!MMGroupViewHooksInstalled()) return @"部分可用：视图层钩子未装";
    if (!objc_getClass("ChatRoomInfoViewController")) return @"部分可用：群聊信息页开关缺失";
    NSInteger count = (NSInteger)MMGroupRoomList().count;
    return count ? [NSString stringWithFormat:@"可用（组内 %ld 个）", (long)count]
                 : @"可用（组内还是空的，去群聊信息页把群加进来）";
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
