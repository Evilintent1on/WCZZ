#import "ShareMenuSettingsController.h"
#import "ShareMenuConfig.h"

// ============================================================
//  设置页：分享面板项目（逐项开关）
//
//  体验与「长按菜单」设置一致：把抓到的项目全列出来，开关控制是否在面板里显示。
//    开关开 = 显示；关 = 隐藏（下次打开面板即生效，若面板正开着会立刻应用）
//  右上角：重新抓取（抓当前面板）/ 抓取详情（原始视图树，排查用）
// ============================================================

@implementation ShareMenuSettingsController {
    NSMutableArray<NSDictionary *> *_entries;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.title = @"分享面板";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }
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
    if (!ip || ip.row >= (NSInteger)_entries.count) return;

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
    if (indexPath.section == 1) {
        static NSString *optId = @"wczz.share.opt";
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:optId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:optId];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            [sw addTarget:self action:@selector(onToggleSkipFirst:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        cell.textLabel.text = @"不抓「转发给」好友行";
        ((UISwitch *)cell.accessoryView).on = WCZZShareMenuSkipsFirstRow();
        return cell;
    }
    static NSString *cid = @"wczz.share.cell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(onToggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    }
    NSDictionary *entry = _entries[(NSUInteger)indexPath.row];
    NSString *title = entry[WCZZShareMenuTitleKey];
    NSInteger seen = [entry[WCZZShareMenuSeenKey] integerValue];
    cell.textLabel.text = [title isKindOfClass:[NSString class]] ? title : @"(?)";
    cell.detailTextLabel.text = seen > 1 ? [NSString stringWithFormat:@"%ld", (long)seen] : nil;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    UISwitch *sw = (UISwitch *)cell.accessoryView;
    sw.on = ![entry[WCZZShareMenuHiddenKey] boolValue];      // 开 = 显示
    return cell;
}

@end
