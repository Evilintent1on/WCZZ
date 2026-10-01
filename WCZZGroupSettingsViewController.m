#import "WCZZGroupSettingsViewController.h"
#import "WCZZSessionGroupManager.h"
#import <objc/runtime.h>

static NSString *const kWCZZGroupNameKey = @"WCZZGroupName";
static NSString *const kWCZZGroupHideSearchKey = @"WCZZGroupHideSearch";
static NSString *const kWCZZGroupPinnedKey = @"WCZZGroupPinned";
static NSString *const kWCZZGroupBelowOfficialTopKey = @"WCZZGroupBelowOfficialTop";

@interface WCZZGroupSettingsViewController ()
@property (nonatomic, strong) NSString *groupName;
@property (nonatomic, assign) BOOL hideSearch;
@property (nonatomic, assign) BOOL groupPinned;
@property (nonatomic, assign) BOOL belowOfficialTop;
@end

@implementation WCZZGroupSettingsViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _groupName = [d stringForKey:kWCZZGroupNameKey] ?: @"群助手";
        _hideSearch = [d boolForKey:kWCZZGroupHideSearchKey];
        _groupPinned = [d boolForKey:kWCZZGroupPinnedKey];
        _belowOfficialTop = [d boolForKey:kWCZZGroupBelowOfficialTopKey];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"群聊分组设置";
    self.tableView.tableFooterView = [UIView new];
    self.tableView.rowHeight = 55;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil];
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 7; // 分组名称、分组头像、收纳模式、排除群聊、隐藏搜索框、置顶群聊分组、置于官方置顶下方
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"wczz.groupsetting";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    for (UIView *v in [cell.contentView.subviews copy]) {
        if ([v isKindOfClass:[UISwitch class]]) [v removeFromSuperview];
    }

    // 卡片样式
    cell.backgroundColor = [UIColor whiteColor];
    if (@available(iOS 13.0, *)) {
        cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    }
    cell.textLabel.font = [UIFont systemFontOfSize:15];

    switch (indexPath.row) {
        case 0: {
            cell.textLabel.text = @"分组名称";
            cell.detailTextLabel.text = self.groupName;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 1: {
            cell.textLabel.text = @"分组头像";
            cell.detailTextLabel.text = @"从相册选择";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 2: {
            cell.textLabel.text = @"收纳模式";
            cell.detailTextLabel.text = @"全部群聊";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 3: {
            cell.textLabel.text = @"排除群聊";
            WCZZSessionGroupManager *mgr = [WCZZSessionGroupManager sharedInstance];
            NSInteger excludedCount = mgr.excludedGroups.count;
            cell.detailTextLabel.text = excludedCount > 0 ?
                [NSString stringWithFormat:@"已选 %ld 个群聊", (long)excludedCount] : @"未选择";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        case 4: {
            cell.textLabel.text = @"隐藏搜索框";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.on = self.hideSearch;
            sw.tag = 300;
            [sw addTarget:self action:@selector(wczzGroupSettingSwitch:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[
                [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
            break;
        }
        case 5: {
            cell.textLabel.text = @"置顶群聊分组";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.on = self.groupPinned;
            sw.tag = 301;
            [sw addTarget:self action:@selector(wczzGroupSettingSwitch:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[
                [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
            break;
        }
        case 6: {
            cell.textLabel.text = @"-置于官方置顶下方";
            cell.textLabel.textColor = [UIColor grayColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [UISwitch new];
            sw.on = self.belowOfficialTop;
            sw.tag = 302;
            [sw addTarget:self action:@selector(wczzGroupSettingSwitch:) forControlEvents:UIControlEventValueChanged];
            sw.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:sw];
            [NSLayoutConstraint activateConstraints:@[
                [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
            break;
        }
    }
    return cell;
}

- (void)wczzGroupSettingSwitch:(UISwitch *)sw {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (sw.tag == 300) {
        self.hideSearch = sw.on;
        [d setBool:sw.on forKey:kWCZZGroupHideSearchKey];
    } else if (sw.tag == 301) {
        self.groupPinned = sw.on;
        [d setBool:sw.on forKey:kWCZZGroupPinnedKey];
    } else if (sw.tag == 302) {
        self.belowOfficialTop = sw.on;
        [d setBool:sw.on forKey:kWCZZGroupBelowOfficialTopKey];
    }
    [d synchronize];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) {
        // 分组名称：弹出输入框
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"分组名称"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.text = self.groupName;
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *name = alert.textFields.firstObject.text;
            if (name.length > 0) {
                self.groupName = name;
                [[NSUserDefaults standardUserDefaults] setObject:name forKey:kWCZZGroupNameKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                [self.tableView reloadData];
            }
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    // 其他行（头像、收纳模式、排除群聊）暂时只做展示，后续可扩展
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"仅收纳首页已有的群聊会话，不含好友、公众号和服务号。全部群聊模式可单独排除；白名单模式只收纳选中的群聊。不置顶时按分组内最新消息时间排列。关闭功能恢复原列表，不删除消息或清除未读。";
}

@end
