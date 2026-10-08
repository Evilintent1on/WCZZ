//
//  GroupHelperListController.m
//
//  分组列表页：
//    * 数据 = MMGroupGroupedSessions()（所有群聊 − 常用群 + 手动加入）
//    * 右上角「＋」→ 选择页（手动加入分组）
//    * 点某一行 → 调主界面的 -onLogicOpenSession: 打开该会话
//    * 左滑 → 移出分组（群聊 = 设为常用群；手动加入的 = 移除手动名单）
//

#import "WeChatHeaders.h"
#import "GroupHelperCompat.h"
#import "GroupHelperConfig.h"
#import "GroupHelperListController.h"
#import "GroupHelperSessionPickerController.h"

#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 找主界面控制器（用来打开会话）

static UIViewController *MMGroupFindIn(UIViewController *controller, NSInteger depth) {
    if (!controller || depth > 12) return nil;
    Class mainFrameClass = NSClassFromString(@"NewMainFrameViewController");
    if (mainFrameClass && [controller isKindOfClass:mainFrameClass]) return controller;
    if ([controller isKindOfClass:[UINavigationController class]]) {
        for (UIViewController *child in ((UINavigationController *)controller).viewControllers) {
            UIViewController *found = MMGroupFindIn(child, depth + 1);
            if (found) return found;
        }
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        UIViewController *found = MMGroupFindIn(((UITabBarController *)controller).selectedViewController, depth + 1);
        if (found) return found;
    }
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found = MMGroupFindIn(child, depth + 1);
        if (found) return found;
    }
    return MMGroupFindIn(controller.presentedViewController, depth + 1);
}

static UIViewController *MMGroupMainFrameController(void) {
    UIWindow *window = nil;
    for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
        if (candidate.isKeyWindow) { window = candidate; break; }
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    return MMGroupFindIn(window.rootViewController, 0);
}

static UIImage *MMGroupAvatarForUserName(NSString *userName) {
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return nil;
    if (MMGroupIsHelperSession(userName)) return nil;
    Class centerClass = objc_getClass("MMServiceCenter");
    Class contactMgrClass = objc_getClass("CContactMgr");
    if (!centerClass || !contactMgrClass) return nil;
    SEL defaultCenterSel = NSSelectorFromString(@"defaultCenter");
    SEL getServiceSel = NSSelectorFromString(@"getService:");
    SEL getContactSel = NSSelectorFromString(@"getContactByName:");
    SEL headImageSel = NSSelectorFromString(@"getContactHeadImage");
    id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, defaultCenterSel);
    id contactMgr = ((id (*)(id, SEL, id))objc_msgSend)(center, getServiceSel, contactMgrClass);
    if (![contactMgr respondsToSelector:getContactSel]) return nil;
    id contact = ((id (*)(id, SEL, id))objc_msgSend)(contactMgr, getContactSel, userName);
    if (contact && [contact respondsToSelector:headImageSel]) {
        id image = ((id (*)(id, SEL))objc_msgSend)(contact, headImageSel);
        return [image isKindOfClass:[UIImage class]] ? image : nil;
    }
    return nil;
}

#pragma mark -

@interface GroupHelperListController ()
@property (nonatomic, strong) NSArray *sessions;
@end

@implementation GroupHelperListController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = MMGroupHelperTitle();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 60.0;
    self.tableView.tableFooterView = [UIView new];
    if (@available(iOS 13.0, *)) {
        self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    }
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(onAddTapped)];
    [self reloadSessions];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSessions];
}

- (void)reloadSessions {
    self.sessions = MMGroupGroupedSessions();
    [self.tableView reloadData];
    MMGroupLog(@"列表页刷新：%lu 个会话", (unsigned long)self.sessions.count);
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.sessions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (self.sessions.count == 0) {
        return @"分组里还没有会话。群聊默认会进分组；也可以在群聊信息页把某个群设为「常用群」让它留在会话列表。";
    }
    return @"点右上角「＋」把会话加进分组；左滑可以移出分组。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"wczz.group.list.cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.textLabel.font = [UIFont systemFontOfSize:17.0];
        if (@available(iOS 13.0, *)) {
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        }
        cell.imageView.layer.cornerRadius = 4.0;
        cell.imageView.clipsToBounds = YES;
    }
    id session = self.sessions[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
    NSString *display = MMGroupDisplayName(userName, MMGroupValueSafe(session, @"m_nsNickName"));
    unsigned int unread = (unsigned int)[MMGroupValueSafe(session, @"m_uUnReadCount") unsignedIntValue];

    cell.textLabel.text = display;
    cell.detailTextLabel.text = unread ? [NSString stringWithFormat:@"%u 条未读", unread] : nil;

    UIImage *avatar = MMGroupAvatarForUserName(userName);
    if (avatar) {
        cell.imageView.image = avatar;
    } else {
        // 没有联系人头像时给一个占位，避免 cell 复用串图
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(40, 40), NO, 0);
        [[UIColor secondarySystemFillColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 40, 40) cornerRadius:4] fill];
        cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id session = self.sessions[(NSUInteger)indexPath.row];
    UIViewController *mainFrame = MMGroupMainFrameController();
    SEL openSel = NSSelectorFromString(@"onLogicOpenSession:");
    if (mainFrame && [mainFrame respondsToSelector:openSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(mainFrame, openSel, session);
        return;
    }
    MMGroupLog(@"打开会话失败：找不到 NewMainFrameViewController");
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    id session = self.sessions[(NSUInteger)indexPath.row];
    NSString *userName = MMGroupValueSafe(session, @"m_nsUserName");
    if (![userName isKindOfClass:[NSString class]] || !userName.length) return nil;

    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"移出分组"
                                                                       handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        if (MMGroupIsGroupUserName(userName)) {
            // 群聊：标记为常用群 → 不再自动进分组
            MMGroupSetCommon(userName, YES);
        }
        MMGroupSetManual(userName, NO);
        [self reloadSessions];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}

#pragma mark - actions

- (void)onAddTapped {
    __weak typeof(self) weakSelf = self;
    GroupHelperSessionPickerController *picker =
        [[GroupHelperSessionPickerController alloc] initWithMode:GroupHelperPickerModeManual
                                                      completion:^(NSUInteger count) {
        (void)count;
        [weakSelf reloadSessions];
    }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    [self presentViewController:nav animated:YES completion:nil];
}

@end
