//
//  HBGroupService.m
//  微信私有接口桥实现
//

#import "HBGroupService.h"
#import "HBGroupEngine.h"
#import <objc/runtime.h>

static const void *kHBGroupPickerCompletionKey = &kHBGroupPickerCompletionKey;

/// 按候选类名列表找第一个存在的类
static Class HBFindClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;
    }
    return Nil;
}

/// 向对象发消息，选择器不存在或抛异常时返回 nil
static id HBSend(id target, NSString *selector, NSArray *args) {
    if (!target || !selector.length) return nil;
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    @try {
        NSMethodSignature *signature = [target methodSignatureForSelector:sel];
        if (!signature) return nil;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = sel;
        for (NSUInteger i = 0; i < args.count; i++) {
            id value = args[i];
            NSUInteger index = i + 2;
            if (index >= signature.numberOfArguments) break;
            const char *type = [signature getArgumentTypeAtIndex:index];
            if (type[0] == '@') {
                id obj = value;
                [invocation setArgument:&obj atIndex:index];
            } else if (type[0] == 'B' || type[0] == 'c') {
                BOOL flag = [value boolValue];
                [invocation setArgument:&flag atIndex:index];
            } else if (type[0] == 'q' || type[0] == 'Q' || type[0] == 'i' || type[0] == 'I') {
                long long number = [value longLongValue];
                [invocation setArgument:&number atIndex:index];
            } else if (type[0] == 'd') {
                double number = [value doubleValue];
                [invocation setArgument:&number atIndex:index];
            }
        }
        [invocation invoke];
        if (signature.methodReturnLength == 0) return nil;
        const char *returnType = signature.methodReturnType;
        if (returnType && returnType[0] == '@') {
            void *buffer = NULL;
            [invocation getReturnValue:&buffer];
            return (__bridge id)buffer;
        }
        return nil;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void HBCall(id target, NSString *selector, NSArray *args) {
    HBSend(target, selector, args);
}

@interface HBGroupService ()
- (id)serviceCenter;
- (id)serviceForClassNames:(NSArray<NSString *> *)names;
- (id)sessionManager;
- (id)sessionLogic;
- (id)sessionForUserName:(NSString *)userName;
- (id)homeController;
- (UIWindow *)keyWindow;
@end

@implementation HBGroupService

+ (instancetype)shared {
    static HBGroupService *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HBGroupService alloc] init];
    });
    return instance;
}

#pragma mark - 基础对象

- (id)serviceCenter {
    id serviceCenter = HBSend(HBFindClass(@[@"MMServiceCenter"]), @"defaultCenter", @[]);
    if (!serviceCenter) {
        serviceCenter = HBSend(NSClassFromString(@"MMServiceCenter"), @"defaultCenter", @[]);
    }
    return serviceCenter;
}

- (id)serviceForClassNames:(NSArray<NSString *> *)names {
    Class cls = HBFindClass(names);
    if (!cls) return nil;
    id center = [self serviceCenter];
    if (!center) return nil;
    return HBSend(center, @"getService:", @[cls]);
}

- (id)sessionManager {
    id manager = [self serviceForClassNames:@[@"MainSessionMgr", @"MMNewSessionMgr", @"LMainSessionMgr"]];
    if (manager) return manager;
    return HBSend(HBFindClass(@[@"MMNewSessionMgr"]), @"sharedInstance", @[]);
}

- (id)sessionLogic {
    return [self serviceForClassNames:@[@"MainFrameLogicController"]];
}

#pragma mark - 账号 / 会话

- (NSString *)currentAccount {
    id setting = [self serviceForClassNames:@[@"CSetting", @"MMSetting"]];
    NSString *account = HBSend(setting, @"m_nsUserName", @[]);
    if ([account isKindOfClass:[NSString class]] && account.length) return account;

    id accountService = HBFindClass(@[@"MMAccountMgr", @"CAccountMgr"]);
    account = HBSend(accountService, @"getUserName", @[]);
    if ([account isKindOfClass:[NSString class]] && account.length) return account;
    return nil;
}

