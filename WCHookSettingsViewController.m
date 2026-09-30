#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>


#import "WeChatHeaders.h"
#import "WCHookSettingsManager.h"
#import "WCHookTableViewFactory.h"

@interface WCHookSettingsViewController : UIViewController
@property (nonatomic, strong) WCTableViewManager *tableManager;
@property (nonatomic, strong) NSArray<WCHookSettingSection *> *sections;
@property (nonatomic, strong) UIView *topFillerView;
@end

@implementation WCHookSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = WCHookPluginName;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wchook_handleSettingChanged:)
                                                 name:@"com.wchook.notification.swipeQuoteStateDidChange"
                                               object:nil];

    CGRect frame = self.view.bounds;

    self.tableManager = [WCHookTableViewFactory tableManagerWithFrame:frame style:UITableViewStyleGrouped];
    if (!self.tableManager) {
        return;
    }

    UITableView *tableView = self.tableManager.tableView;
    UIColor *backgroundColor = tableView.backgroundColor ?: [UIColor systemGroupedBackgroundColor];

    UIView *topFillerView = [[UIView alloc] initWithFrame:CGRectZero];
    topFillerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topFillerView.backgroundColor = backgroundColor;
    self.topFillerView = topFillerView;

    self.view.backgroundColor = backgroundColor;
    [self.view addSubview:topFillerView];

    if ([self.tableManager respondsToSelector:@selector(addTableViewToSuperView:)]) {
        [self.tableManager addTableViewToSuperView:self.view];
    } else if (tableView) {
        [self.view addSubview:tableView];
    }

    tableView.frame = frame;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (@available(iOS 11.0, *)) {
        tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    tableView.tableFooterView = [UIView new];

    [self reloadTableData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadTableData];
}

- (void)wchook_handleSettingChanged:(__unused NSNotification *)notification {
    [self reloadTableData];
}

- (void)reloadTableData {
    if (!self.tableManager) {
        return;
    }

    self.sections = [WCHookSettings() currentSections];
    [self wchook_bindAuxiliaryActions];
    [self.tableManager clearAllSection];

    for (WCHookSettingSection *sectionModel in self.sections) {
        id section = [WCHookTableViewFactory sectionWithHeader:sectionModel.headerTitle
                                                       footer:sectionModel.footerTitle];
        if (!section) {
            continue;
        }

        for (WCHookSettingItem *item in sectionModel.items) {
            id cell = nil;
            switch (item.kind) {
            case WCHookSettingItemKindToggle: {
                cell = [WCHookTableViewFactory switchCellWithTitle:item.title
                                                        descriptor:item.subtitle
                                                                on:item.isOn
                                                            target:item
                                                            action:@selector(wchook_handleToggleControl:)];
                break;
            }
            case WCHookSettingItemKindNavigation: {
                UITableViewCellAccessoryType accessory = item.actionHandler ? UITableViewCellAccessoryDisclosureIndicator
                                                                            : UITableViewCellAccessoryNone;
                cell = [WCHookTableViewFactory navigationCellWithTitle:item.title
                                                                detail:item.detail
                                                                target:item
                                                                action:@selector(wchook_handleSelection:)
                                                        accessoryType:accessory];
                break;
            }
            }

            if (!cell) {
                continue;
            }

            [WCHookTableViewFactory addCell:cell toSection:section];
        }

        [WCHookTableViewFactory addSection:section toManager:self.tableManager];
    }

    [WCHookTableViewFactory reloadTableView:self.tableManager.tableView];
}

- (void)wchook_bindAuxiliaryActions {
}

- (void)wchook_openURLString:(NSString *)URLString {
    if (URLString.length == 0) {
        return;
    }

    NSURL *url = [NSURL URLWithString:URLString];
    if (!url) {
        return;
    }

    UIApplication *application = [UIApplication sharedApplication];
    if (!application) {
        return;
    }

    if (@available(iOS 10.0, *)) {
        [application openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [application openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self wchook_layoutContentViews];
}

- (void)wchook_layoutContentViews {
    if (!self.tableManager) {
        return;
    }

    UITableView *tableView = self.tableManager.tableView;
    if (!tableView) {
        return;
    }

    CGRect bounds = self.view.bounds;
    CGFloat topOffset = [self wchook_calculatedNavigationContentBottom];
    CGFloat height = CGRectGetHeight(bounds) - topOffset;
    if (height < 0.0f) {
        height = 0.0f;
    }

    CGRect targetFrame = CGRectMake(CGRectGetMinX(bounds), topOffset, CGRectGetWidth(bounds), height);
    if (!CGRectEqualToRect(tableView.frame, targetFrame)) {
        tableView.frame = targetFrame;
    }

    UIView *fillerView = self.topFillerView;
    if (fillerView) {
        CGRect fillerFrame = CGRectMake(0.0f, 0.0f, CGRectGetWidth(bounds), topOffset);
        if (!CGRectEqualToRect(fillerView.frame, fillerFrame)) {
            fillerView.frame = fillerFrame;
        }
    }

    SEL insetSelector = @selector(setTopInsetUnderContentViewY:);
    if ([tableView respondsToSelector:insetSelector]) {
        ((void (*)(id, SEL, double))objc_msgSend)(tableView, insetSelector, topOffset);
    }
}

- (CGFloat)wchook_calculatedNavigationContentBottom {
    UINavigationController *navigationController = self.navigationController;
    if (!navigationController) {
        if (@available(iOS 11.0, *)) {
            return self.view.safeAreaInsets.top;
        }
        return 0.0f;
    }

    UINavigationBar *navigationBar = navigationController.navigationBar;
    if (!navigationBar) {
        if (@available(iOS 11.0, *)) {
            return self.view.safeAreaInsets.top;
        }
        return 0.0f;
    }

    CGRect referenceRect = navigationBar.bounds;
    SEL navigationContentSelector = @selector(navigationContentView);
    if ([navigationBar respondsToSelector:navigationContentSelector]) {
        UIView *contentView = ((UIView *(*)(id, SEL))objc_msgSend)(navigationBar, navigationContentSelector);
        if (contentView) {
            referenceRect = contentView.frame;
        }
    }

    CGRect rectInWindow = [navigationBar convertRect:referenceRect toView:nil];
    CGRect rectInView = [self.view convertRect:rectInWindow fromView:nil];
    CGFloat bottom = CGRectGetMaxY(rectInView);
    if (bottom > 0.0f) {
        return bottom;
    }

    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (@available(iOS 11.0, *)) {
        insets = self.view.safeAreaInsets;
    }
    return insets.top + CGRectGetHeight(referenceRect);
}


@end
