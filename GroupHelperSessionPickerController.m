//
//  GroupHelperSessionPickerController.m
//
//  数据来源：-[MMNewSessionMgr GetSessionInfoList]（8.0.75 已验证存在）。
//  勾选状态来自 wczz.group.list；提交时整体覆盖名单并落地折叠。
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"
#import "GroupHelperSessionPickerController.h"

@interface GroupHelperSessionPickerController () <UISearchResultsUpdating>
@property (nonatomic, copy) void (^completion)(NSUInteger count);
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, strong) NSArray *filtered;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selected;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *keyword;
@end

@implementation GroupHelperSessionPickerController

- (instancetype)initWithCompletion:(void (^)(NSUInteger))completion {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _completion = [completion copy];
        _selected = [NSMutableOrderedSet orderedSet];
        self.title = @"群助手名单";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 54.0;
    self.tableView.tableFooterView = [UIView new];
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(wczzGroupCancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(wczzGroupDone)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.tableView.tableHeaderView = self.searchController.searchBar;
    }
    self.definesPresentationContext = YES;

    [self wczzGroupReload];
}

- (void)wczzGroupReload {
    self.sessions = MMGroupAllSessions();
    self.filtered = self.sessions;

    [self.selected removeAllObjects];
    for (NSString *userName in MMGroupUserNameList()) {
        [self.selected addObject:userName];
    }
    [self.tableView reloadData];
    [self wczzGroupUpdatePrompt];
}

- (void)wczzGroupUpdatePrompt {
    self.navigationItem.prompt = [NSString stringWithFormat:@"已选 %lu / 共 %lu 个会话",
                                  (unsigned long)self.selected.count,
                                  (unsigned long)self.sessions.count];
}

#pragma mark - search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *keyword = searchController.searchBar.text.lowercaseString;
    self.keyword = keyword;
    if (!keyword.length) {
        self.filtered = self.sessions;
    } else {
        NSMutableArray *hits = [NSMutableArray array];
        for (id session in self.sessions) {
            NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
            NSString *display = MMGroupDisplayName(userName, MMGroupValueSafe(session, @"m_nsNickName"));
            if ([[display lowercaseString] containsString:keyword] ||
                [[userName lowercaseString] containsString:keyword]) {
                [hits addObject:session];
            }
        }
        self.filtered = hits;
    }
    [self.tableView reloadData];
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.filtered.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"wczz.group.picker.cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }
    id session = self.filtered[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
    NSString *display = MMGroupDisplayName(userName, MMGroupValueSafe(session, @"m_nsNickName"));
    unsigned int unread = (unsigned int)[MMGroupValueSafe(session, @"m_uUnReadCount") unsignedIntValue];

    cell.textLabel.text = display;
    if ([display isEqualToString:userName]) {
        cell.detailTextLabel.text = unread ? [NSString stringWithFormat:@"%u 条未读", unread] : nil;
    } else {
        cell.detailTextLabel.text = unread ? [NSString stringWithFormat:@"%@ · %u 条未读", userName, unread]
                                           : userName;
    }
    cell.accessoryType = [self.selected containsObject:userName] ? UITableViewCellAccessoryCheckmark
                                                                : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id session = self.filtered[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return;
    if ([self.selected containsObject:userName]) {
        [self.selected removeObject:userName];
    } else {
        [self.selected addObject:userName];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self wczzGroupUpdatePrompt];
}

#pragma mark - actions

- (void)wczzGroupCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)wczzGroupDone {
    MMGroupSetUserNameList(self.selected.array);
    MMGroupApplyFold();
    if (self.completion) {
        self.completion(self.selected.count);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
