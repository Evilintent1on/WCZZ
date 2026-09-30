#import "WeChatCompat.h"
#import "WeChatHeaders.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"
#import "MessageMenuSettingsController.h"
#import "WCHookSettingsManager.h"
#import "WCHookSwipeUtilities.h"
#import "WCHookMessageNavigator.h"
#import "WCHookSettingsViewController.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <stdarg.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <limits.h>

// WCZZ 0.1-1
// Red packet detail overlay + message long-press menu customizer for WeChat 8.0.75.

static NSString * const WCZZRedDetailKey     = @"wczz.redDetail.enabled";

static BOOL WCZZBool(NSString *key, BOOL fallback) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : fallback;
}
static void WCZZSetBool(NSString *key, BOOL value) {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
}
static void WCZZLog(NSString *format, ...) { }

// 滑动动作：0=关闭，1=引用，2=删除/撤回
// 返回是否有任意滑动方向配置了动作
static BOOL WCHookAnySwipeEnabled(void) {
    NSArray *keys = @[@"com.wchook.swipeLeftOther", @"com.wchook.swipeRightOther",
                      @"com.wchook.swipeLeftSelf", @"com.wchook.swipeRightSelf"];
    NSArray *defaults = @[@1, @0, @2, @1];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        NSInteger value;
        if (![[NSUserDefaults standardUserDefaults] objectForKey:key]) {
            value = [defaults[i] integerValue];
        } else {
            value = [[NSUserDefaults standardUserDefaults] integerForKey:key];
        }
        if (value != 0) {
            return YES;
        }
    }
    return NO;
}

// 获取指定方向的滑动动作（direction: 1=左滑，2=右滑；isSelf: 是否我方消息）
static NSInteger WCHookSwipeActionForDirection(NSInteger direction, BOOL isSelf) {
    NSString *key = nil;
    NSInteger defaultValue = 0;
    if (direction == 1) { // 左滑
        if (isSelf) {
            key = @"com.wchook.swipeLeftSelf";
            defaultValue = 2; // 撤回
        } else {
            key = @"com.wchook.swipeLeftOther";
            defaultValue = 1; // 引用
        }
    } else if (direction == 2) { // 右滑
        if (isSelf) {
            key = @"com.wchook.swipeRightSelf";
            defaultValue = 1; // 引用
        } else {
            key = @"com.wchook.swipeRightOther";
            defaultValue = 0; // 关闭
        }
    }
    if (!key) {
        return 0;
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:key]) {
        return defaultValue;
    }
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    if (value < 0 || value > 2) {
        return defaultValue;
    }
    return value;
}

static id WCZZValue(id obj, NSString *key) {
    if (!obj) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}


#pragma mark - Settings

@interface WCZZSettingsViewController : UITableViewController @end
@implementation WCZZSettingsViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"WCZZ"; self.tableView.tableFooterView = [UIView new]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 1; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"红包";
    if (section == 1) return @"消息";
    return @"手势";
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"wczz.setting"]; if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"wczz.setting"];
    c.accessoryView = nil; c.accessoryType = UITableViewCellAccessoryNone; c.detailTextLabel.text = nil;
    if (ip.section == 0) {
        c.textLabel.text=@"红包详情"; UISwitch *sw=[UISwitch new]; sw.tag=100; sw.on=WCZZBool(WCZZRedDetailKey,YES); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged]; c.accessoryView=sw;
    } else if (ip.section == 1) {
        c.textLabel.text=@"长按菜单"; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else {
        c.textLabel.text=@"左滑引用"; c.detailTextLabel.text=[WCHookSettings() summaryTextForSwipeQuote]; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}
- (void)wczzMain:(UISwitch *)sw { if(sw.tag==100) WCZZSetBool(WCZZRedDetailKey,sw.on); }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self.navigationController pushViewController:[MessageMenuSettingsController new] animated:YES];
    else if (ip.section == 2) [self.navigationController pushViewController:[WCHookSettingsViewController new] animated:YES];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
@end

#pragma mark - Red envelope summary overlay

static const void *WCZZRedDataKey = &WCZZRedDataKey;
static const void *WCZZRedSummaryLabelKey = &WCZZRedSummaryLabelKey;
static id WCZZLatestRedData = nil;

static id WCZZRedDetailInfo(id data) {
    if (!data) return nil;
    id info = WCZZValue(data, @"m_oWCRedEnvelopesDetailInfo");
    if (info) return info;
    id nested = WCZZValue(data, @"m_data");
    if (nested) {
        info = WCZZValue(nested, @"m_oWCRedEnvelopesDetailInfo");
        if (info) return info;
    }
    return nil;
}

static UILabel *WCZZRedSummaryLabel(id vc) {
    id label = objc_getAssociatedObject(vc, WCZZRedSummaryLabelKey);
    return [label isKindOfClass:[UILabel class]] ? label : nil;
}

