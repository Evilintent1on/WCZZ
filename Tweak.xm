#import "WeChatCompat.h"
#import "WeChatHeaders.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"
#import "MessageMenuSettingsController.h"
#import "GroupHelperConfig.h"
#import "GroupHelperCompat.h"
#import "GroupHelperSessionPickerController.h"
#import "GroupHelperListController.h"
#import <objc/runtime.h>
#import <objc/message.h>

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
    else if (@available(iOS 13.0, *)) card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
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
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return section == 2 ? 6 : 1;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 28.0; }
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section { return section == 0 ? 8.0 : 0.01; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"红包";
    if (section == 1) return @"消息";
    return @"群助手";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == 2) return @"开启后所有群聊会收进「群助手」这一项，点它进入分组列表。想让某个群留在会话列表，就在群聊信息页把它设为「常用群」。";
    return nil;
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
    } else if (ip.section == 1) {
        c.textLabel.text=@"长按菜单"; c.accessoryType=UITableViewCellAccessoryNone;
    } else if (ip.section == 2 && ip.row == 0) {
        c.textLabel.text=@"启用群助手"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=MMGroupRuntimeStatus(); c.detailTextLabel.font=[UIFont systemFontOfSize:12.0];
        UISwitch *sw=[UISwitch new]; sw.tag=200; sw.on=MMGroupIsEnabled(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 1) {
        c.textLabel.text=@"分组名称"; c.detailTextLabel.text=MMGroupHelperTitle();
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 2) {
        c.textLabel.text=@"常用群（不进分组）";
        c.detailTextLabel.text=[NSString stringWithFormat:@"%lu 个", (unsigned long)[MMGroupCommonList() count]];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 3) {
        c.textLabel.text=@"立即刷新会话列表"; c.detailTextLabel.text=MMGroupSessionListHookInstalled()?@"已挂钩子":@"**钩子未安装**";
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 4) {
        c.textLabel.text=@"诊断信息（可复制）";
        c.detailTextLabel.text=MMGroupSessionListHookClassName() ?: @"";
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2) {
        c.textLabel.text=@"调试日志"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *sw=[UISwitch new]; sw.tag=201; sw.on=MMGroupDebugEnabled(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    }
    return c;
}
- (void)wczzMain:(UISwitch *)sw {
    if (sw.tag == 100) WCZZSetBool(WCZZRedDetailKey, sw.on);
    if (sw.tag == 200) { MMGroupSetEnabled(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 201) MMGroupSetDebugEnabled(sw.on);
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self.navigationController pushViewController:[MessageMenuSettingsController new] animated:YES];
    if (ip.section == 2 && ip.row == 1) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"分组名称"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = MMGroupHelperTitle();
            field.placeholder = @"群助手";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            MMGroupSetHelperTitle(alert.textFields.firstObject.text);
            [tv reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (ip.section == 2 && ip.row == 2) {
        GroupHelperSessionPickerController *picker =
            [[GroupHelperSessionPickerController alloc] initWithMode:GroupHelperPickerModeCommon
                                                          completion:^(NSUInteger count) {
            (void)count;
            [tv reloadData];
        }];
        [self.navigationController pushViewController:picker animated:YES];
    }
    if (ip.section == 2 && ip.row == 3) {
        MMGroupForceReloadSessions();
        [tv reloadData];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已请求刷新"
                                                                       message:@"如果列表没变化，请打开「诊断信息」把内容发我。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if (ip.section == 2 && ip.row == 4) {
        NSString *report = MMGroupDiagnostics();
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群助手诊断"
                                                                       message:report
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = report;
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
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

#pragma mark - Group helper hooks (群助手：会话列表入口 + 自有列表页)

static const void *WCZZGroupCommonSwitchKey = &WCZZGroupCommonSwitchKey;

// 从会话 cell 反查 username（不同版本字段名不同，逐个试）。
static NSString *WCZZGroupUserNameOfCell(id cell) {
    if (!cell) return nil;
    NSString *userName = WCZZValue(cell, @"m_nsUserName");
    if (![userName isKindOfClass:[NSString class]] || !userName.length) {
        userName = WCZZValue(cell, @"userName");
    }
    if (![userName isKindOfClass:[NSString class]] || !userName.length) {
        id data = WCZZValue(cell, @"m_cellData") ?: WCZZValue(cell, @"m_data") ?: WCZZValue(cell, @"viewModel");
        userName = WCZZValue(data, @"m_nsUserName") ?: WCZZValue(data, @"userName");
    }
    return [userName isKindOfClass:[NSString class]] ? userName : nil;
}

// 列表里某一行对应的会话（主界面自己的取法）。
static id WCZZGroupSessionAtIndexPath(id mainFrame, id indexPath) {
    SEL sel = NSSelectorFromString(@"logicGetSessionAtIndexPath:");
    if (!mainFrame || ![mainFrame respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(mainFrame, sel, indexPath);
}

static BOOL WCZZGroupIsHelperIndexPath(id mainFrame, id indexPath) {
    return MMGroupIsHelperSession(MMGroupValueSafe(WCZZGroupSessionAtIndexPath(mainFrame, indexPath), @"m_nsUserName"));
}

%group WCZZGroupHooks

// 会话列表面板的钩子不在这里：会话管理器的类名各版本不同，改用
// GroupHelperConfig 里的运行时安装（MMGroupInstallSessionListHook，候选类名探测）。

// 点「群助手」那一行 → 进插件自己的列表页（不交给微信）。
%hook NewMainFrameViewController

- (void)tableView:(id)tableView didSelectRowAtIndexPath:(id)indexPath {
    if (MMGroupIsEnabled() && WCZZGroupIsHelperIndexPath(self, indexPath)) {
        MMGroupLog(@"点击入口会话，进入列表页");
        [self.navigationController pushViewController:[[GroupHelperListController alloc] init] animated:YES];
        return;
    }
    %orig;
}

// 入口会话不许删、不许侧滑（MiYou 同样拦了这些）
- (void)tableView:(id)tableView commitEditingStyle:(long long)style forRowAtIndexPath:(id)indexPath {
    if (MMGroupIsEnabled() && WCZZGroupIsHelperIndexPath(self, indexPath)) return;
    %orig;
}

- (id)tableView:(id)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(id)indexPath {
    if (MMGroupIsEnabled() && WCZZGroupIsHelperIndexPath(self, indexPath)) return nil;
    return %orig;
}

- (id)tableView:(id)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(id)indexPath {
    if (MMGroupIsEnabled() && WCZZGroupIsHelperIndexPath(self, indexPath)) return nil;
    return %orig;
}

// 老版本微信有这个方法（8.0.79 已挪走），留着做兼容占位
- (void)deleteSessionAtIndex:(long long)index {
    %orig;
}

%end

// cell 层：入口会话不给编辑样式
%hook NewMainFrameCell

- (void)checkTableViewEditingStyle {
    if (MMGroupIsEnabled() && MMGroupIsHelperSession(WCZZGroupUserNameOfCell(self))) return;
    %orig;
}

- (void)onCommitEditingWithStyle:(long long)style tableView:(id)tableView {
    if (MMGroupIsEnabled() && MMGroupIsHelperSession(WCZZGroupUserNameOfCell(self))) return;
    %orig;
}

%end

// cell 数据：入口会话拿不到联系人，这里把结果打出来（出问题看日志/诊断）
%hook MainFrameCellDataManager

- (id)getCellDataByUsrName:(id)userName {
    id data = %orig;
    if (MMGroupIsHelperSession(userName)) {
        MMGroupLog(@"入口会话 cellData: %@", data ? NSStringFromClass([data class]) : @"nil");
    }
    return data;
}

- (id)getCellData:(id)arg1 {
    return %orig;
}

%end

// 前台会话相关（MiYou 也挂过，做个透传，防止入口会话被当成"最后会话"保存）
%hook MainFrameLogicController

- (void)asyncSaveFrontUserName {
    %orig;
}

- (void)syncSaveFrontUserName {
    %orig;
}

%end

// 未读显示判定（透传）
%hook CContact

- (BOOL)needShowUnreadCountOnSession {
    return %orig;
}

%end

// 群聊信息页：插入「设为常用群」表头开关。
%hook ChatRoomInfoViewController

- (void)viewDidLoad {
    %orig;
    [self wczzGroupInstallCommonSwitch];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self wczzGroupInstallCommonSwitch];
}

// 页面会重建表格，重建后把我们的表头补回去。
- (void)reloadTableData {
    %orig;
    [self wczzGroupInstallCommonSwitch];
}

%new
- (void)wczzGroupInstallCommonSwitch {
    if (!MMGroupIsEnabled()) return;

    NSString *userName = WCZZValue(WCZZValue(self, @"m_chatRoomContact"), @"m_nsUserName");
    if (!MMGroupIsGroupUserName(userName)) return;

    UITableView *tableView = nil;
    id tableInfo = WCZZValue(self, @"m_tableViewInfo");
    if ([tableInfo respondsToSelector:@selector(getTableView)]) {
        tableView = [tableInfo getTableView];
    }
    if (![tableView isKindOfClass:[UITableView class]]) {
        tableView = [self wczzGroupFindTableView:self.view];
    }

    UIView *header = objc_getAssociatedObject(self, WCZZGroupCommonSwitchKey);
    if (![header isKindOfClass:[UIView class]]) {
        header = [self wczzGroupMakeCommonHeader:userName];
        objc_setAssociatedObject(self, WCZZGroupCommonSwitchKey, header, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 其它入口（左滑菜单 / 设置页）可能改过状态，这里同步一下开关
    for (UIView *sub in header.subviews) {
        if ([sub isKindOfClass:[UISwitch class]]) {
            ((UISwitch *)sub).on = MMGroupIsCommon(userName);
        }
    }
    if (header && tableView && tableView.tableHeaderView != header) {
        CGRect frame = header.frame;
        frame.size.width = tableView.bounds.size.width;
        header.frame = frame;
        tableView.tableHeaderView = header;
    }
}

%new
- (UIView *)wczzGroupMakeCommonHeader:(NSString *)userName {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 52)];
    container.backgroundColor = [UIColor clearColor];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 220, 52)];
    label.text = @"设为常用群（不折叠）";
    label.font = [UIFont systemFontOfSize:16.0];
    [container addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = MMGroupIsCommon(userName);
    sw.tag = 7001;
    [sw addTarget:self action:@selector(wczzGroupCommonChanged:) forControlEvents:UIControlEventValueChanged];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [sw.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [sw.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
    ]];
    return container;
}

%new
- (void)wczzGroupCommonChanged:(UISwitch *)sender {
    NSString *userName = WCZZValue(WCZZValue(self, @"m_chatRoomContact"), @"m_nsUserName");
    if (!MMGroupIsGroupUserName(userName)) return;
    MMGroupSetCommon(userName, sender.isOn);   // 会话列表下次刷新时会自动重算分组
}

%new
- (UITableView *)wczzGroupFindTableView:(UIView *)root {
    if (!root) return nil;
    if ([root isKindOfClass:[UITableView class]]) return (UITableView *)root;
    for (UIView *sub in root.subviews) {
        UITableView *found = [self wczzGroupFindTableView:sub];
        if (found) return found;
    }
    return nil;
}

%end

%end

#pragma mark - Plugin registration / delayed hook installation

static BOOL WCZZRegistered = NO;
static BOOL WCZZRedHooksStarted = NO;
static BOOL WCZZMenuHooksStarted = NO;
static BOOL WCZZGroupHooksStarted = NO;
static NSInteger WCZZInstallAttempts = 0;

static void WCZZRegisterPlugin(void) {
    if (WCZZRegistered) return;
    Class c = objc_getClass("WCPluginsMgr");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL reg = NSSelectorFromString(@"registerControllerWithTitle:version:controller:");
    if (!c || ![c respondsToSelector:shared]) return;
    id mgr = ((id (*)(id, SEL))objc_msgSend)(c, shared);
    if (!mgr || ![mgr respondsToSelector:reg]) return;
    #ifdef PACKAGE_VERSION
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(mgr, reg, @"WCZZ", PACKAGE_VERSION, @"WCZZSettingsViewController");
#else
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(mgr, reg, @"WCZZ", @"0.1-1", @"WCZZSettingsViewController");
#endif
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
        // 群助手：Logos 部分只依赖主界面类（你项目头文件里已验证存在）；
        // 会话管理器的钩子单独探测安装，装在哪个候选类上会写进「诊断信息」。
        if (!WCZZGroupHooksStarted && objc_getClass("NewMainFrameViewController")) {
            %init(WCZZGroupHooks);
            WCZZGroupHooksStarted = YES;
            WCZZLog(@"group hooks installed");
        }
        MMGroupInstallSessionListHook();
        WCZZRegisterPlugin();
        if ((!WCZZRedHooksStarted || !WCZZMenuHooksStarted || !WCZZGroupHooksStarted || !WCZZRegistered) && WCZZInstallAttempts++ < 60) {
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
