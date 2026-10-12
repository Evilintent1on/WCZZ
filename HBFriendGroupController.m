//
//  HBFriendGroupController.m
//  群聊 / 好友分组控制器实现
//
//  列表模式：一行一个分组，向上可展开到「全部分组设置」
//  设置模式：一堆开关行（置顶 / 位置 / 隐藏搜索栏 / 隐藏摘要发送者 / 摘要格式 / 改名 / 换头像 / 选群）
//

#import "HBFriendGroupController.h"
#import "HBGroupEngine.h"
#import "HBGroupService.h"

static NSString *const kHBGroupCellID = @"HBGroupCell";

@interface HBFriendGroupController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
- (void)onConfigChanged:(NSNotification *)note;
- (BOOL)validAccount;
- (void)openSession:(id)session;
- (void)openSettings;
- (void)prepareGroupBatch:(HBGroupAction)action;
- (void)beginGroupBatch:(NSMutableArray *)list action:(HBGroupAction)action;
- (void)processGroupBatch:(NSMutableArray *)list
                   action:(HBGroupAction)action
                    index:(NSUInteger)index
                completed:(NSUInteger)completed;
- (void)finishGroupBatch:(NSUInteger)count stopped:(BOOL)stopped;
- (void)onModeSwitch:(UISwitch *)sender;
- (void)onPinnedSwitch:(UISwitch *)sender;
- (void)onBelowNativeSwitch:(UISwitch *)sender;
- (void)onHideSearchBarSwitch:(UISwitch *)sender;
- (void)onHideSummarySenderSwitch:(UISwitch *)sender;
- (void)editSummaryFormat;
- (void)editName;
- (void)chooseAvatar;
- (void)chooseFriends;
- (NSString *)currentGroupName;
@end

@implementation HBFriendGroupController

#pragma mark - 生命周期

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if ((self = [super initWithStyle:style])) {
        _cellModels = [NSMutableDictionary dictionary];
        _searchText = @"";
        _account = @"";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.rowHeight = 64.0;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kHBGroupCellID];

    self.title = self.groupChats ? @"群聊分组" : @"好友分组";

    if (!self.settingsMode) {
        UIBarButtonItem *menuItem = [[UIBarButtonItem alloc] initWithTitle:@"⋯"
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(showGroupMenu)];
        self.navigationItem.rightBarButtonItem = menuItem;
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onConfigChanged:)
                                                 name:kHBGroupChangedNotification
                                               object:nil];

    [self reloadSettings];
    [self reloadGroup];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onConfigChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.isViewLoaded) return;
        [self reloadSettings];
        [self.tableView reloadData];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.settingsMode) [self reloadSettings];
    else [self reloadGroup];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[HBGroupService shared] closeSessionMenus];
}

#pragma mark - 数据

- (BOOL)validAccount {
    NSString *current = [[HBGroupService shared] currentAccount];
    if (!current.length) return NO;
    if (self.account.length && ![self.account isEqualToString:current]) return NO;
    self.account = current;
    return YES;
}

- (void)reloadGroup {
    if (![self validAccount]) {
        self.sessions = @[];
        [self.tableView reloadData];
        return;
    }

    BOOL chatMode = self.groupChats;
    NSArray *all = [[HBGroupService shared] allSessions];
    NSMutableArray *list = [NSMutableArray array];

    for (id session in all) {
        if (![HBGroupEngine isGroupSession:session chatMode:chatMode]) continue;
        NSString *name = [HBGroupEngine displayNameOfSession:session];
        if (self.searchText.length) {
            NSString *trimmed = [self.searchText stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length) {
                if (![name containsString:trimmed]) continue;
            }
        }
        [list addObject:session];
    }

    self.sessions = list;
    [self.tableView reloadData];
}