- (NSArray *)allSessions {
    id manager = [self sessionManager];
    NSArray *sessions = HBSend(manager, @"getLastFrontSessionArray", @[]);
    if ([sessions isKindOfClass:[NSArray class]] && sessions.count) return sessions;

    sessions = HBSend(manager, @"allSessions", @[]);
    if ([sessions isKindOfClass:[NSArray class]]) return sessions;

    NSMutableArray *merged = [NSMutableArray array];
    for (NSString *selector in @[@"allTopSessions", @"topSessions", @"normalSessions"]) {
        NSArray *part = HBSend(manager, selector, @[]);
        if ([part isKindOfClass:[NSArray class]]) [merged addObjectsFromArray:part];
    }
    return merged;
}

- (void)rebuildMainSessions {
    id manager = [self sessionManager];
    if (!manager) return;
    HBCall(manager, @"rebuildMainSessions", @[]);
}

- (void)recountUnread {
    id manager = [self sessionManager];
    if (!manager) return;
    HBCall(manager, @"recountUnReadCount", @[]);
    HBCall(manager, @"setVisibleUnreadSlienceChatSessionCount:", @[@(0)]);
}

#pragma mark - 会话操作

- (id)sessionForUserName:(NSString *)userName {
    if (!userName.length) return nil;
    id manager = [self sessionManager];
    id session = HBSend(manager, @"GetSessionByUserName:", @[userName]);
    if (session) return session;
    for (id item in [self allSessions]) {
        if ([[HBGroupEngine userNameOfSession:item] isEqualToString:userName]) return item;
    }
    return nil;
}

- (BOOL)markRead:(NSString *)userName {
    id manager = [self sessionManager];
    if (!manager || !userName.length) return NO;

    if (HBSend(manager, @"MarkChatRead:", @[userName])) return YES;

    HBCall(manager, @"ChangeSessionUnReadCount:to:", @[userName, @(0)]);
    HBCall(manager, @"ClearUnRead:FromID:ToID:", @[userName, @(0), @(0)]);
    HBCall(manager, @"removeMsgRedTips:type:", @[userName, @(0)]);

    id session = [self sessionForUserName:userName];
    if (session) {
        @try {
            [session setValue:@(0) forKey:@"m_uUnReadCount"];
            [session setValue:@(0) forKey:@"m_uAtAllCount"];
            [session setValue:@(NO) forKey:@"m_bShowUnReadAsRedDot"];
        } @catch (__unused NSException *e) { }
    }
    return YES;
}

- (BOOL)deleteSession:(NSString *)userName {
    id manager = [self sessionManager];
    if (!manager || !userName.length) return NO;
    HBCall(manager, @"deleteSession:", @[userName]);
    return YES;
}

- (BOOL)hideSession:(NSString *)userName {
    return [self setHideSession:userName hidden:YES];
}

- (BOOL)setHideSession:(NSString *)userName hidden:(BOOL)hidden {
    id manager = [self sessionManager];
    if (!manager || !userName.length) return NO;
    HBCall(manager, @"setHideSession:", @[userName, @(hidden)]);
    HBCall(manager, @"hideSession:", @[userName, @(hidden)]);

    id session = [self sessionForUserName:userName];
    if (session) {
        @try { [session setValue:@(hidden) forKey:@"m_bHide"]; } @catch (__unused NSException *e) { }
    }
    return YES;
}

- (BOOL)changeUnreadCount:(NSString *)userName to:(NSUInteger)count {
    id manager = [self sessionManager];
    if (!manager || !userName.length) return NO;
    HBCall(manager, @"ChangeSessionUnReadCount:to:", @[userName, @(count)]);
    return YES;
}

#pragma mark - 跳转

- (void)openSession:(id)session fromController:(UIViewController *)controller {
    if (!session) return;
    id contact = nil;
    @try { contact = [session valueForKey:@"m_contact"]; } @catch (__unused NSException *e) { }

    id manager = [self sessionManager];
    if (!manager) return;

    HBCall(manager, @"SyncFulFillSession:", @[session]);

    UINavigationController *nav = controller.navigationController;
    if (!nav) return;

    NSArray *arguments = contact ? @[contact, nav, @(YES)] : @[];
    if (arguments.count) {
        HBCall(manager, @"PushOtherBaseMsgControllerByContact:navigationController:animated:", arguments);
    }
}

