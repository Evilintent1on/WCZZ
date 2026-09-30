#import "MessageMenuSettingsController.h"
#import "MessageMenuConfig.h"
#import "MessageMenuBackup.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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
    MMActionRowBackup,
    MMActionRowRestore,
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

@interface MMWCZZRemovedItemsController : UITableViewController
- (instancetype)initWithEntries:(NSMutableArray<NSMutableDictionary *> *)entries
                  changeHandler:(void (^)(void))changeHandler;
@end

@interface MMWCZZRemovedItemsController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *allEntries;
@property (nonatomic, copy) void (^changeHandler)(void);
@end

@implementation MMWCZZRemovedItemsController

- (instancetype)initWithEntries:(NSMutableArray<NSMutableDictionary *> *)entries
                  changeHandler:(void (^)(void))changeHandler {
    if (@available(iOS 13.0, *)) {
        self = [super initWithStyle:UITableViewStyleInsetGrouped];
    } else {
        self = [super initWithStyle:UITableViewStyleGrouped];
    }
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
    if (!removed.count) {
        cell.textLabel.text = @"暂无已移除菜单";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    cell.textLabel.text = removed[indexPath.row][MMMenuEntryTitleKey];
    cell.textLabel.textColor = [UIColor labelColor];
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

@interface MessageMenuSettingsController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *entries;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL sortingEnabled;
@property (nonatomic, assign) BOOL creatingBackup;
@end

@implementation MessageMenuSettingsController

- (instancetype)init {
    if (@available(iOS 13.0, *)) {
        self = [super initWithStyle:UITableViewStyleInsetGrouped];
    } else {
        self = [super initWithStyle:UITableViewStyleGrouped];
    }
    if (self) [self reloadConfig];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"长按菜单";
    self.tableView.tableFooterView = [UIView new];
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
        case MMSectionActions:  return @"更多";
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
    for (UIView *v in [cell.contentView.subviews copy]) { if ([v isKindOfClass:[UISwitch class]]) [v removeFromSuperview]; }

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
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
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
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
            if (!self.enabled) cell.textLabel.textColor = [UIColor secondaryLabelColor];
        }
        return cell;
    }

    if (indexPath.section == MMSectionKept) {
        NSArray<NSDictionary *> *kept = [self keptEntries];
        NSDictionary *entry = kept[indexPath.row];
        cell.textLabel.text = entry[MMMenuEntryTitleKey];
        if (self.enabled && self.sortingEnabled) {
            cell.showsReorderControl = YES;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.on = YES;
            sw.enabled = self.enabled;
            sw.accessibilityIdentifier = entry[MMMenuEntryIdentifierKey];
            [sw addTarget:self action:@selector(entrySwitchChanged:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[[sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],[sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
        }
        if (!self.enabled) {
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.userInteractionEnabled = NO;
        }
        return cell;
    }

    if (indexPath.section == MMSectionRemoved) {
        cell.textLabel.text = @"已移除菜单";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 项", (unsigned long)[self removedEntries].count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
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
        case MMActionRowBackup:
            cell.textLabel.text = @"备份配置";
            break;
        case MMActionRowRestore:
            cell.textLabel.text = @"还原配置";
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
            case MMActionRowBackup:           [self backupTapped]; break;
            case MMActionRowRestore:          [self restoreTapped]; break;
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

- (void)backupTapped {
    if (self.creatingBackup) return;
    [self persistConfig];
    self.creatingBackup = YES;
    __weak typeof(self) weakSelf = self;
    MMMenuCreateBackupFileAsync(^(NSURL *url, NSString *errorMessage) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.creatingBackup = NO;
        if (!url) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"备份失败"
                                                                           message:(errorMessage ?: @"无法生成备份文件。")
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        UIActivityViewController *activity = [[UIActivityViewController alloc]
            initWithActivityItems:@[url] applicationActivities:nil];
        UIPopoverPresentationController *popover = activity.popoverPresentationController;
        if (popover) {
            popover.sourceView = self.view;
            popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                            CGRectGetMidY(self.view.bounds), 1, 1);
            popover.permittedArrowDirections = 0;
        }
        [self presentViewController:activity animated:YES completion:nil];
    });
}

- (void)restoreTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还原配置"
                                                                   message:@"选择有效备份后，当前配置会被备份文件覆盖。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"继续选择" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        (void)a;
        [weakSelf presentRestorePicker];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentRestorePicker {
    UIDocumentPickerViewController *picker = nil;
    if (@available(iOS 14.0, *)) {
        picker = [[UIDocumentPickerViewController alloc]
                  initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"public.zip-archive"],
                                               [UTType typeWithIdentifier:@"public.data"]]
                  asCopy:YES];
    } else {
        picker = [[UIDocumentPickerViewController alloc]
                  initWithDocumentTypes:@[@"public.zip-archive", @"public.data"]
                  inMode:UIDocumentPickerModeOpen];
    }
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    NSError *error = nil;
    BOOL restored = MMMenuRestoreFromBackupURL(url, &error);
    if (restored) {
        [self reloadConfig];
        [self.tableView reloadData];
        [self applyEditingState];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(restored ? @"还原完成" : @"无法还原")
                                                                   message:(restored ? @"配置已还原并立即生效，无需重启微信。"
                                                                                     : (error.localizedDescription ?: @"所选文件不是有效的配置备份。"))
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
