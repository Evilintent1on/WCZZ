//
//  GroupHelperSessionPickerController.m
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"
#import "GroupHelperSessionPickerController.h"

@interface GroupHelperSessionPickerController () <UISearchResultsUpdating>
@property (nonatomic, assign) GroupHelperPickerMode mode;
@property (nonatomic, copy) void (^completion)(NSUInteger count);
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, strong) NSArray *filtered;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selected;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation GroupHelperSessionPickerController

- (instancetype)initWithMode:(GroupHelperPickerMode)mode completion:(void (^)(NSUInteger))completion {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _mode = mode;
        _completion = [completion copy];
        _selected = [NSMutableOrderedSet orderedSet];
        self.title = (mode == GroupHelperPickerModeCommon) ? @"常用群（不进分组）" : @"加入分组";
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
                                                      action:@selector(onCancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(onDone)];

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

    [self reloadData];
}

- (NSArray<NSString *> *)memberList {
    return (self.mode == GroupHelperPickerModeCommon) ? MMGroupCommonList() : MMGroupManualList();
}

- (void)reloadData {
    // 常用群只能选群聊；手动加入可以选任意会话
    self.sessions = (self.mode == GroupHelperPickerModeCommon) ? MMGroupAllGroupSessions() : MMGroupAllSessions();
    self.filtered = self.sessions;
    [self.selected removeAllObjects];
    for (NSString *userName in [self memberList]) {
        [self.selected addObject:userName];
    }
    [self.tableView reloadData];
    [self updatePrompt];
}

- (void)updatePrompt {
    NSString *what = (self.mode == GroupHelperPickerModeCommon) ? @"常用" : @"已加入";
    self.navigationItem.prompt = [NSString stringWithFormat:@"%@ %lu / 共 %lu 个会话",
                                  what, (unsigned long)self.selected.count, (unsigned long)self.sessions.count];
}

#pragma mark - search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *keyword = searchController.searchBar.text.lowercaseString;
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
        if (@available(iOS 13.0, *)) {
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }
    }
    id session = self.filtered[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
    NSString *display = MMGroupDisplayName(userName, MMGroupValueSafe(session, @"m_nsNickName"));

    cell.textLabel.text = display;
    cell.detailTextLabel.text = [display isEqualToString:userName] ? nil : userName;
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
    [self updatePrompt];
}

#pragma mark - actions

- (void)onCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onDone {
    if (self.mode == GroupHelperPickerModeCommon) {
        MMGroupSetCommonList(self.selected.array);
    } else {
        MMGroupSetManualList(self.selected.array);
    }
    if (self.completion) {
        self.completion(self.selected.count);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
