//
//  GroupHelperSessionPickerController.m
//  「密群列表」的增删页 —— 复刻 MiYou 的做法：
//    * 用微信原生的 ContactSelectView（多选）当选择界面
//      （实测 -[MYMultiSelectViewController initView]：ContactSelectView +
//        m_bMultiSelect=YES + m_uiGroupScene=[self selectType] + 底部按钮 onSendGroup）
//    * 拿不到原生视图时退回自建列表页（保证任何微信版本都能用）
//  文案照 MiYou 原文：「密群列表」/「已选 %ld 个群」
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"
#import "GroupHelperSessionPickerController.h"

#import <objc/runtime.h>
#import <objc/message.h>

@interface GroupHelperSessionPickerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, assign) GroupHelperPickerMode mode;
@property (nonatomic, copy) void (^completion)(NSUInteger count);
@property (nonatomic, strong) id nativeSelectView;      // ContactSelectView（原生多选视图）
@property (nonatomic, strong) UITableView *fallbackTable;
@property (nonatomic, strong) NSArray *sessions;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selected;
@end

@implementation GroupHelperSessionPickerController

- (instancetype)initWithMode:(GroupHelperPickerMode)mode completion:(void (^)(NSUInteger))completion {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _mode = mode;
        _completion = [completion copy];
        _selected = [NSMutableOrderedSet orderedSet];
        self.title = (mode == GroupHelperPickerModeRoomList) ? @"密群列表" : @"加入分组";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self action:@selector(onCancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(onDone)];
    [self reloadData];

    // 1) 优先用微信原生的多选联系人视图（MiYou 的做法）
    Class selectViewClass = objc_getClass("ContactSelectView");
    if (selectViewClass) {
        @try {
            id selectView = [[selectViewClass alloc] initWithFrame:self.view.bounds];
            [selectView setValue:@(YES) forKey:@"m_bMultiSelect"];      // 多选
            [selectView setValue:@{} forKey:@"m_dicExistContact"];
            [selectView setValue:[NSMutableDictionary dictionary] forKey:@"m_dicMultiSelect"];
            if ([selectView isKindOfClass:[UIView class]]) {
                ((UIView *)selectView).autoresizingMask =
                    UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [self.view addSubview:(UIView *)selectView];
            }
            self.nativeSelectView = selectView;
            MMGroupLog(@"密群列表：已用微信原生 ContactSelectView（多选）");
        } @catch (NSException *exception) {
            MMGroupLog(@"原生 ContactSelectView 初始化异常，退回自建列表：%@", exception);
            self.nativeSelectView = nil;
        }
    }
    if (!self.nativeSelectView) {
        [self buildFallbackTable];
    }
}

- (void)buildFallbackTable {
    UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = 54.0;
    table.tableFooterView = [UIView new];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:table];
    self.fallbackTable = table;
}

- (NSArray<NSString *> *)memberList {
    return MMGroupRoomList();
}

- (void)reloadData {
    self.sessions = MMGroupAllGroupSessions();
    [self.selected removeAllObjects];
    for (NSString *userName in [self memberList]) {
        [self.selected addObject:userName];
    }
    [self.fallbackTable reloadData];
    self.navigationItem.prompt = [NSString stringWithFormat:@"已选 %lu 个群", (unsigned long)self.selected.count];
}

#pragma mark - 自建列表（回退方案）

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sessions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"wczz.group.picker.cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    }
    id session = self.sessions[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupUserNameOfSession(session);
    NSString *display = MMGroupDisplayName(userName, MMGroupValueSafe(session, @"m_nsNickName"));
    cell.textLabel.text = display;
    cell.detailTextLabel.text = [display isEqualToString:userName] ? nil : userName;
    cell.accessoryType = [self.selected containsObject:userName] ? UITableViewCellAccessoryCheckmark
                                                                : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *userName = MMGroupUserNameOfSession(self.sessions[(NSUInteger)indexPath.row]);
    if (!userName.length) return;
    if ([self.selected containsObject:userName]) {
        [self.selected removeObject:userName];
    } else {
        [self.selected addObject:userName];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    self.navigationItem.prompt = [NSString stringWithFormat:@"已选 %lu 个群", (unsigned long)self.selected.count];
}

#pragma mark - 收尾

/// 从原生 ContactSelectView 的 m_dicMultiSelect / m_dicExistContact 里读出选中的会话
- (NSArray<NSString *> *)selectedUserNames {
    NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSetWithOrderedSet:self.selected];
    if (self.nativeSelectView) {
        for (NSString *key in @[@"m_dicMultiSelect", @"m_dicExistContact"]) {
            @try {
                id dict = [self.nativeSelectView valueForKey:key];
                if ([dict respondsToSelector:@selector(allKeys)]) {
                    for (id name in [dict allKeys]) {
                        if ([name isKindOfClass:[NSString class]] && [name length]) [result addObject:name];
                    }
                }
            } @catch (__unused NSException *exception) {}
        }
    }
    return result.array;
}

- (void)onCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onDone {
    MMGroupSetRoomList([self selectedUserNames]);
    MMGroupForceReloadSessions();
    if (self.completion) self.completion(MMGroupRoomList().count);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