- (void)reloadSettings {
    if (!self.settingsMode) return;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.settingsMode ? 3 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.settingsMode) return self.sessions.count;
    switch (section) {
        case 0: return 4;   // 开关组
        case 1: return 3;   // 外观组
        case 2: return 2;   // 分组管理组
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (!self.settingsMode) {
        return [NSString stringWithFormat:@"共 %lu 个会话", (unsigned long)self.sessions.count];
    }
    if (section == 0) return @"分组行会折叠同类会话，点开分组行可查看全部。";
    if (section == 2) return @"选中后立即生效，返回微信首页即可看到分组。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kHBGroupCellID];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kHBGroupCellID];

    HBGroupConfig *config = [HBGroupConfig shared];

    if (!self.settingsMode) {
        id session = self.sessions.count > (NSUInteger)indexPath.row ? self.sessions[indexPath.row] : nil;
        cell.textLabel.text = session ? [HBGroupEngine displayNameOfSession:session] : @"";
        cell.detailTextLabel.text = session ? [HBGroupEngine summaryOfSession:session] : @"";
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    cell.imageView.image = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.detailTextLabel.text = nil;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = self.groupChats ? @"群聊分组" : @"好友分组";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = self.groupChats ? config.chatGroupEnabled : config.friendGroupEnabled;
            [sw addTarget:self action:@selector(onModeSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"分组行置顶";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = config.pinned;
            [sw addTarget:self action:@selector(onPinnedSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"排在原生置顶之下";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = config.belowNativePinned;
            [sw addTarget:self action:@selector(onBelowNativeSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else {
            cell.textLabel.text = @"隐藏首页搜索栏";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = config.hideSearchBar;
            [sw addTarget:self action:@selector(onHideSearchBarSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        return cell;
    }

    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"隐藏摘要发送者";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = config.hideSummarySender;
            [sw addTarget:self action:@selector(onHideSummarySenderSwitch:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"摘要格式";
            cell.detailTextLabel.text = config.summaryFormat ?: @"%@: %@";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"分组显示名";
            cell.detailTextLabel.text = [self currentGroupName];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    if (indexPath.row == 0) {
        cell.textLabel.text = self.groupChats ? @"选择群聊" : @"选择好友";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"分组头像";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (!self.settingsMode) {
        id session = self.sessions.count > (NSUInteger)indexPath.row ? self.sessions[indexPath.row] : nil;
        if (session) [self openSession:session];
        return;
    }

    if (indexPath.section == 1 && indexPath.row == 1) { [self editSummaryFormat]; return; }
    if (indexPath.section == 1 && indexPath.row == 2) { [self editName]; return; }
    if (indexPath.section == 2 && indexPath.row == 0) { [self chooseFriends]; return; }
    if (indexPath.section == 2 && indexPath.row == 1) { [self chooseAvatar]; return; }
}

#pragma mark - 会话操作

- (void)openSession:(id)session {
    [[HBGroupService shared] openSession:session fromController:self];
}

- (void)showGroupMenu {
    if (![self validAccount]) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    BOOL chatMode = self.groupChats;

    [sheet addAction:[UIAlertAction actionWithTitle:@"分组设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self openSettings];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"全部标为已读" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self prepareGroupBatch:HBGroupActionRead];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除会话" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self prepareGroupBatch:HBGroupActionDelete];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"隐藏会话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self prepareGroupBatch:HBGroupActionHide];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (chatMode) sheet.title = @"群聊分组";
    else sheet.title = @"好友分组";

    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openSettings {
    HBFriendGroupController *controller =
        [[HBFriendGroupController alloc] initWithStyle:UITableViewStyleGrouped];
    controller.settingsMode = YES;
    controller.groupChats = self.groupChats;
    controller.homeController = self.homeController;
    controller.account = self.account;
    [self.navigationController pushViewController:controller animated:YES];
}

#pragma mark - 批量操作

- (void)prepareGroupBatch:(HBGroupAction)action {
    if (![self validAccount]) {
        [[HBGroupService shared] toast:@"账号未就绪"];
        return;
    }
    if (self.batchRunning) {
        [[HBGroupService shared] toast:@"正在处理中，请稍候"];
        return;
    }
    if (!self.sessions.count) {
        [[HBGroupService shared] toast:@"没有可操作的会话"];
        return;
    }

    NSString *title = nil;
    switch (action) {
        case HBGroupActionRead: title = @"把分组内全部会话标为已读？"; break;
        case HBGroupActionDelete: title = @"删除分组内全部会话？"; break;
        case HBGroupActionHide: title = @"隐藏分组内全部会话？"; break;
        default: break;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [self beginGroupBatch:[self.sessions mutableCopy] action:action];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)beginGroupBatch:(NSMutableArray *)list action:(HBGroupAction)action {
    self.batchRunning = YES;
    self.handlingEdit = YES;
    [[HBGroupService shared] closeSessionMenus];
    [self processGroupBatch:list action:action index:0 completed:0];
}

- (void)processGroupBatch:(NSMutableArray *)list
                   action:(HBGroupAction)action
                    index:(NSUInteger)index
                completed:(NSUInteger)completed {

    if (index >= list.count) {
        [self finishGroupBatch:completed stopped:NO];
        return;
    }

    id session = list[index];
    NSString *userName = [HBGroupEngine userNameOfSession:session];

    if (userName.length) {
        HBGroupService *service = [HBGroupService shared];
        switch (action) {
            case HBGroupActionRead:
                [service markRead:userName];
                break;
            case HBGroupActionDelete:
                [service deleteSession:userName];
                break;
            case HBGroupActionHide:
                [service hideSession:userName];
                break;
            default: break;
        }
        completed++;
    }

    // 串行推进，避免同时打太多微信私有接口
    dispatch_async(dispatch_get_main_queue(), ^{
        [self processGroupBatch:list action:action index:index + 1 completed:completed];
    });
}

- (void)finishGroupBatch:(NSUInteger)count stopped:(BOOL)stopped {
    self.batchRunning = NO;
    self.handlingEdit = NO;
    [[HBGroupService shared] recountUnread];
    [self reloadGroup];

    if (!stopped) {
        [[HBGroupService shared] toast:[NSString stringWithFormat:@"已处理 %lu 个会话", (unsigned long)count]];
    } else {
        [[HBGroupService shared] toast:@"已中断"];
    }
}

#pragma mark - 设置项动作

- (void)onModeSwitch:(UISwitch *)sender {
    HBGroupConfig *config = [HBGroupConfig shared];
    if (self.groupChats) config.chatGroupEnabled = sender.on;
    else config.friendGroupEnabled = sender.on;
    [config synchronize];
    [HBFriendGroupController refreshForHomeActivation];
}

- (void)onPinnedSwitch:(UISwitch *)sender {
    [HBGroupConfig shared].pinned = sender.on;
    [[HBGroupConfig shared] synchronize];
    [HBFriendGroupController refreshForHomeActivation];
}

- (void)onBelowNativeSwitch:(UISwitch *)sender {
    [HBGroupConfig shared].belowNativePinned = sender.on;
    [[HBGroupConfig shared] synchronize];
    [HBFriendGroupController refreshForHomeActivation];
}

- (void)onHideSearchBarSwitch:(UISwitch *)sender {
    [HBGroupConfig shared].hideSearchBar = sender.on;
    [[HBGroupConfig shared] synchronize];
    [HBFriendGroupController refreshForHomeActivation];
}

- (void)onHideSummarySenderSwitch:(UISwitch *)sender {
    [HBGroupConfig shared].hideSummarySender = sender.on;
    [[HBGroupConfig shared] synchronize];
    [HBFriendGroupController refreshForHomeActivation];
}

- (void)editSummaryFormat {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"摘要格式"
                                                                   message:@"%@ 表示发送者，%@ 表示内容"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = [HBGroupConfig shared].summaryFormat ?: @"%@: %@";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length) {
            [HBGroupConfig shared].summaryFormat = text;
            [[HBGroupConfig shared] synchronize];
            [self.tableView reloadData];
            [HBFriendGroupController refreshForHomeActivation];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)currentGroupName {
    NSArray<HBGroupItem *> *groups = [[HBGroupConfig shared] groupsForChatMode:self.groupChats];
    if (groups.count) return groups.firstObject.name;
    return self.groupChats ? @"群聊分组" : @"好友分组";
}

- (void)editName {
    NSArray<HBGroupItem *> *groups = [[HBGroupConfig shared] groupsForChatMode:self.groupChats];
    if (!groups.count) return;
    HBGroupItem *item = groups.firstObject;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"分组显示名"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = item.name;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length) {
            item.name = text;
            [[HBGroupConfig shared] synchronize];
            [self.tableView reloadData];
            [HBFriendGroupController refreshForHomeActivation];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseAvatar {
    NSArray<HBGroupItem *> *groups = [[HBGroupConfig shared] groupsForChatMode:self.groupChats];
    if (!groups.count) return;

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];

    UIImage *image = info[UIImagePickerControllerOriginalImage];
    NSArray<HBGroupItem *> *groups = [[HBGroupConfig shared] groupsForChatMode:self.groupChats];
    if (!image || !groups.count) return;

    HBGroupItem *item = groups.firstObject;
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"hbgroup_%@.png", item.identifier]];
    if ([UIImagePNGRepresentation(image) writeToFile:path atomically:YES]) {
        item.avatarPath = path;
        [[HBGroupConfig shared] synchronize];
        [self.tableView reloadData];
        [HBFriendGroupController refreshForHomeActivation];
    } else {
        [[HBGroupService shared] toast:@"头像保存失败"];
    }
}

- (void)chooseFriends {
    if (![self validAccount]) return;
    [[HBGroupService shared] presentSessionPickerForChatMode:self.groupChats
                                                     from:self
                                                 completion:^(NSArray<NSString *> *selected) {
        HBGroupConfig *config = [HBGroupConfig shared];
        NSArray<HBGroupItem *> *groups = [config groupsForChatMode:self.groupChats];
        HBGroupItem *item = groups.firstObject;

        if (!item) {
            item = [[HBGroupItem alloc] init];
            item.name = self.groupChats ? @"群聊分组" : @"好友分组";
            NSMutableArray *list = [groups mutableCopy] ?: [NSMutableArray array];
            [list addObject:item];
            [config setGroups:list chatMode:self.groupChats];
        }

        item.members = [selected mutableCopy] ?: [NSMutableArray array];
        [config synchronize];
        [self.tableView reloadData];
        [HBFriendGroupController refreshForHomeActivation];
        [[HBGroupService shared] toast:[NSString stringWithFormat:@"已保存 %lu 个", (unsigned long)selected.count]];
    }];
}

#pragma mark - 类方法（引擎入口）

+ (BOOL)isEnabled {
    return [HBGroupConfig shared].enabled;
}

+ (BOOL)isChatGroupEnabled {
    HBGroupConfig *config = [HBGroupConfig shared];
    return config.enabled && config.chatGroupEnabled;
}

+ (void)setChatGroupEnabled:(BOOL)enabled {
    [HBGroupConfig shared].chatGroupEnabled = enabled;
    [[HBGroupConfig shared] synchronize];
    [self refreshForHomeActivation];
}

+ (void)setEnabled:(BOOL)enabled {
    [self setEnabled:enabled groupChats:YES];
}

+ (void)setEnabled:(BOOL)enabled groupChats:(BOOL)groupChats {
    HBGroupConfig *config = [HBGroupConfig shared];
    config.enabled = enabled;
    if (groupChats) config.chatGroupEnabled = enabled;
    else config.friendGroupEnabled = enabled;
    [config synchronize];
    [self refreshForHomeActivation];
}

+ (void)rebuildSessions:(id)manager {
    [self rebuildSessions:manager groupChats:YES];
}

+ (void)rebuildSessions:(id)manager groupChats:(BOOL)groupChats {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rebuildSessions:manager groupChats:groupChats];
        });
        return;
    }
    if (![self isEnabled]) return;
    [HBGroupEngine rebuildSessions:manager chatMode:groupChats];
}

+ (NSArray *)filteredLaunchSessions:(NSArray *)sessions {
    return [self filteredLaunchSessions:sessions groupChats:YES];
}

+ (NSArray *)filteredLaunchSessions:(NSArray *)sessions groupChats:(BOOL)groupChats {
    if (![self isEnabled]) return sessions ?: @[];
    return [HBGroupEngine filteredLaunchSessions:sessions chatMode:groupChats];
}

+ (BOOL)isGroupSession:(id)session {
    return [HBGroupEngine isGroupSession:session chatMode:YES];
}

+ (id)groupAtIndex:(NSUInteger)index top:(BOOL)top manager:(id)manager {
    if (![self isEnabled]) return nil;
    return [HBGroupEngine groupAtIndex:index top:top manager:manager];
}

+ (id)groupCellDataForSession:(id)session {
    if (![self isEnabled]) return session;
    return [HBGroupEngine groupCellDataForSession:session];
}

+ (id)summaryDataForItem:(id)item {
    NSString *text = [HBGroupEngine summaryOfSession:item];
    if ([item respondsToSelector:NSSelectorFromString(@"m_textForMessageLabel")]) {
        @try { return [item valueForKey:@"m_textForMessageLabel"]; } @catch (__unused NSException *e) { }
    }
    return text ?: @"";
}

+ (void)finishSummaryForItem:(id)item entryData:(id)entryData {
    if (!item || !entryData) return;
    @try {
        id count = [entryData valueForKey:@"unreadCount"];
        if ([count respondsToSelector:@selector(unsignedIntegerValue)]) {
            [item setValue:count forKey:@"m_uUnReadCount"];
        }
    } @catch (__unused NSException *e) { }
}

+ (void)recordHomeRowHeight:(CGFloat)height {
    [HBGroupEngine recordHomeRowHeight:height];
}

+ (void)configureHomeCell:(id)cell {
    if (!cell) return;
    // 分组行禁止长按菜单、去掉删除按钮
    if ([cell respondsToSelector:NSSelectorFromString(@"setContextMenuEnabled:")]) {
        @try { [cell setValue:@(NO) forKey:@"contextMenuEnabled"]; } @catch (__unused NSException *e) { }
    }
    if ([cell respondsToSelector:NSSelectorFromString(@"setForbidDisplayMenuWithGestures:")]) {
        @try { [cell setValue:@(YES) forKey:@"forbidDisplayMenuWithGestures"]; } @catch (__unused NSException *e) { }
    }
    @try { [cell setValue:@(NO) forKey:@"m_bShowUnReadAsRedDot"]; } @catch (__unused NSException *e) { }
}

+ (void)openFromController:(id)controller session:(id)session {
    if (!session) return;
    HBFriendGroupController *list =
        [[HBFriendGroupController alloc] initWithStyle:UITableViewStylePlain];
    list.groupChats = YES;
    list.homeController = controller;

    UINavigationController *nav = nil;
    if ([controller respondsToSelector:NSSelectorFromString(@"navigationController")]) {
        nav = [controller valueForKey:@"navigationController"];
    }
    if (nav) [nav pushViewController:list animated:YES];
}

+ (NSString *)avatarForGroupUsername:(NSString *)userName {
    if (!userName.length) return nil;
    NSArray<HBGroupItem *> *groups = [[HBGroupConfig shared] groupsForChatMode:
                                      [userName hasSuffix:@"@chatroom"]];
    for (HBGroupItem *item in groups) {
        if ([item.members containsObject:userName]) return item.avatarPath;
    }
    return nil;
}

+ (void)applyGroupAvatar:(id)view fake:(BOOL)fake {
    if (!view) return;
    // 分组行的头像用分组自定义头像；没有就用默认
    @try { [view setValue:@(fake) forKey:@"hb_group_fake_avatar"]; } @catch (__unused NSException *e) { }
}

+ (BOOL)isGroupActionMenu:(id)menu {
    return [HBGroupConfig shared].enabled;
}

+ (void)setSelecting:(BOOL)selecting controller:(id)controller {
    if (!controller) return;
    if ([controller respondsToSelector:NSSelectorFromString(@"setEditing:animated:")]) {
        @try { [controller setValue:@(selecting) forKey:@"editing"]; } @catch (__unused NSException *e) { }
    }
}

+ (void)refreshForHomeActivation {
    // 让微信首页重新拉一次会话列表
    dispatch_async(dispatch_get_main_queue(), ^{
        [[HBGroupService shared] rebuildMainSessions];
    });
}

+ (void)appendExclusionCellToSection:(id)section contact:(id)contact owner:(id)owner {
    NSString *userName = [HBGroupEngine userNameOfSession:contact];
    if (!userName.length) return;
    HBGroupConfig *config = [HBGroupConfig shared];
    if (![config.exclusions containsObject:userName]) {
        [config.exclusions addObject:userName];
        [config synchronize];
    }
}

@end