static UILabel *WCZZEnsureRedSummaryLabel(id vc) {
    if (!vc || ![vc isKindOfClass:[UIViewController class]]) return nil;
    UILabel *label = WCZZRedSummaryLabel(vc);
    UIViewController *controller = (UIViewController *)vc;
    if (!label) {
        UIView *root = controller.view;
        if (!root) return nil;

        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = 0x575A01;
        label.numberOfLines = 4;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.backgroundColor = [UIColor clearColor];
        label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        label.userInteractionEnabled = NO;
        label.layer.zPosition = 1000.0;
        [root addSubview:label];
        objc_setAssociatedObject(vc, WCZZRedSummaryLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return label;
}

static void WCZZLayoutRedSummaryLabel(id vc) {
    UILabel *label = WCZZEnsureRedSummaryLabel(vc);
    if (!label) return;

    UIView *root = [(UIViewController *)vc view];
    // The red header is above/around the safe-area region on this WeChat
    // screen.  Starting at safeAreaInsets.top made the four-line summary get
    // clipped by the header, leaving only about one and a half lines visible.
    // Put the overlay near the very top of the red header instead.
    CGFloat width = MIN(280.0, MAX(230.0, root.bounds.size.width * 0.68));
    CGFloat height = 102.0;
    CGFloat x = (root.bounds.size.width - width) * 0.5;
    CGFloat y = 40.0;
    label.frame = CGRectMake(x, y, width, height);
}

static void WCZZApplyRedSummary(id vc, id data) {
    if (!WCZZBool(WCZZRedDetailKey, YES) || !vc || !data) return;

    id info = WCZZRedDetailInfo(data);
    if (!info) {
        WCZZLog(@"red summary: detail info missing data=%p", data);
        return;
    }

    UILabel *label = WCZZEnsureRedSummaryLabel(vc);
    if (!label) return;

    long long totalAmount = MAX(0LL, [WCZZValue(info, @"m_lTotalAmount") longLongValue]);
    long long totalNum = MAX(0LL, [WCZZValue(info, @"m_lTotalNum") longLongValue]);
    long long recAmount = MAX(0LL, [WCZZValue(info, @"m_lRecAmount") longLongValue]);
    long long recNum = MAX(0LL, [WCZZValue(info, @"m_lRecNum") longLongValue]);
    long long remainAmount = MAX(0LL, totalAmount - recAmount);
    long long remainNum = MAX(0LL, totalNum - recNum);

    // IMPORTANT: this is a separate overlay label.  Never modify
    // m_receivedInfoLable, because that label belongs to WeChat's sender/amount
    // area (for example: "小号发出的红包" and "0.01元").
    label.text = [NSString stringWithFormat:@"总金额:%.2f元\n总个数:%lld个\n剩余:%lld个\n剩余:%.2f元",
                  totalAmount / 100.0,
                  totalNum,
                  remainNum,
                  remainAmount / 100.0];
    [label.superview bringSubviewToFront:label];
    WCZZLayoutRedSummaryLabel(vc);
    WCZZLog(@"red summary applied total=%.2f num=%lld remain=%.2f/%lld label=%p",
            totalAmount / 100.0,
            totalNum,
            remainAmount / 100.0,
            remainNum,
            label);
}

static void WCZZScheduleRedSummary(id vc, id data) {
    if (!vc || !data) return;
    objc_setAssociatedObject(vc, WCZZRedDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSInteger i = 0; i < 6; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * i * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (vc) WCZZApplyRedSummary(vc, data);
        });
    }
}

