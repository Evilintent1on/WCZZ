#import "WeChatCompat.h"
#import "WeChatHeaders.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"
#import "MessageMenuSettingsController.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <stdarg.h>

#pragma mark - Card background (25pt radius)

@interface WCZZCardBgView : UIView
@property (nonatomic, assign) UIRectCorner corners;
@property (nonatomic, assign) BOOL showSeparator;
@property (nonatomic, strong) UIColor *cardColor;
@end
@implementation WCZZCardBgView
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *card = [self viewWithTag:999];
    if (!card) {
        card = [[UIView alloc] init];
        card.tag = 999;
        [self addSubview:card];
    }
    if (self.cardColor) card.backgroundColor = self.cardColor;
    else if (@available(iOS 13.0, *)) card.backgroundColor = [UIColor systemBackgroundColor];
    else card.backgroundColor = [UIColor whiteColor];
    CGFloat inset = 16.0;
    card.frame = CGRectMake(inset, 0, self.bounds.size.width - inset*2, self.bounds.size.height);
    card.layer.cornerRadius = 20.0;
    card.layer.masksToBounds = YES;
    if (@available(iOS 11.0, *)) {
        CACornerMask mask = 0;
        if (self.corners & UIRectCornerTopLeft) mask |= kCALayerMinXMinYCorner;
        if (self.corners & UIRectCornerTopRight) mask |= kCALayerMaxXMinYCorner;
        if (self.corners & UIRectCornerBottomLeft) mask |= kCALayerMinXMaxYCorner;
        if (self.corners & UIRectCornerBottomRight) mask |= kCALayerMaxXMaxYCorner;
        card.layer.maskedCorners = mask;
    }
    UIView *sep = [self viewWithTag:998];
    if (self.showSeparator) {
        if (!sep) {
            sep = [[UIView alloc] init];
            sep.tag = 998;
            if (@available(iOS 13.0, *)) sep.backgroundColor = [UIColor separatorColor];
            else sep.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
            [self addSubview:sep];
        }
        CGFloat sepInset = 32.0;
        sep.frame = CGRectMake(sepInset, self.bounds.size.height - 0.5, self.bounds.size.width - sepInset - 16.0, 0.5);
        sep.hidden = NO;
    } else if (sep) {
        sep.hidden = YES;
    }
}
@end

static void WCZZApplyCard(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip) {
    NSInteger rows = [tv numberOfRowsInSection:ip.section];
    UIRectCorner corners;
    if (ip.row == 0 && ip.row == rows-1) corners = UIRectCornerAllCorners;
    else if (ip.row == 0) corners = UIRectCornerTopLeft|UIRectCornerTopRight;
    else if (ip.row == rows-1) corners = UIRectCornerBottomLeft|UIRectCornerBottomRight;
    else corners = 0;
    BOOL showSep = (ip.row < rows-1);
    WCZZCardBgView *bg = [[WCZZCardBgView alloc] init];
    bg.backgroundColor = [UIColor clearColor];
    bg.corners = corners;
    bg.showSeparator = showSep;
    cell.backgroundView = bg;
    WCZZCardBgView *selBg = [[WCZZCardBgView alloc] init];
    selBg.backgroundColor = [UIColor clearColor];
    selBg.corners = corners;
    selBg.showSeparator = showSep;
    if (@available(iOS 13.0, *)) selBg.cardColor = [UIColor systemGray5Color];
    else selBg.cardColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    cell.selectedBackgroundView = selBg;
    cell.backgroundColor = [UIColor clearColor];
}
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

static id WCZZValue(id obj, NSString *key) {
    if (!obj) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}



#pragma mark - Settings

@interface WCZZSettingsViewController : UITableViewController @end
@implementation WCZZSettingsViewController
- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"WCZZ"; self.tableView.tableFooterView = [UIView new]; self.tableView.rowHeight = 55; self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return 1; }
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 28.0; }
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section { return section == 0 ? 8.0 : 0.01; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"红包";
    return @"消息";
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"wczz.setting"]; if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"wczz.setting"];
    c.accessoryView = nil; c.accessoryType = UITableViewCellAccessoryNone; c.detailTextLabel.text = nil; c.selectionStyle=UITableViewCellSelectionStyleDefault;
    for (UIView *v in [c.contentView.subviews copy]) { if ([v isKindOfClass:[UISwitch class]]) [v removeFromSuperview]; }
    WCZZApplyCard(c, tv, ip);
    c.layoutMargins = UIEdgeInsetsMake(0, 32, 0, 16);
    if (ip.section == 0) {
        c.textLabel.text=@"红包详情"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *sw=[UISwitch new]; sw.tag=100; sw.on=WCZZBool(WCZZRedDetailKey,YES); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else {
        c.textLabel.text=@"长按菜单"; c.accessoryType=UITableViewCellAccessoryNone;
    }
    return c;
}
- (void)wczzMain:(UISwitch *)sw { if(sw.tag==100) WCZZSetBool(WCZZRedDetailKey,sw.on); }
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self.navigationController pushViewController:[MessageMenuSettingsController new] animated:YES];
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
        MMMenuCaptureTitles((NSArray *)result);
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

#pragma mark - Plugin registration / delayed hook installation

static BOOL WCZZRegistered = NO;
static BOOL WCZZRedHooksStarted = NO;
static BOOL WCZZMenuHooksStarted = NO;
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
        WCZZRegisterPlugin();
        if ((!WCZZRedHooksStarted || !WCZZMenuHooksStarted || !WCZZRegistered) && WCZZInstallAttempts++ < 60) {
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
