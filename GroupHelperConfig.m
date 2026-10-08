//
//  GroupHelperConfig.m
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"

#import <objc/runtime.h>
#import <objc/message.h>

NSString * const MMGroupEnabledKey = @"wczz.group.enabled";
NSString * const MMGroupListKey    = @"wczz.group.list";
NSString * const MMGroupFoldedKey  = @"wczz.group.foldedByUs";

/// 落地过程中会被微信回调（rebuildAndUpdateSessionInfo → GetSessionInfoList），
/// 用它挡住递归。
static BOOL MMGroupApplying = NO;

#pragma mark - helpers

static id MMGroupValue(id object, NSString *key) {
    if (!object || !key) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static MMNewSessionMgr *MMGroupSessionMgr(void) {
    Class centerClass = objc_getClass("MMServiceCenter");
    Class mgrClass = objc_getClass("MMNewSessionMgr");
    if (!centerClass || !mgrClass) return nil;
    SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSel = NSSelectorFromString(@"getService:");
    if (![centerClass respondsToSelector:defaultCenterSel]) return nil;
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
    if (!center || ![center respondsToSelector:getServiceSel]) return nil;
    id mgr = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, mgrClass);
    return [mgr isKindOfClass:[MMNewSessionMgr class]] ? mgr : (MMNewSessionMgr *)mgr;
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

#pragma mark - switches

BOOL MMGroupIsEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:MMGroupEnabledKey];
    return value ? [value boolValue] : NO;   // 默认关闭
}

void MMGroupSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:MMGroupEnabledKey];
}

#pragma mark - membership (pure state)

NSArray<NSString *> *MMGroupUserNameList(void) {
    return [MMGroupStoredList(MMGroupListKey) copy];
}

void MMGroupSetUserNameList(NSArray<NSString *> *list) {
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in list) {
        if ([item isKindOfClass:[NSString class]] && [item length] && ![clean containsObject:item]) {
            [clean addObject:item];
        }
    }
    MMGroupStoreList(clean, MMGroupListKey);
}

BOOL MMGroupContainsUserName(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return NO;
    return [MMGroupStoredList(MMGroupListKey) containsObject:userName];
}

void MMGroupAddUserName(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    NSMutableArray<NSString *> *list = MMGroupStoredList(MMGroupListKey);
    if ([list containsObject:userName]) return;
    [list addObject:userName];
    MMGroupStoreList(list, MMGroupListKey);
}

void MMGroupRemoveUserName(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    NSMutableArray<NSString *> *list = MMGroupStoredList(MMGroupListKey);
    if (![list containsObject:userName]) return;
    [list removeObject:userName];
    MMGroupStoreList(list, MMGroupListKey);
}

void MMGroupClearUserNames(void) {
    MMGroupStoreList(@[], MMGroupListKey);
}

#pragma mark - session pipeline

NSArray *MMGroupAllSessions(void) {
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    SEL sel = NSSelectorFromString(@"GetSessionInfoList");
    if (!mgr || ![mgr respondsToSelector:sel]) return @[];
    id list = ((id (*)(id, SEL))objc_msgSend)(mgr, sel);
    return [list isKindOfClass:[NSArray class]] ? list : @[];
}

void MMGroupSyncFromNativeFold(NSArray *sessions) {
    if (MMGroupApplying) return;
    if (![sessions isKindOfClass:[NSArray class]] || sessions.count == 0) return;
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    SEL shouldFoldSel = NSSelectorFromString(@"shouldFoldSession:");
    if (!mgr || ![mgr respondsToSelector:shouldFoldSel]) return;

    NSMutableArray<NSString *> *list = MMGroupStoredList(MMGroupListKey);
    BOOL changed = NO;
    for (id session in sessions) {
        NSString *userName = MMGroupValue(session, @"m_nsUserName");
        if (![userName isKindOfClass:[NSString class]] || !userName.length) continue;
        if ([list containsObject:userName]) continue;
        BOOL folded = ((BOOL (*)(id, SEL, id))objc_msgSend)(mgr, shouldFoldSel, session);
        if (folded) {
            [list addObject:userName];
            changed = YES;
        }
    }
    if (changed) MMGroupStoreList(list, MMGroupListKey);
}

void MMGroupApplyFold(void) {
    if (MMGroupApplying) return;
    MMNewSessionMgr *mgr = MMGroupSessionMgr();
    if (!mgr) return;

    SEL foldSel = NSSelectorFromString(@"foldSessionByNames:");
    SEL unfoldSel = NSSelectorFromString(@"unfoldSessionByName:");
    if (![mgr respondsToSelector:foldSel] || ![mgr respondsToSelector:unfoldSel]) return;

    MMGroupApplying = YES;

    BOOL enabled = MMGroupIsEnabled();
    NSMutableArray<NSString *> *wanted = enabled ? MMGroupStoredList(MMGroupListKey) : [NSMutableArray array];
    NSMutableArray<NSString *> *foldedByUs = MMGroupStoredList(MMGroupFoldedKey);

    // 1) 名单里新增的 → 折起来
    NSMutableArray<NSString *> *toFold = [NSMutableArray array];
    for (NSString *userName in wanted) {
        if (![foldedByUs containsObject:userName]) [toFold addObject:userName];
    }
    if (toFold.count) {
        ((void (*)(id, SEL, id))objc_msgSend)(mgr, foldSel, toFold);
        [foldedByUs addObjectsFromArray:toFold];
    }

    // 2) 已从名单移除的 → 只展开我们自己折过的
    for (NSString *userName in [foldedByUs copy]) {
        if ([wanted containsObject:userName]) continue;
        ((void (*)(id, SEL, id))objc_msgSend)(mgr, unfoldSel, userName);
        [foldedByUs removeObject:userName];
    }

    MMGroupStoreList(foldedByUs, MMGroupFoldedKey);

    SEL rebuildSel = NSSelectorFromString(@"rebuildAndUpdateSessionInfo");
    if ([mgr respondsToSelector:rebuildSel]) {
        ((void (*)(id, SEL))objc_msgSend)(mgr, rebuildSel);
    }

    MMGroupApplying = NO;
}

#pragma mark - display

id MMGroupValueSafe(id object, NSString *key) {
    return MMGroupValue(object, key);
}

NSString *MMGroupDisplayName(NSString *userName, NSString *fallback) {
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