%group WCZZRedHooks
%hook WCRedEnvelopesControlLogic
- (id)initWithData:(id)data {
    id obj = %orig(data);
    WCZZLatestRedData = data;
    if (obj && data) objc_setAssociatedObject(obj, WCZZRedDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCZZLog(@"red control init data=%p", data);
    return obj;
}
- (void)showDetailView {
    %orig;
    id data = WCZZValue(self, @"m_data");
    if (!data) data = objc_getAssociatedObject(self, WCZZRedDataKey);
    WCZZLatestRedData = data ?: WCZZLatestRedData;
    WCZZLog(@"red base showDetailView data=%p", data);
}
%end

%hook WCRedEnvelopesReceiveControlLogic
- (id)initWithData:(id)data Scene:(int)scene {
    id obj = %orig(data, scene);
    WCZZLatestRedData = data;
    WCZZLog(@"red receive init scene=%d data=%p obj=%p", scene, data, obj);
    if (obj && data) objc_setAssociatedObject(obj, WCZZRedDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return obj;
}
- (id)initWithData:(id)data {
    id obj = %orig(data);
    WCZZLatestRedData = data;
    WCZZLog(@"red receive init data=%p obj=%p", data, obj);
    if (obj && data) objc_setAssociatedObject(obj, WCZZRedDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return obj;
}
- (void)showDetailView {
    %orig;
    id data = WCZZValue(self, @"m_data");
    if (!data) data = objc_getAssociatedObject(self, WCZZRedDataKey);
    WCZZLatestRedData = data ?: WCZZLatestRedData;
    WCZZLog(@"red receive showDetailView data=%p", data);
}
%end

%hook WCRedEnvelopesRedEnvelopesDetailViewController
- (id)init {
    id obj = %orig;
    id data = WCZZLatestRedData;
    if (obj && data) objc_setAssociatedObject(obj, WCZZRedDataKey, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCZZLog(@"red detail init vc=%p", obj);
    return obj;
}
- (void)viewDidLoad {
    %orig;
    id data = objc_getAssociatedObject(self, WCZZRedDataKey);
    if (!data) data = WCZZLatestRedData;
    WCZZLog(@"red detail viewDidLoad data=%p", data);
    if (data) WCZZScheduleRedSummary(self, data);
    WCZZLayoutRedSummaryLabel(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    UILabel *label = WCZZRedSummaryLabel(self);
    if (label) WCZZLayoutRedSummaryLabel(self);
}
- (void)refreshViewWithData:(id)data {
    %orig(data);
    WCZZLog(@"red refreshViewWithData data=%p", data);
    if (data) WCZZScheduleRedSummary(self, data);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    id data = objc_getAssociatedObject(self, WCZZRedDataKey);
    if (!data) data = WCZZLatestRedData;
    WCZZLog(@"red detail viewWillAppear data=%p", data);
    if (data) WCZZScheduleRedSummary(self, data);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    id data = objc_getAssociatedObject(self, WCZZRedDataKey);
    if (!data) data = WCZZLatestRedData;
    WCZZLog(@"red detail viewDidAppear data=%p", data);
    if (data) WCZZScheduleRedSummary(self, data);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    if (WCZZLatestRedData == objc_getAssociatedObject(self, WCZZRedDataKey)) WCZZLatestRedData = nil;
    objc_setAssociatedObject(self, WCZZRedDataKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end
%end

#pragma mark - Message long-press menu customization

// Remember the last message cell, used for backup/restore.
static __weak UIView *WCZZLastMessageCell;

static BOOL WCZZIsMessageCell(UIView *view) {
    if (!view) return NO;
    Class base = NSClassFromString(@"BaseMessageCellView");
    Class common = NSClassFromString(@"CommonMessageCellView");
    Class emoticon = NSClassFromString(@"EmoticonMessageCellView");

    UIView *candidate = view;
    for (NSUInteger depth = 0; candidate && depth < 20; depth++) {
        if ((base && [candidate isKindOfClass:base]) ||
            (common && [candidate isKindOfClass:common]) ||
            (emoticon && [candidate isKindOfClass:emoticon])) {
            return YES;
        }
        candidate = candidate.superview;
    }
    return NO;
}

static void WCZZRememberCell(id object) {
    if ([object isKindOfClass:[UIView class]] && WCZZIsMessageCell((UIView *)object)) {
        WCZZLastMessageCell = object;
    }
}

static id WCZZSafeValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}

static BOOL WCZZObjectContainsBackup(id object, NSUInteger depth) {
    if (!object || depth > 3) return NO;
    if ([object isKindOfClass:[NSString class]]) {
        NSString *value = (NSString *)object;
        return MMMenuIsBackupFilename(value) ||
               [value rangeOfString:@"MessageMenu_backup" options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    if ([object isKindOfClass:[NSURL class]]) {
        return WCZZObjectContainsBackup(((NSURL *)object).path, depth + 1);
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id value in [(NSDictionary *)object allValues]) {
            if (WCZZObjectContainsBackup(value, depth + 1)) return YES;
        }
    }
    if ([object isKindOfClass:[NSArray class]]) {
        for (id value in (NSArray *)object) {
            if (WCZZObjectContainsBackup(value, depth + 1)) return YES;
        }
    }
    return NO;
}

static UIViewController *WCZZViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

static NSURL *WCZZBackupURLForCell(UIView *cell) {
    id model = WCZZSafeValue(cell, @"viewModel");
    for (NSString *key in @[@"fileURL", @"filePath", @"m_nsFilePath", @"path"]) {
        id value = WCZZSafeValue(model, key);
        NSURL *url = nil;
        if ([value isKindOfClass:[NSURL class]]) {
            url = value;
        } else if ([value isKindOfClass:[NSString class]]) {
            NSString *path = value;
            url = [path rangeOfString:@"://"].location != NSNotFound
                ? [NSURL URLWithString:path] : [NSURL fileURLWithPath:path];
        }
        if (url.path.length && MMMenuIsBackupFilename(url.lastPathComponent) &&
            [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
            return url;
        }
    }
    return MMMenuLatestBackupURL();
}

static void WCZZShowRestoreResult(UIView *cell, BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *controller = WCZZViewControllerForView(cell);
        if (!controller) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:(success ? @"还原完成" : @"无法还原")
                                                                       message:(success ? @"配置已还原并立即生效，无需重启微信。" : (error.localizedDescription ?: @"备份文件无效。"))
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [controller presentViewController:alert animated:YES completion:nil];
    });
}

static void WCZZRestoreBackupFromCell(UIView *cell) {
    NSURL *url = WCZZBackupURLForCell(cell);
    NSError *error = nil;
    BOOL success = url && MMMenuRestoreFromBackupURL(url, &error);
    if (!success && !error) {
        error = [NSError errorWithDomain:@"WCZZ.MessageMenu.Backup"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"找不到备份文件"}];
    }
    WCZZShowRestoreResult(cell, success, error);
}

static id WCZZCreateRestoreItem(id target) {
    SEL action = @selector(wczzMenu_restoreBackup:);
    Class customClass = NSClassFromString(@"MMMenuItem");
    SEL initializer = @selector(initWithTitle:target:action:);
    if (customClass && [customClass instancesRespondToSelector:initializer]) {
        @try {
            return ((id (*)(id, SEL, id, id, SEL))objc_msgSend)(
                [customClass alloc], initializer, @"还原", target, action);
        } @catch (NSException *exception) {}
    }
    return [[UIMenuItem alloc] initWithTitle:@"还原" action:action];
}

static BOOL WCZZMenuItemsContainTitle(NSArray *items, NSString *title) {
    for (id item in items) {
        if ([MMMenuItemTitle(item) isEqualToString:title]) return YES;
    }
    return NO;
}

static NSArray *WCZZAppendRestoreItemIfNeeded(NSArray *items, id source) {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return items;

    UIView *cell = nil;
    if ([source isKindOfClass:[UIView class]] && WCZZIsMessageCell(source)) {
        cell = source;
    } else if ([WCZZLastMessageCell isKindOfClass:[UIView class]]) {
        cell = WCZZLastMessageCell;
    }
    if (!cell) return items;

    id model = WCZZSafeValue(cell, @"viewModel");
    BOOL isBackup = WCZZObjectContainsBackup(model, 0) ||
                    WCZZObjectContainsBackup(cell, 0) ||
                    WCZZObjectContainsBackup(items, 0);

    if (!isBackup || WCZZMenuItemsContainTitle(items, @"还原")) {
        return items;
    }

    NSMutableArray *result = [items mutableCopy];
    [result addObject:WCZZCreateRestoreItem(cell)];
    return [result copy];
}

static id WCZZApplyMenuPolicy(id result, id source, SEL selector) {
    (void)selector;
    WCZZRememberCell(source);

    if (![result isKindOfClass:[NSArray class]]) return result;

    @try {
        NSArray *processed = MMMenuApplyPolicy((NSArray *)result);
        return WCZZAppendRestoreItemIfNeeded(processed, source);
    } @catch (NSException *exception) {
        return result;
    }
}

static BOOL WCZZMenuItemsLookLikeMessageMenu(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return NO;

    NSArray *configured = MMMenuLoadEntries();
    for (id item in items) {
        NSString *title = MMMenuItemTitle(item);
        if (!title.length) continue;

        for (NSDictionary *entry in configured) {
            if ([title isEqualToString:entry[MMMenuEntryTitleKey]]) return YES;
        }

        NSString *className = NSStringFromClass([item class]);
        if ([className rangeOfString:@"MMMenu" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSArray *WCZZProcessControllerItems(NSArray *items, UIResponder *responder, SEL selector) {
    BOOL isMessage = [responder isKindOfClass:[UIView class]] && WCZZIsMessageCell((UIView *)responder);

    if (!isMessage && WCZZLastMessageCell && WCZZMenuItemsLookLikeMessageMenu(items)) {
        isMessage = YES;
    }

    if (!isMessage && !responder && [items isKindOfClass:[NSArray class]]) {
        isMessage = YES;
    }

    if (!isMessage) return items;

    return WCZZApplyMenuPolicy(items, responder ?: WCZZLastMessageCell, selector);
}

%group WCZZMenuHooks
%hook BaseMessageCellView

- (id)filteredMenuItems:(id)items {
    WCZZRememberCell(self);
    id result = %orig(items);
    return WCZZApplyMenuPolicy(result, self, _cmd);
}

- (id)operationMenuItems {
    WCZZRememberCell(self);
    id result = %orig;
    return WCZZApplyMenuPolicy(result, self, _cmd);
}

%new
- (void)wczzMenu_restoreBackup:(id)sender {
    (void)sender;
    WCZZRestoreBackupFromCell(self);
}

%end

%hook EmoticonMessageCellView

- (id)filteredMenuItems:(id)items {
    WCZZRememberCell(self);
    id result = %orig(items);
    return WCZZApplyMenuPolicy(result, self, _cmd);
}

- (id)operationMenuItems {
    WCZZRememberCell(self);
    id result = %orig;
    return WCZZApplyMenuPolicy(result, self, _cmd);
}

%end

%hook MMMenuController

- (void)setMenuItems:(NSArray *)items {
    UIResponder *responder = nil;
    @try {
        responder = self.responder;
    } @catch (NSException *exception) {}

    NSArray *result = WCZZProcessControllerItems(items, responder, _cmd);
    %orig(result);
}

%end

%hook UIMenuController

- (void)setMenuItems:(NSArray<UIMenuItem *> *)items {
    NSArray *result = items;
    if (WCZZMenuItemsLookLikeMessageMenu(items) || WCZZLastMessageCell) {
        result = WCZZApplyMenuPolicy(items, WCZZLastMessageCell, _cmd);
    }
    %orig(result);
}

%end
%end

#pragma mark - Swipe-to-quote (WCHook)

@interface CommonMessageCellView (WCHookSwipe)
@property(nonatomic, strong) UIPanGestureRecognizer *wchook_swipeGesture;
@property(nonatomic, strong) UIImpactFeedbackGenerator *wchook_feedbackGenerator;
@property(nonatomic, assign) BOOL wchook_feedbackTriggered;
- (void)wchook_setupSwipeGestureIfNeeded;
- (void)wchook_handleSwipe:(UIPanGestureRecognizer *)gesture;
- (void)wchook_resetSwipeAnimated:(BOOL)animated;
- (void)wchook_triggerQuoteReply;
- (BOOL)wchook_isMessageFromSelf;
- (void)wchook_triggerDeleteMessage;
- (void)wchook_triggerRecallMessage;
- (void)wchook_insertAtMention:(NSString *)username nickname:(NSString *)nickname;
- (id)wchook_findInputToolViewInView:(UIView *)view;
- (UITextView *)wchook_findTextViewInView:(UIView *)view;
- (void)onShowMsgReplyMenuItem:(id)sender;
@end

%group WCZZSwipeHooks
%hook CommonMessageCellView

%property(nonatomic, strong) UIPanGestureRecognizer *wchook_swipeGesture;
%property(nonatomic, strong) UIImpactFeedbackGenerator *wchook_feedbackGenerator;
%property(nonatomic, assign) BOOL wchook_feedbackTriggered;

- (void)didMoveToWindow {
    %orig;

    if (self.window) {
        [self wchook_setupSwipeGestureIfNeeded];
    } else {
        [self wchook_resetSwipeAnimated:NO];
    }
}

%new
- (void)wchook_setupSwipeGestureIfNeeded {
    if (!WCHookAnySwipeEnabled()) {
        if (self.wchook_swipeGesture) {
            self.wchook_swipeGesture.enabled = NO;
        }
        return;
    }

    UIPanGestureRecognizer *gesture = self.wchook_swipeGesture;
    if (!gesture) {
        gesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wchook_handleSwipe:)];
        gesture.maximumNumberOfTouches = 1;
        gesture.minimumNumberOfTouches = 1;
        gesture.cancelsTouchesInView = YES;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = (id<UIGestureRecognizerDelegate>)self;
        [self addGestureRecognizer:gesture];
        self.wchook_swipeGesture = gesture;
    }

    gesture.enabled = YES;

    // 根据设置创建对应强度的震动发生器（档位变化时重建）
    NSInteger hapticLevel = [WCHookSettings() wchook_hapticLevel];
    if (hapticLevel == 0) {
        self.wchook_feedbackGenerator = nil;
    } else {
        UIImpactFeedbackStyle style = UIImpactFeedbackStyleMedium;
        if (hapticLevel == 1) {
            style = UIImpactFeedbackStyleLight;
        } else if (hapticLevel == 3) {
            style = UIImpactFeedbackStyleHeavy;
        }
        self.wchook_feedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:style];
    }
}

%new
- (void)wchook_handleSwipe:(UIPanGestureRecognizer *)gesture {
    if (!gesture) {
        return;
    }

    if (!WCHookAnySwipeEnabled()) {
        [self wchook_resetSwipeAnimated:NO];
        return;
    }

    NSArray<UIView *> *messageViews = [WCHookSwipeUtilities relatedMessageViewsForCommonView:self];
    CGPoint translation = [gesture translationInView:self];
    CGPoint velocity = [gesture velocityInView:self];

    if ([WCHookSwipeUtilities shouldIgnoreTranslation:translation]) {
        [WCHookSwipeUtilities applyTransform:CGAffineTransformIdentity toViews:messageViews];
        if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
            [self wchook_resetSwipeAnimated:NO];
        }
        return;
    }

    CGFloat threshold = [WCHookSwipeUtilities thresholdForView:self];

    switch (gesture.state) {
    case UIGestureRecognizerStateBegan: {
        [self.wchook_feedbackGenerator prepare];
        self.wchook_feedbackTriggered = NO;
        break;
    }
    case UIGestureRecognizerStateChanged: {
        CGFloat clamped = [WCHookSwipeUtilities clampedTranslation:translation.x threshold:threshold];
        CGAffineTransform transform = CGAffineTransformMakeTranslation(clamped, 0.0f);
        [WCHookSwipeUtilities applyTransform:transform toViews:messageViews];

        if (!self.wchook_feedbackTriggered && fabs(translation.x) >= threshold) {
            [self.wchook_feedbackGenerator impactOccurred];
            self.wchook_feedbackTriggered = YES;
        }
        break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateEnded: {
        NSInteger direction = [WCHookSwipeUtilities triggerDirectionWithTranslation:translation velocity:velocity threshold:threshold];
        if (direction != 0) {
            if (!self.wchook_feedbackTriggered) {
                [self.wchook_feedbackGenerator impactOccurred];
                self.wchook_feedbackTriggered = YES;
            }
            BOOL isSelf = [self wchook_isMessageFromSelf];
            NSInteger action = WCHookSwipeActionForDirection(direction, isSelf);
            if (action == 1) {
                [self wchook_triggerQuoteReply];
            } else if (action == 2) {
                if (isSelf) {
                    [self wchook_triggerRecallMessage];
                } else {
                    [self wchook_triggerDeleteMessage];
                }
            }
            // action == 0: 关闭，不执行任何操作
        }
        [self wchook_resetSwipeAnimated:NO];
        break;
    }
    default: {
        break;
    }
    }
}

%new
- (void)wchook_resetSwipeAnimated:(BOOL)animated {
    NSArray<UIView *> *messageViews = [WCHookSwipeUtilities relatedMessageViewsForCommonView:self];
    [WCHookSwipeUtilities animateResetForViews:messageViews animated:animated];
    self.wchook_feedbackTriggered = NO;
}

%new
- (void)wchook_triggerQuoteReply {
    // 如果开启了引用并艾特，先获取发送者信息
    NSString *atUsername = nil;
    NSString *atNickname = nil;
    if ([WCHookSettings() isEnabledForKey:@"WCHookQuoteAndAt"]) {
        @try {
            id messageWrap = nil;
            if ([self respondsToSelector:@selector(messageWrap)]) {
                messageWrap = ((id (*)(id, SEL))objc_msgSend)(self, @selector(messageWrap));
            } else if ([self respondsToSelector:@selector(getMessageWrap)]) {
                messageWrap = ((id (*)(id, SEL))objc_msgSend)(self, @selector(getMessageWrap));
            }
            if (messageWrap) {
                if ([messageWrap respondsToSelector:@selector(fromUsrName)]) {
                    atUsername = ((id (*)(id, SEL))objc_msgSend)(messageWrap, @selector(fromUsrName));
                }
                // 尝试获取昵称用于显示
                if ([self respondsToSelector:@selector(getContactDisplayName)]) {
                    atNickname = ((id (*)(id, SEL))objc_msgSend)(self, @selector(getContactDisplayName));
                }
            }
        } @catch (__unused NSException *exception) {
        }
    }

    // 尝试多个引用相关的 selector（best-effort）
    NSArray *selectors = @[@"onShowMsgReplyMenuItem:", @"onReplyMsg:", @"onQuoteMsg:", @"showReplyMenu"];
    BOOL triggered = NO;
    for (NSString *selName in selectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([self respondsToSelector:sel]) {
            @try {
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        if ([selName hasSuffix:@":"]) {
                            ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
                        } else {
                            ((void (*)(id, SEL))objc_msgSend)(self, sel);
                        }
                    } @catch (__unused NSException *exception) {
                    }
                });
                triggered = YES;
                break;
            } @catch (__unused NSException *exception) {
            }
        }
    }
    if (!triggered) {
        return;
    }

    // 引用触发后，插入艾特
    if (atUsername.length > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self wchook_insertAtMention:atUsername nickname:atNickname];
        });
    }
}

