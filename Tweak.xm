#import "WeChatCompat.h"
#import "WeChatHeaders.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"
#import "MessageMenuSettingsController.h"
#import "GroupHelperConfig.h"
#import "GroupHelperCompat.h"
#import "GroupHelperSessionPickerController.h"
#import <objc/runtime.h>
#import <objc/message.h>

// 底栏液态玻璃（WCZZTabBarGlass.xm）
BOOL WCZZTabBarGlassEnabled(void);
void WCZZSetTabBarGlassEnabled(BOOL enabled);

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <stdarg.h>

// %new 方法的声明（实现在 WCZZGroupHooks 里）。注意：这个类只在这里声明类别 ——
// 它的完整 @interface 在 WeChatCompat.h 里，GroupHelperConfig.m 那个编译单元看不到它，
// 所以不能把类别放进 GroupHelperCompat.h（会报 cannot define category for undefined class）。
@interface NewMainFrameViewController (WCZZGroupHelper)
- (void)wczzGroupSetInside:(BOOL)inside;
- (void)wczzGroupExitInside;
- (void)wczzGroupPushRoomHelper;
- (void)wczzGroupApplyInsideChrome;
- (void)wczzGroupRestoreSearchBar;
@property (nonatomic, assign) BOOL inRoomList;   // MiYou 注入的同名属性
@end

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
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 2) return 11;
    return 1;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 28.0; }
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)section { return section == 0 ? 8.0 : 0.01; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"红包";
    if (section == 1) return @"消息";
    if (section == 2) return @"群助手";
    return @"外观";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    return nil;   // 页脚会和最后一行重叠，说明文字放到行内了
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
        c.textLabel.text=@"群助手"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=MMGroupRuntimeStatus(); c.detailTextLabel.font=[UIFont systemFontOfSize:12.0];
        UISwitch *sw=[UISwitch new]; sw.tag=200; sw.on=MMGroupIsEnabled(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 1) {
        c.textLabel.text=@"显示群助手入口"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *sw=[UISwitch new]; sw.tag=201; sw.on=MMGroupShowHelper(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 2) {
        c.textLabel.text=@"入口置顶"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *sw=[UISwitch new]; sw.tag=202; sw.on=MMGroupHelperTop(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 3) {
        c.textLabel.text=@"所有群聊自动加入"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=MMGroupAutoAllGroups()?@"含全部群":@"仅名单";
        UISwitch *sw=[UISwitch new]; sw.tag=204; sw.on=MMGroupAutoAllGroups(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 4) {
        c.textLabel.text=@"未读样式"; c.detailTextLabel.text=(MMGroupHelperIncoType()==1)?@"红点":@"数字";
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 5) {
        c.textLabel.text=@"群助手名称"; c.detailTextLabel.text=MMGroupHelperTitle();
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 6) {
        c.textLabel.text=@"密群列表";
        c.detailTextLabel.text=[NSString stringWithFormat:@"已选 %lu 个群", (unsigned long)[MMGroupRoomList() count]];
        c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 7) {
        c.textLabel.text=@"诊断信息（可复制）"; c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 2 && ip.row == 8) {
        c.textLabel.text=@"调试日志"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        UISwitch *sw=[UISwitch new]; sw.tag=203; sw.on=MMGroupDebugEnabled(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2 && ip.row == 9) {
        c.textLabel.text=@"用微信原生多选界面"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=MMGroupUseNativePicker()?@"开（原版）":@"关（自建列表）";
        UISwitch *sw=[UISwitch new]; sw.tag=205; sw.on=MMGroupUseNativePicker(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 2) {
        c.textLabel.text=@"原版入口方式（push）"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=MMGroupUseOriginalEntry()?@"开（原版）":@"关（原地切换）";
        UISwitch *sw=[UISwitch new]; sw.tag=206; sw.on=MMGroupUseOriginalEntry(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    } else if (ip.section == 3) {
        c.textLabel.text=@"底栏液态玻璃"; c.selectionStyle=UITableViewCellSelectionStyleNone;
        c.detailTextLabel.text=WCZZTabBarGlassEnabled()?@"开":@"关";
        UISwitch *sw=[UISwitch new]; sw.tag=300; sw.on=WCZZTabBarGlassEnabled(); [sw addTarget:self action:@selector(wczzMain:) forControlEvents:UIControlEventValueChanged];
        sw.translatesAutoresizingMaskIntoConstraints=NO; [c.contentView addSubview:sw];
        [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor]]];
    }
    return c;
}
- (void)wczzMain:(UISwitch *)sw {
    if (sw.tag == 100) WCZZSetBool(WCZZRedDetailKey, sw.on);
    if (sw.tag == 300) { WCZZSetTabBarGlassEnabled(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 200) { MMGroupSetEnabled(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 201) { MMGroupSetShowHelper(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 202) { MMGroupSetHelperTop(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 203) MMGroupSetDebugEnabled(sw.on);
    if (sw.tag == 204) { MMGroupSetAutoAllGroups(sw.on); MMGroupForceReloadSessions(); [self.tableView reloadData]; }
    if (sw.tag == 205) { MMGroupSetUseNativePicker(sw.on); [self.tableView reloadData]; }
    if (sw.tag == 206) { MMGroupSetUseOriginalEntry(sw.on); [self.tableView reloadData]; }
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self.navigationController pushViewController:[MessageMenuSettingsController new] animated:YES];
    if (ip.section == 2 && ip.row == 4) {
        MMGroupSetHelperIncoType(MMGroupHelperIncoType() == 1 ? 0 : 1);
        [tv reloadData];
    }
    if (ip.section == 2 && ip.row == 5) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群助手名称"
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
    if (ip.section == 2 && ip.row == 6) {
        GroupHelperSessionPickerController *picker =
            [[GroupHelperSessionPickerController alloc] initWithMode:GroupHelperPickerModeRoomList
                                                          completion:^(NSUInteger count) {
            (void)count;
            [tv reloadData];
        }];
        [self.navigationController pushViewController:picker animated:YES];
    }
    if (ip.section == 2 && ip.row == 7) {
        NSString *report = nil;
        @try { report = MMGroupDiagnostics(); } @catch (NSException *exception) { report = nil; }
        if (![report isKindOfClass:[NSString class]] || !report.length) {
            report = @"诊断采集失败（已捕获异常，未影响微信）";
        }
        // 保底：同时写到微信沙盒 Documents/wczz_group_diag.txt（弹窗出问题也能取到）
        @try {
            NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            NSString *path = [dir stringByAppendingPathComponent:@"wczz_group_diag.txt"];
            [report writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSLog(@"[WCZZ/群助手] 诊断已写入: %@", path);
        } @catch (__unused NSException *e) {}
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"群助手诊断"
                                                                       message:report
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            @try { [UIPasteboard generalPasteboard].string = report; } @catch (__unused NSException *e) {}
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        @try { [self presentViewController:alert animated:YES completion:nil]; } @catch (__unused NSException *e) {}
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
    // 实测（MiYou -checkTableViewEditingStyle）：cell.m_cellData.m_sessionInfo.m_nsUserName
    if (!cell) return nil;
    id cellData = WCZZValue(cell, @"m_cellData");
    id sessionInfo = WCZZValue(cellData, @"m_sessionInfo");
    NSString *userName = MMGroupUserNameOfSession(sessionInfo);
    if (![userName isKindOfClass:[NSString class]] || !userName.length) {
        userName = MMGroupUserNameOfSession(cellData);
    }
    if (![userName isKindOfClass:[NSString class]] || !userName.length) {
        userName = WCZZValue(cell, @"m_nsUserName") ?: WCZZValue(cell, @"userName");
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
    return MMGroupIsHelperSession(MMGroupUserNameOfSession(WCZZGroupSessionAtIndexPath(mainFrame, indexPath)));
}

// 组内视图：把会话列表顶部的搜索框藏起来（MiYou 的组内页面没有搜索框），退出时还原
static UISearchBar *WCZZGroupFindSearchBar(UIView *root, NSInteger depth) {
    if (!root || depth > 12) return nil;
    if ([root isKindOfClass:[UISearchBar class]]) return (UISearchBar *)root;
    for (UIView *sub in root.subviews) {
        UISearchBar *found = WCZZGroupFindSearchBar(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

// associated object keys（标题 / 左侧按钮，进入组内视图时保存原值）
static const void *WCZZGroupTitleKey = &WCZZGroupTitleKey;
static const void *WCZZGroupLeftItemKey = &WCZZGroupLeftItemKey;
static const void *WCZZGroupSearchBarKey = &WCZZGroupSearchBarKey;
static const void *WCZZGroupSearchContainerKey = &WCZZGroupSearchContainerKey;

%group WCZZGroupHooks

// 会话列表面板的钩子不在这里：会话管理器的类名各版本不同，改用
// GroupHelperConfig 里的运行时安装（MMGroupInstallSessionListHook，候选类名探测）。

// 点「群助手」那一行 → 进插件自己的列表页（不交给微信）。
%hook NewMainFrameViewController

- (void)tableView:(id)tableView didSelectRowAtIndexPath:(id)indexPath {
    // 原版：logic = [self valueForKey:@"m_mainFrameLogicController"]; session = [logic getSessionInfoAtIndexPath:indexPath];
    //       if (session.m_nsUserName == "MGRoomHelper") { push 组内页面; return; }
    // 这里两层都解析一遍（逻辑层优先），保证和显示映射完全一致，避免行号错位。
    if (MMGroupIsEnabled()) {
        id logic = WCZZValue(self, @"m_mainFrameLogicController");
        SEL logicSel = NSSelectorFromString(@"getSessionInfoAtIndexPath:");
        if (logic && [logic respondsToSelector:logicSel]) {
            id session = ((id (*)(id, SEL, id))objc_msgSend)(logic, logicSel, indexPath);
            if (MMGroupIsHelperSession(MMGroupUserNameOfSession(session))) {
                if ([MMGroupRoomList() count]) [self wczzGroupPushRoomHelper];
                return;
            }
        }
        SEL vcSel = NSSelectorFromString(@"logicGetSessionAtIndexPath:");
        if ([self respondsToSelector:vcSel]) {
            id session = ((id (*)(id, SEL, id))objc_msgSend)(self, vcSel, indexPath);
            if (MMGroupIsHelperSession(MMGroupUserNameOfSession(session))) {
                if ([MMGroupRoomList() count]) [self wczzGroupPushRoomHelper];
                return;
            }
        }
    }
    %orig;
}

%new
- (void)wczzGroupPushRoomHelper {
    // 原版（MiYou -[NewMainFrameViewController tableView:didSelectRowAtIndexPath:] 实测）：
    //   vc = [[NewMainFrameViewController alloc] init];
    //   vc.m_nsTitle = @"微信群助手"; vc.hidesBottomBarWhenPushed = YES; vc.inRoomList = @YES;
    //   [cfg setIsOpenInRoom:NO]; [cfg setIsOpenRoomHelper:YES];
    //   [[self navigationController] PushViewController:vc animated:YES];
    // 裸实例在 8.0.79 上会因缺少数据源而空页面/闪退，所以这里补三步：
    //   ① 把当前主界面的 logic controller 拷过去 ② 保证有「返回」项 ③ 失败就退回原地切换
    MMGroupSetInsideHelper(YES);
    Class vcClass = MMGroupUseOriginalEntry() ? objc_getClass("NewMainFrameViewController") : Nil;
    UIViewController *vc = vcClass ? [[vcClass alloc] init] : nil;
    if (vc) {
        @try {
            id logic = WCZZValue(self, @"m_mainFrameLogicController");
            if (logic && !WCZZValue(vc, @"m_mainFrameLogicController")) {
                [vc setValue:logic forKey:@"m_mainFrameLogicController"];
            }
            for (NSString *key in @[@"m_tableViewMgr", @"m_tableViewInfo", @"m_logicController"]) {
                id value = WCZZValue(self, key);
                if (value && !WCZZValue(vc, key)) {
                    @try { [vc setValue:value forKey:key]; } @catch (__unused NSException *e) {}
                }
            }
            [vc setValue:MMGroupHelperTitle() forKey:@"m_nsTitle"];
            [vc setValue:@(YES) forKey:@"inRoomList"];
            vc.hidesBottomBarWhenPushed = YES;
        } @catch (NSException *exception) {
            MMGroupLog(@"push 前配置异常（仍继续）: %@", exception);
        }
    }
    if (vc && self.navigationController) {
        @try {
            [self.navigationController pushViewController:vc animated:YES];
            // 保证能返回：打开侧滑返回手势 + 兜底左按钮
            if (@available(iOS 7.0, *)) {
                self.navigationController.interactivePopGestureRecognizer.enabled = YES;
            }
            if (!vc.navigationItem.leftBarButtonItem && vc.navigationItem.leftBarButtonItem != nil) {
                // 理论上不需要；保险起见保证能返回
            }
            if (!vc.navigationItem.leftBarButtonItem && !vc.navigationItem.hidesBackButton) {
                vc.navigationItem.leftBarButtonItem =
                    [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain
                                                    target:vc action:@selector(wczzGroupExitInside)];
            }
            MMGroupLog(@"已按原版方式 push 新的会话列表页");
            return;
        } @catch (NSException *exception) {
            MMGroupLog(@"push 失败，退回原地切换: %@", exception);
        }
    }
    // 原地切换（标题 + 返回 + 藏搜索框）
    @try {
        [self setValue:MMGroupHelperTitle() forKey:@"m_nsTitle"];
        [self setValue:@(YES) forKey:@"inRoomList"];
    } @catch (__unused NSException *e) {}
    objc_setAssociatedObject(self, WCZZGroupTitleKey, self.navigationItem.title,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, WCZZGroupLeftItemKey, self.navigationItem.leftBarButtonItem,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self wczzGroupApplyInsideChrome];
    MMGroupForceReloadSessions();
    // 微信可能会在之后重设导航栏/搜索框，过一小会儿再压一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self wczzGroupApplyInsideChrome];
    });
}

%new
- (void)wczzGroupApplyInsideChrome {
    self.navigationItem.title = MMGroupHelperTitle();
    self.navigationItem.hidesBackButton = NO;
    UINavigationController *nav = self.navigationController;
    BOOL pushedPage = nav && nav.viewControllers.count > 1 && nav.viewControllers.firstObject != self;
    if (!self.navigationItem.leftBarButtonItem ||
        ![self.navigationItem.leftBarButtonItem.target isEqual:self]) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain
                                            target:self action:@selector(wczzGroupExitInside)];
    }
    if (pushedPage) return;

    // 原地模式：藏掉搜索框（保存原状态，退出时还原）
    UISearchBar *bar = WCZZGroupFindSearchBar(self.view, 0);
    if (bar && !bar.hidden) {
        objc_setAssociatedObject(self, WCZZGroupSearchBarKey, bar, OBJC_ASSOCIATION_ASSIGN);
        bar.hidden = YES;
        UIView *container = bar.superview;
        if (container && container != self.view) {
            objc_setAssociatedObject(self, WCZZGroupSearchContainerKey, container, OBJC_ASSOCIATION_ASSIGN);
            container.hidden = YES;
        }
        MMGroupLog(@"组内视图：已隐藏搜索框");
    }
}

%new
- (void)wczzGroupRestoreSearchBar {
    UIView *container = objc_getAssociatedObject(self, WCZZGroupSearchContainerKey);
    UISearchBar *bar = objc_getAssociatedObject(self, WCZZGroupSearchBarKey);
    if (container) container.hidden = NO;
    if (bar) bar.hidden = NO;
    objc_setAssociatedObject(self, WCZZGroupSearchContainerKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(self, WCZZGroupSearchBarKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

%new
- (void)wczzGroupSetInside:(BOOL)inside {
    MMGroupSetInsideHelper(inside);
    if (inside) {
        @try { [self setValue:MMGroupHelperTitle() forKey:@"m_nsTitle"]; } @catch (__unused NSException *e) {}
        self.hidesBottomBarWhenPushed = YES;
    }
    MMGroupForceReloadSessions();
}

%new
- (void)wczzGroupExitInside {
    MMGroupSetInsideHelper(NO);
    @try { [self setValue:@(NO) forKey:@"inRoomList"]; } @catch (__unused NSException *e) {}
    UINavigationController *nav = self.navigationController;
    if (nav && nav.viewControllers.count > 1 && nav.viewControllers.firstObject != self) {
        [nav popViewControllerAnimated:YES];      // 原版是 push 进来的 → 返回就是 pop
        return;
    }
    NSString *title = objc_getAssociatedObject(self, WCZZGroupTitleKey);
    self.navigationItem.title = title.length ? title : @"微信";
    self.navigationItem.leftBarButtonItem = objc_getAssociatedObject(self, WCZZGroupLeftItemKey);
    [self wczzGroupRestoreSearchBar];
    MMGroupForceReloadSessions();
}

%new
- (BOOL)inRoomList {
    return MMGroupIsInsideHelper();
}

%new
- (void)setInRoomList:(BOOL)inRoomList {
    [self wczzGroupSetInside:inRoomList];
}

- (void)viewDidLoad {
    %orig;
    MMGroupInstallViewHooks();
    MMGroupForceReloadSessions();
}

// 实测复刻 -[NewMainFrameViewController viewWillAppear:]（IMP 0x4cfb2c）
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!MMGroupIsEnabled()) return;
    if (MMGroupIsInsideHelper()) {
        @try { [self setValue:MMGroupHelperTitle() forKey:@"m_nsTitle"]; } @catch (__unused NSException *e) {}
        [self wczzGroupApplyInsideChrome];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self wczzGroupApplyInsideChrome];
        });
    }
    MMGroupForceReloadSessions();
}

- (id)m_nsTitle {
    id title = %orig;
    if (MMGroupIsInsideHelper()) return MMGroupHelperTitle();
    return title;
}

// push 进来的组内页面在消失时退出组内模式
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (MMGroupIsInsideHelper() && self.navigationController.viewControllers.count <= 1) {
        MMGroupSetInsideHelper(NO);
    }
}

// 实测复刻 -[NewMainFrameViewController viewDidPop:]（IMP 0x4cf054）
- (void)viewDidPop:(id)sender {
    %orig;
    if (!MMGroupIsEnabled()) return;
    self.hidesBottomBarWhenPushed = YES;
    MMGroupSetInsideHelper(NO);
    MMGroupForceReloadSessions();
}

- (void)mmSearchBarTextDidChange:(id)text {
    %orig;
    if (MMGroupIsEnabled()) MMGroupForceReloadSessions();
}

- (BOOL)shouldMiniTaskGestureBegin {
    return %orig;
}

- (void)checkAndUpdateLeftNavBarItemForMiniTaskEntry {
    %orig;
}

- (void)notifyMiniTaskEntryWhenViewWillDisappear {
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

// MiYou：deleteSessionAtIndex: 里拦掉入口行
- (void)deleteSessionAtIndex:(long long)index {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    if (MMGroupIsEnabled() && WCZZGroupIsHelperIndexPath(self, indexPath)) return;
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

- (BOOL)gestureRecognizerShouldBegin:(id)gesture {
    if (MMGroupIsEnabled() && MMGroupIsHelperSession(WCZZGroupUserNameOfCell(self))) return NO;
    return %orig;
}

%end

// cell 数据：入口会话拿不到联系人，这里把结果打出来（出问题看日志/诊断）
%hook MainFrameCellDataManager

- (id)getCellDataByUsrName:(id)userName {
    id data = %orig;
    MMGroupNoteCellDataManagerCall(userName, data);   // 记进诊断：微信到底按哪个 username 取 cellData
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

// MiYou 在 MMNewSessionMgr 上还挂了这三个（GroupTool.isOpenRoomEnable 分支）
%hook MMNewSessionMgr

- (long long)GetTotalUnreadCount {
    long long total = %orig;
    MMGroupLog(@"GetTotalUnreadCount = %lld", total);
    return total;
}

- (long long)GetTotalUnreadCountForAppIcon {
    long long total = %orig;
    MMGroupLog(@"GetTotalUnreadCountForAppIcon = %lld", total);
    return total;
}

// 老版本微信有这个；入口行不允许被删除
- (void)DeleteSessionAtIndex:(long long)index {
    %orig;
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
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;

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
            ((UISwitch *)sub).on = MMGroupIsInRoomList(userName);
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
    label.text = @"加入群助手（收进群助手）";
    label.font = [UIFont systemFontOfSize:16.0];
    [container addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = MMGroupIsInRoomList(userName);
    sw.tag = 7001;
    [sw addTarget:self action:@selector(settingFilterRoom:) forControlEvents:UIControlEventValueChanged];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [sw.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [sw.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
    ]];
    return container;
}

%new
- (void)settingFilterRoom:(UISwitch *)sender {
    NSString *userName = WCZZValue(WCZZValue(self, @"m_chatRoomContact"), @"m_nsUserName");
    if (![userName hasSuffix:@"@chatroom"]) return;   // 只对群聊显示
    MMGroupSetInRoomList(userName, sender.isOn);   // 加入/移出 RoomList
    MMGroupForceReloadSessions();
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
            // 钩子装好立刻压几次刷新，避免「进微信要等一会才出现群助手」
            for (NSNumber *delayNum in @[@0.1, @0.6, @1.6]) {
                double delay = [delayNum doubleValue];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    MMGroupForceReloadSessions();
                });
            }
        }
        MMGroupInstallSessionListHook();
        // 微信列表实际读的是主界面的行缓存 → 必须在视图层也做一次映射
        MMGroupInstallViewHooks();
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