- (void)presentSessionPickerForChatMode:(BOOL)chatMode
                                   from:(UIViewController *)controller
                             completion:(void (^)(NSArray<NSString *> *))completion {

    Class pickerClass = HBFindClass(@[@"SessionSelectController", @"MMSessionSelectController"]);
    if (!pickerClass) {
        if (completion) completion(@[]);
        return;
    }

    id picker = [[pickerClass alloc] init];
    if (!picker) {
        if (completion) completion(@[]);
        return;
    }

    // 微信选择器私有配置项，取不到就跳过
    @try { [picker setValue:@(YES) forKey:@"m_bKeepCurViewAfterSelect"]; } @catch (__unused NSException *e) { }
    @try { [picker setValue:@(YES) forKey:@"m_bShowMultiSelectRightBtn"]; } @catch (__unused NSException *e) { }
    @try { [picker setValue:@(YES) forKey:@"m_bIgnoreChatRoom"]; } @catch (__unused NSException *e) { }
    @try { [picker setValue:@(chatMode) forKey:@"m_onlyChatRoom"]; } @catch (__unused NSException *e) { }
    @try { [picker setValue:@(1000) forKey:@"maxSelectionCount"]; } @catch (__unused NSException *e) { }

    // 微信选择器用代理回调；拿不到代理协议时退化成直接返回空
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [controller presentViewController:nav animated:YES completion:nil];

    // 选择结果由 SessionSelectController 的 hook 回收（见 HBGroupHooks.xm），
    // 这里把 completion 通过关联对象挂到 picker 上。
    if (completion) {
        objc_setAssociatedObject(picker, kHBGroupPickerCompletionKey, [completion copy],
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

+ (void)finishPicker:(id)picker {
    if (!picker) return;
    void (^completion)(NSArray<NSString *> *) =
        objc_getAssociatedObject(picker, kHBGroupPickerCompletionKey);
    if (!completion) return;
    objc_setAssociatedObject(picker, kHBGroupPickerCompletionKey, nil, OBJC_ASSOCIATION_ASSIGN);

    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    NSArray *records = HBSend(picker, @"contactSelectionRecords", @[]);
    if ([records isKindOfClass:[NSArray class]]) {
        for (id record in records) {
            NSString *userName = HBSend(record, @"m_nsUsrName", @[]);
            if (![userName isKindOfClass:[NSString class]] || !userName.length) {
                userName = [HBGroupEngine userNameOfSession:record];
            }
            if (userName.length) [selected addObject:userName];
        }
    }
    completion([selected copy]);
}

- (void)closeSessionMenus {
    id home = [self homeController];
    if (!home) return;
    id tableView = HBSend(home, @"tableView", @[]);
    NSArray *cells = HBSend(tableView, @"visibleCells", @[]);
    if (![cells isKindOfClass:[NSArray class]]) return;
    for (id cell in cells) {
        HBCall(cell, @"forceHideMenuOptionsAnimated:", @[@(NO)]);
    }
}

- (id)homeController {
    id logic = [self sessionLogic];
    id home = HBSend(logic, @"getViewController", @[]);
    if (home) return home;
    Class cls = HBFindClass(@[@"NewMainFrameViewController", @"MainFrameViewController"]);
    return cls ? HBSend(cls, @"sharedInstance", @[]) : nil;
}

#pragma mark - UI 小工具

- (UIWindow *)keyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

- (void)toast:(NSString *)text {
    if (!text.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self keyWindow];
        if (!window) return;

        UILabel *label = [[UILabel alloc] init];
        label.text = text;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:14];
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        label.layer.cornerRadius = 10;
        label.layer.masksToBounds = YES;

        CGSize maxSize = CGSizeMake(window.bounds.size.width - 80, CGFLOAT_MAX);
        CGSize size = [label sizeThatFits:maxSize];
        label.frame = CGRectMake(0, 0, size.width + 28, size.height + 20);
        label.center = CGPointMake(window.bounds.size.width / 2, window.bounds.size.height / 2);

        [window addSubview:label];
        label.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{
                label.alpha = 0;
            } completion:^(BOOL done) {
                [label removeFromSuperview];
            }];
        }];
    });
}

@end