%new
- (BOOL)wchook_isMessageFromSelf {
    @try {
        id messageWrap = nil;
        if ([self respondsToSelector:@selector(messageWrap)]) {
            messageWrap = [self performSelector:@selector(messageWrap)];
        } else if ([self respondsToSelector:@selector(getMessageWrap)]) {
            messageWrap = [self performSelector:@selector(getMessageWrap)];
        }
        if (!messageWrap) {
            return NO;
        }
        // 尝试通过 isSenderFromSelf 判断
        if ([messageWrap respondsToSelector:@selector(isSenderFromSelf)]) {
            return [[messageWrap performSelector:@selector(isSenderFromSelf)] boolValue];
        }
        // 尝试通过 fromUsrName 与当前登录用户对比
        NSString *fromUsrName = nil;
        if ([messageWrap respondsToSelector:@selector(fromUsrName)]) {
            fromUsrName = [messageWrap performSelector:@selector(fromUsrName)];
        }
        if (fromUsrName.length > 0) {
            // 获取当前登录用户
            id contactMgr = nil;
            @try {
                Class mgrClass = objc_getClass("CContactMgr");
                if (mgrClass && [mgrClass respondsToSelector:@selector(shareInstance)]) {
                    contactMgr = [mgrClass performSelector:@selector(shareInstance)];
                }
            } @catch (__unused NSException *e) {
            }
            if (contactMgr && [contactMgr respondsToSelector:@selector(getSelfContact)]) {
                id selfContact = [contactMgr performSelector:@selector(getSelfContact)];
                if (selfContact && [selfContact respondsToSelector:@selector(m_nsUsrName)]) {
                    NSString *selfUsrName = [selfContact performSelector:@selector(m_nsUsrName)];
                    if ([fromUsrName isEqualToString:selfUsrName]) {
                        return YES;
                    }
                }
            }
        }
    } @catch (__unused NSException *exception) {
    }
    return NO;
}

