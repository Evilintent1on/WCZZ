//
//  HBGroupHooks.xm
//  群聊分组的接入层
//
//  挂钩点（从原版二进制里还原出来的）：
//
//   MainSessionMgr（类方法，会话列表数据源）
//     - rebuildMainSessions
//     - setVisibleUnreadSlienceChatSessionCount:
//     - getNormalSessionAtIndex:fulFilled:
//     - getTopSessionAtIndex:fulFilled:
//     - getLastFrontSessionArray
//     - getCellDataAtIndexPath:
//
//   NewMainFrameViewController（首页）
//     - handleSelectIndexPath:tableView:
//     - tableView:canEditRowAtIndexPath:
//     - tableView:cellForRowAtIndexPath:
//     - tableView:heightForRowAtIndexPath:
//
//   SessionSelectController（选群界面）
//     - viewWillAppear:
//     - layoutSubviews
//
//   MMHeadImageView（头像）
//     - checkAndUpdateImage
//
//  所有类都用 objc_getClass 动态取，取不到就跳过——换微信版本不会因为一个类没了整体挂掉。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "HBFriendGroupController.h"
#import "HBGroupEngine.h"
#import "HBGroupService.h"

#pragma mark - 动态挂钩

typedef struct {
    const char *className;
    const char *selector;
    IMP replacement;
    void *original;
} HBHookEntry;

/// 挂一个实例方法；类不存在就跳过
static void HBHookClass(const char *className, const char *selectorName, IMP replacement, void **original) {
    if (!className || !selectorName || !replacement) return;
    Class cls = objc_getClass(className);
    if (!cls) return;
    SEL sel = sel_registerName(selectorName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return;
    MSHookMessageEx(cls, sel, replacement, (IMP *)original);
}

/// 挂一个类方法（走 metaclass）
static void HBHookMetaClass(const char *className, const char *selectorName, IMP replacement, void **original) {
    if (!className || !selectorName || !replacement) return;
    Class cls = objc_getClass(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    SEL sel = sel_registerName(selectorName);
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;
    MSHookMessageEx(meta, sel, replacement, (IMP *)original);
}

#pragma mark - MainSessionMgr

typedef id (*HBGetArrayIMP)(id, SEL);
typedef id (*HBGetIndexIMP)(id, SEL, NSInteger, BOOL *);
typedef void (*HBVoidIMP)(id, SEL);
typedef void (*HBSetCountIMP)(id, SEL, NSUInteger);
typedef NSUInteger (*HBUIntIMP)(id, SEL);

static HBGetArrayIMP orig_getLastFrontSessionArray = NULL;
static HBGetArrayIMP orig_rebuildMainSessions = NULL;
static HBGetIndexIMP orig_getNormalSessionAtIndex = NULL;
static HBGetIndexIMP orig_getTopSessionAtIndex = NULL;
static HBSetCountIMP orig_setVisibleUnread = NULL;
static id (*orig_getCellDataAtIndexPath)(id, SEL, id) = NULL;

static id hb_getLastFrontSessionArray(id self, SEL _cmd) {
    id sessions = orig_getLastFrontSessionArray ? orig_getLastFrontSessionArray(self, _cmd) : nil;
    if (![HBFriendGroupController isChatGroupEnabled]) return sessions;
    if (![sessions isKindOfClass:[NSArray class]]) return sessions;
    return [HBFriendGroupController filteredLaunchSessions:sessions groupChats:YES];
}

static void hb_rebuildMainSessions(id self, SEL _cmd) {
    if (orig_rebuildMainSessions) orig_rebuildMainSessions(self, _cmd);
    if (![HBFriendGroupController isChatGroupEnabled]) return;
    [HBFriendGroupController rebuildSessions:self groupChats:YES];
}

static id hb_getNormalSessionAtIndex(id self, SEL _cmd, NSInteger index, BOOL *fulfilled) {
    if (![HBFriendGroupController isChatGroupEnabled] || !orig_getNormalSessionAtIndex) {
        return orig_getNormalSessionAtIndex ? orig_getNormalSessionAtIndex(self, _cmd, index, fulfilled) : nil;
    }
    id session = [HBFriendGroupController groupAtIndex:(NSUInteger)index top:NO manager:self];
    if (session) {
        if (fulfilled) *fulfilled = YES;
        return session;
    }
    return orig_getNormalSessionAtIndex(self, _cmd, index, fulfilled);
}

static id hb_getTopSessionAtIndex(id self, SEL _cmd, NSInteger index, BOOL *fulfilled) {
    if (![HBFriendGroupController isChatGroupEnabled] || !orig_getTopSessionAtIndex) {
        return orig_getTopSessionAtIndex ? orig_getTopSessionAtIndex(self, _cmd, index, fulfilled) : nil;
    }
    id session = [HBFriendGroupController groupAtIndex:(NSUInteger)index top:YES manager:self];
    if (session) {
        if (fulfilled) *fulfilled = YES;
        return session;
    }
    return orig_getTopSessionAtIndex(self, _cmd, index, fulfilled);
}

static void hb_setVisibleUnreadSlienceChatSessionCount(id self, SEL _cmd, NSUInteger count) {
    if (orig_setVisibleUnread) orig_setVisibleUnread(self, _cmd, count);
    if (![HBFriendGroupController isChatGroupEnabled]) return;
    [HBFriendGroupController rebuildSessions:self groupChats:YES];
}

static id hb_getCellDataAtIndexPath(id self, SEL _cmd, id indexPath) {
    id cellData = orig_getCellDataAtIndexPath ? orig_getCellDataAtIndexPath(self, _cmd, indexPath) : nil;
    if (![HBFriendGroupController isChatGroupEnabled]) return cellData;
    return [HBFriendGroupController groupCellDataForSession:cellData] ?: cellData;
}

#pragma mark - NewMainFrameViewController

static id (*orig_tableCellForRow)(id, SEL, id, id) = NULL;
static CGFloat (*orig_tableHeightForRow)(id, SEL, id, id) = NULL;
static BOOL (*orig_canEditRow)(id, SEL, id, id) = NULL;
static void (*orig_handleSelectIndexPath)(id, SEL, id, id) = NULL;

static id hb_tableCellForRow(id self, SEL _cmd, id tableView, id indexPath) {
    id cell = orig_tableCellForRow ? orig_tableCellForRow(self, _cmd, tableView, indexPath) : nil;
    if ([HBFriendGroupController isChatGroupEnabled]) {
        [HBFriendGroupController configureHomeCell:cell];
    }
    return cell;
}

static CGFloat hb_tableHeightForRow(id self, SEL _cmd, id tableView, id indexPath) {
    CGFloat height = orig_tableHeightForRow ? orig_tableHeightForRow(self, _cmd, tableView, indexPath) : 64.0;
    if ([HBFriendGroupController isChatGroupEnabled]) {
        [HBFriendGroupController recordHomeRowHeight:height];
    }
    return height;
}

static BOOL hb_canEditRow(id self, SEL _cmd, id tableView, id indexPath) {
    if ([HBFriendGroupController isChatGroupEnabled]) return YES;
    return orig_canEditRow ? orig_canEditRow(self, _cmd, tableView, indexPath) : NO;
}

static void hb_handleSelectIndexPath(id self, SEL _cmd, id indexPath, id tableView) {
    if (![HBFriendGroupController isChatGroupEnabled]) {
        if (orig_handleSelectIndexPath) orig_handleSelectIndexPath(self, _cmd, indexPath, tableView);
        return;
    }
    if (orig_handleSelectIndexPath) orig_handleSelectIndexPath(self, _cmd, indexPath, tableView);
}

#pragma mark - SessionSelectController

static void (*orig_selectViewWillAppear)(id, SEL, BOOL) = NULL;
static void (*orig_selectLayoutSubviews)(id, SEL) = NULL;

static void hb_selectViewWillAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_selectViewWillAppear) orig_selectViewWillAppear(self, _cmd, animated);
    [HBFriendGroupController setSelecting:YES controller:self];
}

