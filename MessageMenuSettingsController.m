#import "MessageMenuSettingsController.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Card background (25pt radius)

@interface MMCardBgView : UIView
@property (nonatomic, assign) UIRectCorner corners;
@property (nonatomic, assign) BOOL showSeparator;
@property (nonatomic, strong) UIColor *cardColor;

@end
@implementation MMCardBgView
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

static void MMApplyCard(UITableViewCell *cell, UITableView *tv, NSIndexPath *ip) {
    NSInteger rows = [tv numberOfRowsInSection:ip.section];
    UIRectCorner corners;
    if (ip.row == 0 && ip.row == rows-1) corners = UIRectCornerAllCorners;
    else if (ip.row == 0) corners = UIRectCornerTopLeft|UIRectCornerTopRight;
    else if (ip.row == rows-1) corners = UIRectCornerBottomLeft|UIRectCornerBottomRight;
    else corners = 0;
    BOOL showSep = (ip.row < rows-1);
    MMCardBgView *bg = [[MMCardBgView alloc] init];
    bg.backgroundColor = [UIColor clearColor];
    bg.corners = corners;
    bg.showSeparator = showSep;
    cell.backgroundView = bg;
    MMCardBgView *selBg = [[MMCardBgView alloc] init];
    selBg.backgroundColor = [UIColor clearColor];
    selBg.corners = corners;
    selBg.showSeparator = showSep;
    if (@available(iOS 13.0, *)) selBg.cardColor = [UIColor systemGray5Color];
    else selBg.cardColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    cell.selectedBackgroundView = selBg;
    cell.backgroundColor = [UIColor clearColor];
}

// WeChat-native settings style: grouped table, white cells, system fonts,
// standard switches. No custom colors or icons.

typedef NS_ENUM(NSInteger, MMSection) {
    MMSectionGeneral = 0,
    MMSectionKept,
    MMSectionRemoved,
    MMSectionActions,
    MMSectionCount,
};

typedef NS_ENUM(NSInteger, MMActionRow) {
    MMActionRowRestoreDefaults = 0,
    MMActionRowCount,
};

#pragma mark - Helpers

static NSMutableArray<NSMutableDictionary *> *MMWCZZMutableEntries(NSArray<NSDictionary *> *entries) {
    NSMutableArray<NSMutableDictionary *> *result = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        if ([entry isKindOfClass:[NSDictionary class]]) {
            [result addObject:[entry mutableCopy]];
        }
    }
    return result;
}

static NSArray<NSDictionary *> *MMWCZZEntriesForRemoved(NSArray<NSDictionary *> *entries, BOOL removed) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        if ([entry[MMMenuEntryRemoveKey] boolValue] == removed) {
            [result addObject:entry];
        }
    }
    return [result copy];
}

static NSMutableOrderedSet<NSString *> *MMWCZZParseTitles(NSString *raw) {
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",，、;；\n\r"];
    NSMutableOrderedSet<NSString *> *titles = [NSMutableOrderedSet orderedSet];
    for (NSString *part in [raw componentsSeparatedByCharactersInSet:separators]) {
        NSString *title = MMMenuNormalizeTitle(part);
        if (!title) continue;
        if (title.length > 40) title = [title substringToIndex:40];
        [titles addObject:title];
    }
    return titles;
}

static NSMutableDictionary *MMWCZZEntryWithTitle(NSString *title, BOOL removed) {
    return [@{
        MMMenuEntryIdentifierKey: [NSString stringWithFormat:@"custom.%@", [[NSUUID UUID] UUIDString]],
        MMMenuEntryTitleKey:      title,
        MMMenuEntryRemoveKey:     @(removed),
        MMMenuEntryBuiltinKey:    @NO,
    } mutableCopy];
}

#pragma mark - Removed items controller