%new
- (void)wchook_triggerDeleteMessage {
    // 尝试调用删除消息的 selector（best-effort）
    NSArray *selectors = @[@"onDelMsg:", @"onDeleteMsg:", @"deleteMessage", @"onDeleteMessage:"];
    for (NSString *selName in selectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([self respondsToSelector:sel]) {
            @try {
                if ([selName hasSuffix:@":"]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
                } else {
                    ((void (*)(id, SEL))objc_msgSend)(self, sel);
                }
                return;
            } @catch (__unused NSException *exception) {
            }
        }
    }
}

%new
- (void)wchook_triggerRecallMessage {
    // 尝试调用撤回消息的 selector（best-effort）
    NSArray *selectors = @[@"onRevokeMsg:", @"onRecallMsg:", @"revokeMessage", @"onRevokeMessage:"];
    for (NSString *selName in selectors) {
        SEL sel = NSSelectorFromString(selName);
        if ([self respondsToSelector:sel]) {
            @try {
                if ([selName hasSuffix:@":"]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(self, sel, nil);
                } else {
                    ((void (*)(id, SEL))objc_msgSend)(self, sel);
                }
                return;
            } @catch (__unused NSException *exception) {
            }
        }
    }
}

%new
- (void)wchook_insertAtMention:(NSString *)username nickname:(NSString *)nickname {
    if (username.length == 0) {
        return;
    }
    @try {
        // 找到输入工具栏
        UIResponder *responder = self;
        while (responder) {
            if ([responder isKindOfClass:NSClassFromString(@"MMInputToolView")]) {
                break;
            }
            responder = [responder nextResponder];
        }
        // 如果没找到，尝试从窗口找
        id inputToolView = responder;
        if (!inputToolView) {
            UIWindow *window = [UIApplication sharedApplication].keyWindow;
            inputToolView = [self wchook_findInputToolViewInView:window];
        }
        if (!inputToolView) {
            return;
        }
        // 获取输入框
        UITextView *textView = nil;
        if ([inputToolView respondsToSelector:@selector(getTextView)]) {
            textView = [inputToolView performSelector:@selector(getTextView)];
        } else if ([inputToolView respondsToSelector:@selector(textView)]) {
            textView = [inputToolView performSelector:@selector(textView)];
        }
        if (![textView isKindOfClass:[UITextView class]]) {
            // 遍历子视图找 UITextView
            textView = [self wchook_findTextViewInView:(UIView *)inputToolView];
        }
        if (!textView) {
            return;
        }
        // 插入艾特文本
        NSString *displayName = nickname.length > 0 ? nickname : username;
        NSString *atText = [NSString stringWithFormat:@"@%@ ", displayName];
        NSString *currentText = textView.text ?: @"";
        // 避免重复插入
        if ([currentText hasPrefix:atText]) {
            return;
        }
        textView.text = [atText stringByAppendingString:currentText];
        // 触发文本变化通知，让微信识别艾特
        [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
    } @catch (__unused NSException *exception) {
    }
}

%new
- (id)wchook_findInputToolViewInView:(UIView *)view {
    if (!view) {
        return nil;
    }
    if ([view isKindOfClass:NSClassFromString(@"MMInputToolView")]) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        id result = [self wchook_findInputToolViewInView:subview];
        if (result) {
            return result;
        }
    }
    return nil;
}