static void hb_selectLayoutSubviews(id self, SEL _cmd) {
    if (orig_selectLayoutSubviews) orig_selectLayoutSubviews(self, _cmd);
}

static void (*orig_selectViewWillDisappear)(id, SEL, BOOL) = NULL;

static void hb_selectViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    if (orig_selectViewWillDisappear) orig_selectViewWillDisappear(self, _cmd, animated);
    [HBGroupService finishPicker:self];
}

#pragma mark - MMHeadImageView

static void (*orig_checkAndUpdateImage)(id, SEL) = NULL;

static void hb_checkAndUpdateImage(id self, SEL _cmd) {
    if (orig_checkAndUpdateImage) orig_checkAndUpdateImage(self, _cmd);
    if (![HBFriendGroupController isChatGroupEnabled]) return;
    [HBFriendGroupController applyGroupAvatar:self fake:YES];
}

#pragma mark - 入口：首页悬浮按钮

@interface HBGroupEntryButton : UIButton
@end

@implementation HBGroupEntryButton

+ (instancetype)shared {
    static HBGroupEntryButton *button = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        button = [HBGroupEntryButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(0, 0, 46, 46);
        button.layer.cornerRadius = 23;
        button.layer.masksToBounds = YES;
        button.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.75];
        [button setTitle:@"群" forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [button addTarget:button action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:button
                                                                             action:@selector(onPan:)];
        [button addGestureRecognizer:pan];
    });
    return button;
}

