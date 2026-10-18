#import "ShareMenuSettingsController.h"
#import "ShareMenuConfig.h"
#import <QuartzCore/QuartzCore.h>

// ============================================================
//  设置页：分享面板（逐项开关）
//
//  外观与「长按菜单」设置页一致：Grouped 表 + 每行自绘白色圆角卡片背景，
//  开关放在 contentView 里（放 accessoryView 会露出灰底）。
//    开关开 = 显示；关 = 隐藏（下次打开面板即生效，若面板正开着会立刻应用）
//  右上角：重新抓取（抓当前面板）/ 抓取详情（原始视图树，排查用）
// ============================================================

#pragma mark - Card background (same style as MessageMenu settings)

@interface SMCardBgView : UIView
@property (nonatomic, assign) UIRectCorner corners;
@property (nonatomic, assign) BOOL showSeparator;
@property (nonatomic, strong) UIColor *cardColor;
@end

@implementation SMCardBgView
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
    card.frame = CGRectMake(inset, 0, self.bounds.size.width - inset * 2, self.bounds.size.height);
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

static void SMApplyCard(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip) {
    NSInteger rows = [tv numberOfRowsInSection:ip.section];
    UIRectCorner corners;
    if (ip.row == 0 && ip.row == rows - 1) corners = UIRectCornerAllCorners;
    else if (ip.row == 0) corners = UIRectCornerTopLeft | UIRectCornerTopRight;
    else if (ip.row == rows - 1) corners = UIRectCornerBottomLeft | UIRectCornerBottomRight;
    else corners = 0;
    BOOL showSep = (ip.row < rows - 1);
    SMCardBgView *bg = [[SMCardBgView alloc] init];
    bg.backgroundColor = [UIColor clearColor];
    bg.corners = corners;
    bg.showSeparator = showSep;
    cell.backgroundView = bg;
    SMCardBgView *selBg = [[SMCardBgView alloc] init];
    selBg.backgroundColor = [UIColor clearColor];
    selBg.corners = corners;
    selBg.showSeparator = showSep;
    if (@available(iOS 13.0, *)) selBg.cardColor = [UIColor systemGray5Color];
    else selBg.cardColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    cell.selectedBackgroundView = selBg;
    cell.backgroundColor = [UIColor clearColor];
}

#pragma mark - Controller

@implementation ShareMenuSettingsController {
    NSMutableArray<NSDictionary *> *_entries;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = @"分享面板";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = 55;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(onResetAll)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"重新抓取" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(onRescan)],
        [[UIBarButtonItem alloc] initWithTitle:@"抓取详情" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(onDetail)],
    ];
    [self reloadEntries];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

- (void)reloadEntries {
    _entries = [WCZZShareMenuLoadEntries() mutableCopy];
    [self.tableView reloadData];
}

#pragma mark - 动作

- (void)onResetAll {
    WCZZShareMenuResetAll();
    [self reloadEntries];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已清空"
                                                              message:@"列表已清空；下次打开分享面板会重新抓取。"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)onRescan {
    NSInteger added = WCZZShareMenuCaptureOpenSheet();
    if (added < 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"没有打开的面板"
                                                                  message:@"先打开一次分享/转发面板，再点「重新抓取」。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    WCZZShareMenuApplyOpenSheet();
    [self reloadEntries];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已重新抓取"
                                                              message:[NSString stringWithFormat:
                                                                       @"新增 %ld 项，当前共 %lu 项",
                                                                       (long)added,
                                                                       (unsigned long)_entries.count]
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)onDetail {
    NSString *dump = WCZZShareMenuDebugDump();
    UIViewController *vc = [[UIViewController alloc] init];
    vc.title = @"抓取详情";
    vc.view.backgroundColor = [UIColor systemBackgroundColor];
    // 用文本视图展示（可滚动可复制）
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.selectable = YES;
    tv.alwaysBounceVertical = YES;
    tv.font = [UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightRegular];
    tv.text = dump;
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)onToggleSkipFirst:(UISwitch *)sw {
    WCZZShareMenuSetSkipsFirstRow(sw.on);
}

- (void)onToggle:(UISwitch *)sw {
    UIView *v = sw;
    while (v && ![v isKindOfClass:[UITableViewCell class]]) v = v.superview;
    UITableViewCell *cell = (UITableViewCell *)v;
    if (!cell) return;
    NSIndexPath *ip = [self.tableView indexPathForCell:cell];
    if (!ip || ip.section != 0 || ip.row >= (NSInteger)_entries.count) return;

    NSDictionary *entry = _entries[(NSUInteger)ip.row];
    NSString *title = entry[WCZZShareMenuTitleKey];
    if (![title isKindOfClass:[NSString class]]) return;

    WCZZShareMenuSetTitleHidden(title, !sw.on);   // 关 = 隐藏
    // 面板正开着就立刻应用
    WCZZShareMenuApplyOpenSheet();
    [self reloadEntries];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == 1) return 1;                 // 选项：不抓好友行
    return (NSInteger)_entries.count;
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section { return 28.0; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"抓取范围";
    return _entries.count ? @"开关：开 = 显示，关 = 隐藏" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    if (section == 1) return @"关掉「不抓好友行」后，重新抓取会把「转发给」里的好友也列进来。";
    if (_entries.count) return @"打开一次分享/转发面板会自动抓取新项目；改完立即生效。";
    return @"还没有抓到项目：先打开一次分享/转发面板，再回到这里。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isOption = (indexPath.section == 1);
    NSString *cid = isOption ? @"wczz.share.opt" : @"wczz.share.cell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    for (UIView *v in [cell.contentView.subviews copy]) {
        if ([v isKindOfClass:[UISwitch class]]) [v removeFromSuperview];
    }
    SMApplyCard(cell, tv, indexPath);
    cell.layoutMargins = UIEdgeInsetsMake(0, 32, 0, 16);

    UISwitch *sw = [UISwitch new];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:sw];
    [NSLayoutConstraint activateConstraints:@[
        [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-32],
        [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
    ]];

    if (isOption) {
        cell.textLabel.text = @"不抓「转发给」好友行";
        sw.on = WCZZShareMenuSkipsFirstRow();
        [sw addTarget:self action:@selector(onToggleSkipFirst:) forControlEvents:UIControlEventValueChanged];
    } else {
        NSDictionary *entry = _entries[(NSUInteger)indexPath.row];
        NSString *title = entry[WCZZShareMenuTitleKey];
        cell.textLabel.text = [title isKindOfClass:[NSString class]] ? title : @"(?)";
        sw.on = ![entry[WCZZShareMenuHiddenKey] boolValue];      // 开 = 显示
        [sw addTarget:self action:@selector(onToggle:) forControlEvents:UIControlEventValueChanged];
    }
    return cell;
}

@end