%new
- (UITextView *)wchook_findTextViewInView:(UIView *)view {
    if (!view) {
        return nil;
    }
    if ([view isKindOfClass:[UITextView class]]) {
        return (UITextView *)view;
    }
    for (UIView *subview in view.subviews) {
        UITextView *result = [self wchook_findTextViewInView:subview];
        if (result) {
            return result;
        }
    }
    return nil;
}

- (void)handleTapForReferMsg:(id)sender {
    if ([WCHookSettings() isEnabledForKey:@"WCHookTapReferJump"] && [WCHookMessageNavigator senderLooksLikeReferView:sender]) {
        if ([WCHookMessageNavigator tryJumpFromCell:self]) {
            return;
        }
    }
    %orig;
}

- (void)handleTapReferMessage {
    if ([WCHookSettings() isEnabledForKey:@"WCHookTapReferJump"]) {
        if ([WCHookMessageNavigator tryJumpFromCell:self]) {
            return;
        }
    }
    %orig;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.wchook_swipeGesture) {
        if (!WCHookAnySwipeEnabled()) {
            return NO;
        }
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint velocity = [pan velocityInView:self];
        if (![WCHookSwipeUtilities isVelocityEligible:velocity]) {
            return NO;
        }
    }

    BOOL result = %orig;
    return result;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.wchook_swipeGesture) {
        return NO;
    }
    BOOL result = %orig;
    return result;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.wchook_swipeGesture && [otherGestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) {
        return YES;
    }
    BOOL result = %orig;
    return result;
}