- (void)onTap {
    UIWindow *window = self.window;
    if (!window) return;

    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (!root) return;

    HBFriendGroupController *list =
        [[HBFriendGroupController alloc] initWithStyle:UITableViewStyleGrouped];
    list.groupChats = YES;
    list.settingsMode = NO;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    [root presentViewController:nav animated:YES completion:nil];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;
    CGPoint translation = [pan translationInView:superview];
    CGPoint center = self.center;
    center.x += translation.x;
    center.y += translation.y;
    center.x = MAX(28, MIN(superview.bounds.size.width - 28, center.x));
    center.y = MAX(80, MIN(superview.bounds.size.height - 100, center.y));
    self.center = center;
    [pan setTranslation:CGPointZero inView:superview];
}

@end

static void hb_showEntryButton(UIWindow *window) {
    if (!window) return;
    HBGroupEntryButton *button = [HBGroupEntryButton shared];
    if (button.superview == window) return;
    [button removeFromSuperview];

    CGFloat width = window.bounds.size.width;
    CGFloat height = window.bounds.size.height;
    button.center = CGPointMake(width - 40, height * 0.62);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    [window addSubview:button];
    [window bringSubviewToFront:button];
}

#pragma mark - 构造器

static void (*orig_mainFrameViewDidAppear)(id, SEL, BOOL) = NULL;

static void hb_mainFrameViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_mainFrameViewDidAppear) orig_mainFrameViewDidAppear(self, _cmd, animated);
    if (![HBFriendGroupController isEnabled]) return;
    hb_showEntryButton([(UIViewController *)self view].window);
    [HBFriendGroupController refreshForHomeActivation];
}

__attribute__((constructor)) static void HBGroupInit(void) {
    // 配置先加载
    [[HBGroupConfig shared] reload];

    // 会话列表数据源
    HBHookMetaClass("MainSessionMgr", "rebuildMainSessions", (IMP)hb_rebuildMainSessions, (void **)&orig_rebuildMainSessions);
    HBHookMetaClass("MainSessionMgr", "setVisibleUnreadSlienceChatSessionCount:", (IMP)hb_setVisibleUnreadSlienceChatSessionCount, (void **)&orig_setVisibleUnread);
    HBHookMetaClass("MainSessionMgr", "getNormalSessionAtIndex:fulFilled:", (IMP)hb_getNormalSessionAtIndex, (void **)&orig_getNormalSessionAtIndex);
    HBHookMetaClass("MainSessionMgr", "getTopSessionAtIndex:fulFilled:", (IMP)hb_getTopSessionAtIndex, (void **)&orig_getTopSessionAtIndex);
    // 原版这两个是挂在 MainFrameLogicController 的元类上
    HBHookMetaClass("MainFrameLogicController", "getLastFrontSessionArray", (IMP)hb_getLastFrontSessionArray, (void **)&orig_getLastFrontSessionArray);
    HBHookMetaClass("MainFrameLogicController", "getCellDataAtIndexPath:", (IMP)hb_getCellDataAtIndexPath, (void **)&orig_getCellDataAtIndexPath);
    // 旧版微信这几个在 MainSessionMgr 上，一并挂上做兼容
    HBHookMetaClass("MainSessionMgr", "getLastFrontSessionArray", (IMP)hb_getLastFrontSessionArray, (void **)&orig_getLastFrontSessionArray);
    HBHookMetaClass("MainSessionMgr", "getCellDataAtIndexPath:", (IMP)hb_getCellDataAtIndexPath, (void **)&orig_getCellDataAtIndexPath);

    // 首页
    HBHookClass("NewMainFrameViewController", "tableView:cellForRowAtIndexPath:", (IMP)hb_tableCellForRow, (void **)&orig_tableCellForRow);
    HBHookClass("NewMainFrameViewController", "tableView:heightForRowAtIndexPath:", (IMP)hb_tableHeightForRow, (void **)&orig_tableHeightForRow);
    HBHookClass("NewMainFrameViewController", "tableView:canEditRowAtIndexPath:", (IMP)hb_canEditRow, (void **)&orig_canEditRow);
    HBHookClass("NewMainFrameViewController", "handleSelectIndexPath:tableView:", (IMP)hb_handleSelectIndexPath, (void **)&orig_handleSelectIndexPath);
    HBHookClass("NewMainFrameViewController", "viewDidAppear:", (IMP)hb_mainFrameViewDidAppear, (void **)&orig_mainFrameViewDidAppear);

    // 选群界面
    HBHookClass("SessionSelectController", "viewWillAppear:", (IMP)hb_selectViewWillAppear, (void **)&orig_selectViewWillAppear);
    HBHookClass("SessionSelectController", "layoutSubviews", (IMP)hb_selectLayoutSubviews, (void **)&orig_selectLayoutSubviews);
    HBHookClass("SessionSelectController", "viewWillDisappear:", (IMP)hb_selectViewWillDisappear, (void **)&orig_selectViewWillDisappear);

    // 头像
    HBHookClass("MMHeadImageView", "checkAndUpdateImage", (IMP)hb_checkAndUpdateImage, (void **)&orig_checkAndUpdateImage);
}