static UIBarButtonItem *MMBlackBackButton(UIViewController *vc, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImage *sysChevron = vc.navigationController.navigationBar.backIndicatorImage;
    UIColor *chevronColor = nil;
    if (@available(iOS 13.0, *)) chevronColor = [UIColor labelColor];
    else chevronColor = [UIColor blackColor];
    if (sysChevron) {
        [btn setImage:[sysChevron imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
        btn.tintColor = chevronColor;
    } else {
        CGSize size = CGSizeMake(12, 20);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
        UIBezierPath *p = [UIBezierPath bezierPath];
        CGFloat lw = 2.5;
        [p moveToPoint:CGPointMake(size.width - 1, 1)];
        [p addLineToPoint:CGPointMake(1, size.height / 2)];
        [p addLineToPoint:CGPointMake(size.width - 1, size.height - 1)];
        p.lineWidth = lw;
        p.lineCapStyle = kCGLineCapRound;
        p.lineJoinStyle = kCGLineJoinRound;
        [chevronColor setStroke];
        [p stroke];
        UIImage *chevron = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [btn setImage:chevron forState:UIControlStateNormal];
    }
    [btn addTarget:vc action:action forControlEvents:UIControlEventTouchUpInside];
    btn.frame = CGRectMake(0, 0, 30, 32);
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    return [[UIBarButtonItem alloc] initWithCustomView:btn];
}

@interface MMWCZZRemovedItemsController : UITableViewController
- (instancetype)initWithEntries:(NSMutableArray<NSMutableDictionary *> *)entries
                  changeHandler:(void (^)(void))changeHandler;
@end

@interface MMWCZZRemovedItemsController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *allEntries;
@property (nonatomic, copy) void (^changeHandler)(void);
@end

@implementation MMWCZZRemovedItemsController

- (void)mm_backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (instancetype)initWithEntries:(NSMutableArray<NSMutableDictionary *> *)entries
                  changeHandler:(void (^)(void))changeHandler {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _allEntries = entries;
        _changeHandler = [changeHandler copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"已移除菜单";
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = 55;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = MMBlackBackButton(self, @selector(mm_backTapped));
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }
}

- (NSArray<NSDictionary *> *)removedEntries {
    return MMWCZZEntriesForRemoved(self.allEntries ?: @[], YES);
}

- (void)didChange {
    if (self.changeHandler) self.changeHandler();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSInteger count = (NSInteger)[self removedEntries].count;
    return MAX(count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSDictionary *> *removed = [self removedEntries];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mm.removed"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"mm.removed"];
    MMApplyCard(cell, tableView, indexPath);
    cell.layoutMargins = UIEdgeInsetsMake(0, 32, 0, 16);
    if (!removed.count) {
        cell.textLabel.text = @"暂无已移除菜单";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *entry = removed[indexPath.row];
    cell.textLabel.text = entry[MMMenuEntryTitleKey];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.imageView.image = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray<NSDictionary *> *removed = [self removedEntries];
    if ((NSUInteger)indexPath.row >= removed.count) return;
    // Tap restores the item back to the kept list.
    NSMutableDictionary *entry = (NSMutableDictionary *)removed[indexPath.row];
    entry[MMMenuEntryRemoveKey] = @NO;
    [self didChange];
    [tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return (NSUInteger)indexPath.row < [self removedEntries].count;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSDictionary *> *removed = [self removedEntries];
    if ((NSUInteger)indexPath.row >= removed.count) return nil;
    NSDictionary *entry = removed[indexPath.row];
    BOOL builtin = [entry[MMMenuEntryBuiltinKey] boolValue];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction
        contextualActionWithStyle:(builtin ? UIContextualActionStyleNormal : UIContextualActionStyleDestructive)
                             title:(builtin ? @"恢复" : @"删除")
                           handler:^(UIContextualAction *a, UIView *view, void (^completion)(BOOL)) {
        (void)a; (void)view;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { if (completion) completion(NO); return; }
        NSUInteger idx = [self.allEntries indexOfObjectPassingTest:^BOOL(NSDictionary *c, NSUInteger i, BOOL *s) {
            (void)i; (void)s;
            return [c[MMMenuEntryIdentifierKey] isEqualToString:entry[MMMenuEntryIdentifierKey]];
        }];
        if (idx != NSNotFound) {
            if (builtin) {
                self.allEntries[idx][MMMenuEntryRemoveKey] = @NO;
            } else {
                [self.allEntries removeObjectAtIndex:idx];
            }
            [self didChange];
        }
        if (completion) completion(YES);
        dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

@end

#pragma mark - Main settings controller

@interface MessageMenuSettingsController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *entries;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL sortingEnabled;
@end

@implementation MessageMenuSettingsController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) [self reloadConfig];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"长按菜单";
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = 55;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    self.navigationItem.hidesBackButton = YES;
    self.navigationItem.leftBarButtonItem = MMBlackBackButton(self, @selector(mm_backTapped));
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    } else {
        self.tableView.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
        self.view.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0];
    }
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                     target:self
                                                     action:@selector(addTapped)];
    [self applyEditingState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadConfig];
    [self.tableView reloadData];
    [self applyEditingState];
}

- (void)mm_backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Config

- (void)reloadConfig {
    self.entries = MMWCZZMutableEntries(MMMenuLoadEntries());
    self.enabled = MMMenuIsEnabled();
    self.sortingEnabled = MMMenuIsSortingEnabled();
    self.navigationItem.rightBarButtonItem.enabled = self.enabled;
}

- (void)persistConfig {
    MMMenuSetEnabled(self.enabled);
    MMMenuSetSortingEnabled(self.sortingEnabled);
    MMMenuSaveEntries(self.entries);
    // NOTE: no separate plugin-manager registration; WCZZ owns the single entry.
}

- (void)configurationDidChange {
    self.navigationItem.rightBarButtonItem.enabled = self.enabled;
    [self persistConfig];
}

- (NSArray<NSDictionary *> *)keptEntries {
    return MMWCZZEntriesForRemoved(self.entries, NO);
}

- (NSArray<NSDictionary *> *)removedEntries {
    return MMWCZZEntriesForRemoved(self.entries, YES);
}

- (void)applyEditingState {
    [self.tableView setEditing:(self.enabled && self.sortingEnabled) animated:NO];
}

#pragma mark - Table data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return MMSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((MMSection)section) {
        case MMSectionGeneral:  return 2;
        case MMSectionKept:     return (NSInteger)[self keptEntries].count;
        case MMSectionRemoved:  return 1;
        case MMSectionActions:  return MMActionRowCount;
        default:                return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((MMSection)section) {
        case MMSectionKept:     return @"菜单项";
        case MMSectionRemoved:  return @"已移除";
        case MMSectionActions:  return nil;
        default:                return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if ((MMSection)section == MMSectionGeneral) {
        return @"关闭后长按消息显示微信原始菜单。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mm.cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"mm.cell"];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.userInteractionEnabled = YES;
    cell.showsReorderControl = NO;
    for (UIView *v in [cell.contentView.subviews copy]) { if ([v isKindOfClass:[UISwitch class]] || v.tag == 999 || v.tag == 998) [v removeFromSuperview]; }
    MMApplyCard(cell, tableView, indexPath);
    cell.layoutMargins = UIEdgeInsetsMake(0, 32, 0, 16);

    if (indexPath.section == MMSectionGeneral) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"启用长按菜单自定义";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.tag = 1;
            sw.on = self.enabled;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
        } else {
            cell.textLabel.text = @"自定义排序";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.tag = 2;
            sw.on = self.sortingEnabled;
            sw.enabled = self.enabled;
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
            if (!self.enabled) cell.textLabel.textColor = [UIColor secondaryLabelColor];
        }
        return cell;
    }

    if (indexPath.section == MMSectionKept) {
        NSArray<NSDictionary *> *kept = [self keptEntries];
        NSDictionary *entry = kept[indexPath.row];
        cell.imageView.image = nil;
        if (self.enabled && self.sortingEnabled) {
            cell.showsReorderControl = YES;
            // 排序模式：不用系统 textLabel（编辑模式下位置不可控），自建 label 精确定位
            cell.textLabel.text = nil;
            UILabel *titleLabel = [UILabel new];
            titleLabel.tag = 998;
            titleLabel.text = entry[MMMenuEntryTitleKey];
            titleLabel.textColor = [UIColor labelColor];
            titleLabel.font = [UIFont systemFontOfSize:17];
            titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:titleLabel];
            [NSLayoutConstraint activateConstraints:@[
                [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
            // 把系统排序按钮往左挪 16pt，避免贴边（layout 后执行）
            dispatch_async(dispatch_get_main_queue(), ^{
                for (UIView *sub in cell.subviews) {
                    if ([NSStringFromClass([sub class]) containsString:@"Reorder"]) {
                        sub.transform = CGAffineTransformMakeTranslation(-16, 0);
                        break;
                    }
                }
            });
        } else {
            cell.textLabel.text = entry[MMMenuEntryTitleKey];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.on = YES;
            sw.enabled = self.enabled;
            sw.accessibilityIdentifier = entry[MMMenuEntryIdentifierKey];
            [sw addTarget:self action:@selector(entrySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-32],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
        }
        if (!self.enabled) {
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.userInteractionEnabled = NO;
        }
        return cell;
    }

    if (indexPath.section == MMSectionRemoved) {
        cell.textLabel.text = @"已移除菜单";
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        // "X 项" centered at the switch's middle x (switch trailing -32, width 51).
        UILabel *countLabel = [UILabel new];
        countLabel.tag = 999;
        countLabel.text = [NSString stringWithFormat:@"%lu 项", (unsigned long)[self removedEntries].count];
        countLabel.textColor = [UIColor secondaryLabelColor];
        countLabel.font = [UIFont systemFontOfSize:15];
        countLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:countLabel];
        [NSLayoutConstraint activateConstraints:@[
            [countLabel.centerXAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-57.5],
            [countLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
        ]];
        if (!self.enabled) {
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.userInteractionEnabled = NO;
        }
        return cell;
    }

    // Actions
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    switch (indexPath.row) {
        case MMActionRowRestoreDefaults:
            cell.textLabel.text = @"恢复默认菜单";
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        default:
            break;
    }
    return cell;
}

#pragma mark - Table delegate / editing

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == MMSectionRemoved) {
        if (!self.enabled) return;
        __weak typeof(self) weakSelf = self;
        MMWCZZRemovedItemsController *vc = [[MMWCZZRemovedItemsController alloc]
            initWithEntries:self.entries changeHandler:^{
                __strong typeof(weakSelf) self = weakSelf;
                [self configurationDidChange];
                [self.tableView reloadData];
            }];
        [self.navigationController pushViewController:vc animated:YES];
        return;
    }
    if (indexPath.section == MMSectionActions) {
        switch (indexPath.row) {
            case MMActionRowRestoreDefaults: [self confirmRestoreDefaults]; break;
            default: break;
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == MMSectionKept &&
           self.enabled && self.sortingEnabled &&
           (NSUInteger)indexPath.row < [self keptEntries].count;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)source
      toIndexPath:(NSIndexPath *)destination {
    if (source.section != MMSectionKept || destination.section != MMSectionKept) return;
    NSArray<NSDictionary *> *kept = [self keptEntries];
    if ((NSUInteger)source.row >= kept.count ||
        (NSUInteger)destination.row >= kept.count ||
        source.row == destination.row) return;

    NSMutableArray<NSDictionary *> *ordered = [kept mutableCopy];
    NSDictionary *moving = ordered[source.row];
    [ordered removeObjectAtIndex:source.row];
    [ordered insertObject:moving atIndex:destination.row];

    NSUInteger next = 0;
    for (NSUInteger i = 0; i < self.entries.count; i++) {
        if (![self.entries[i][MMMenuEntryRemoveKey] boolValue] && next < ordered.count) {
            self.entries[i] = [ordered[next] mutableCopy];
            next++;
        }
    }
    [self configurationDidChange];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == MMSectionKept &&
           (NSUInteger)indexPath.row < [self keptEntries].count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != MMSectionKept ||
        (NSUInteger)indexPath.row >= [self keptEntries].count || !self.enabled) {
        return nil;
    }
    NSDictionary *entry = [self keptEntries][indexPath.row];
    BOOL builtin = [entry[MMMenuEntryBuiltinKey] boolValue];
    __weak typeof(self) weakSelf = self;
    UIContextualAction *action = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:(builtin ? @"移除" : @"删除")
                          handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        (void)a; (void)v;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { if (done) done(NO); return; }
        NSUInteger idx = [self.entries indexOfObjectPassingTest:^BOOL(NSDictionary *c, NSUInteger i, BOOL *s) {
            (void)i; (void)s;
            return [c[MMMenuEntryIdentifierKey] isEqualToString:entry[MMMenuEntryIdentifierKey]];
        }];
        if (idx != NSNotFound) {
            if (builtin) {
                self.entries[idx][MMMenuEntryRemoveKey] = @YES;
            } else {
                [self.entries removeObjectAtIndex:idx];
            }
            [self configurationDidChange];
        }
        if (done) done(YES);
        dispatch_async(dispatch_get_main_queue(), ^{ [self.tableView reloadData]; });
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[action]];
}

#pragma mark - Switches

- (void)switchChanged:(UISwitch *)sw {
    if (sw.tag == 1) {
        self.enabled = sw.on;
        if (!self.enabled) self.sortingEnabled = NO;
        [self configurationDidChange];
        [self.tableView reloadData];
        [self applyEditingState];
        return;
    }
    if (sw.tag == 2) {
        if (!self.enabled) { sw.on = NO; return; }
        self.sortingEnabled = sw.on;
        [self configurationDidChange];
        [self.tableView reloadData];
        [self applyEditingState];
    }
}

- (void)entrySwitchChanged:(UISwitch *)sw {
    // Switch is ON for kept items; turning it OFF moves the entry to removed.
    if (sw.on) return;
    NSString *identifier = sw.accessibilityIdentifier;
    if (!identifier.length) return;
    NSUInteger idx = [self.entries indexOfObjectPassingTest:^BOOL(NSDictionary *c, NSUInteger i, BOOL *s) {
        (void)i; (void)s;
        return [c[MMMenuEntryIdentifierKey] isEqualToString:identifier];
    }];
    if (idx != NSNotFound) {
        self.entries[idx][MMMenuEntryRemoveKey] = @YES;
        [self configurationDidChange];
        [self.tableView reloadData];
    }
}

#pragma mark - Add

- (void)addTapped {
    if (!self.enabled) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加菜单"
                                                                   message:@"多个标题可用逗号、顿号、分号或换行分隔。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"输入菜单标题";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSMutableOrderedSet<NSString *> *titles = MMWCZZParseTitles(alert.textFields.firstObject.text ?: @"");
        if (!titles.count) return;
        NSUInteger added = 0;
        for (NSString *title in titles) {
            NSUInteger idx = [self.entries indexOfObjectPassingTest:^BOOL(NSDictionary *e, NSUInteger i, BOOL *s) {
                (void)i; (void)s;
                return [e[MMMenuEntryTitleKey] isEqualToString:title];
            }];
            if (idx != NSNotFound) {
                if ([self.entries[idx][MMMenuEntryRemoveKey] boolValue]) {
                    self.entries[idx][MMMenuEntryRemoveKey] = @NO;
                    added++;
                }
                continue;
            }
            if (self.entries.count >= 100) break;
            [self.entries addObject:MMWCZZEntryWithTitle(title, NO)];
            added++;
        }
        if (added) {
            [self configurationDidChange];
            [self.tableView reloadData];
        }
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)confirmRestoreDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认菜单"
                                                                   message:@"将清除自定义菜单与排序，恢复默认配置。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.entries = MMWCZZMutableEntries(MMMenuDefaultEntries());
        self.enabled = YES;
        self.sortingEnabled = NO;
        [self configurationDidChange];
        [self.tableView reloadData];
        [self applyEditingState];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