%end

%hook MMInputToolView

- (void)onTapMsgReplyView:(id)sender {
    if ([WCHookSettings() isEnabledForKey:@"WCHookTapReferJump"] && [WCHookMessageNavigator senderLooksLikeReferView:sender]) {
        if ([WCHookMessageNavigator tryJumpFromInputTool:self]) {
            return;
        }
    }
    %orig;
}

%end
%end

#pragma mark - Plugin registration / delayed hook installation

static BOOL WCZZRegistered = NO;
static BOOL WCZZRedHooksStarted = NO;
static BOOL WCZZMenuHooksStarted = NO;
static BOOL WCZZSwipeHooksStarted = NO;
static NSInteger WCZZInstallAttempts = 0;

static void WCZZRegisterPlugin(void) {
    if (WCZZRegistered) return;
    Class c = objc_getClass("WCPluginsMgr");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL reg = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
    if (!c || ![c respondsToSelector:shared]) return;
    id mgr = ((id (*)(id, SEL))objc_msgSend)(c, shared);
    if (!mgr || ![mgr respondsToSelector:reg]) return;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(mgr, reg, @"WCZZ", @"0.1-1", @"WCZZSettingsViewController");
    WCZZRegistered = YES;
    WCZZLog(@"plugin registration OK");
}

static void WCZZInstallHooksWhenReady(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!WCZZRedHooksStarted &&
            objc_getClass("WCRedEnvelopesControlLogic") &&
            objc_getClass("WCRedEnvelopesReceiveControlLogic") &&
            objc_getClass("WCRedEnvelopesRedEnvelopesDetailViewController")) {
            %init(WCZZRedHooks);
            WCZZRedHooksStarted = YES;
            WCZZLog(@"red hooks installed");
        }
        if (!WCZZMenuHooksStarted &&
            objc_getClass("BaseMessageCellView") &&
            objc_getClass("MMMenuController")) {
            %init(WCZZMenuHooks);
            WCZZMenuHooksStarted = YES;
            WCZZLog(@"menu hooks installed");
        }
        if (!WCZZSwipeHooksStarted &&
            objc_getClass("CommonMessageCellView") &&
            objc_getClass("MMInputToolView")) {
            %init(WCZZSwipeHooks);
            WCZZSwipeHooksStarted = YES;
            WCZZLog(@"swipe hooks installed");
        }
        WCZZRegisterPlugin();
        if ((!WCZZRedHooksStarted || !WCZZMenuHooksStarted || !WCZZSwipeHooksStarted || !WCZZRegistered) && WCZZInstallAttempts++ < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WCZZInstallHooksWhenReady();
            });
        }
    });
}

%ctor {
    @autoreleasepool {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if ([d objectForKey:WCZZRedDetailKey] == nil) [d setBool:YES forKey:WCZZRedDetailKey];
        // Preload menu config so the first long-press has entries ready.
        (void)MMMenuLoadEntries();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCZZInstallHooksWhenReady(); });
    }
}
