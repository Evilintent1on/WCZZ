// wctabbar —— 只改底部 dock 版（在逆向还原源码基础上修改）
//
// 与原版的差别（本次修改的全部内容）：
//   1) 新增 WCLGIsDockView()：**每个钩子先判断「我是不是底部 dock」**，不是底部的
//      （尤其是顶部导航栏用的那个 ScrollEdgeEffectView）原样透传 → 顶部完全不动。
//   2) 删掉原版的 -objectForInfoDictionaryKey:@"UIDesignRequiresCompatibility" 伪造。
//      那个键是**全局**设计语言开关，改成 @NO 会让整个 App（含顶部）换外观；
//      要「只动底部」就必须放弃它。
//   3) 类解析候选顺序改为「底栏优先」：MMTabBar / WCTabBar / MMTabBarController → UITabBar
//      → iOS 26 的 ScrollEdgeEffectView（该类与顶部共用，靠 WCLGIsDockView() 区分）。
//
// 安装方式与原版二进制一致：C 函数实现 + MSHookMessageEx（不是 %hook 语法糖），
// 因为原版就是运行期解析类名后手动安装的。
//
// 判定「底部 dock」的三重依据（任一成立）：
//   a. 自身类名含 "TabBar"；
//   b. 祖先链含 "TabBar"/"MMTabBarController"，或父视图/祖先的兄弟里有底栏按钮关键字；
//   c. 几何兜底：位于窗口纵向 62% 以下、且高度 < 窗口高度 25%（顶部效果条不满足）。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kWCLGEnabledKey = @"wclg_native_tabbar_enabled";

static NSArray<NSString *> *WCLGTabButtonKeywords(void) {
    return @[@"TabBarButton", @"MMTabBarItemView", @"_UITabButton", @"ItemView"];
}
static NSArray<NSString *> *WCLGPlatterKeywords(void) {
    return @[@"Platter", @"LiquidLens", @"Container"];
}

static BOOL WCLGClassHas(id obj, NSArray<NSString *> *keywords) {
    if (!obj) return NO;
    NSString *cls = NSStringFromClass([obj class]);
    if (!cls) return NO;
    for (NSString *kw in keywords) {
        if ([cls containsString:kw]) return YES;
    }
    return NO;
}

#pragma mark - ★ 底部 dock 判定（决定「动不动顶部」的唯一开关）

static BOOL WCLGIsDockView(UIView *v) {
    if (![v isKindOfClass:[UIView class]]) return NO;

    // a. 自己就是底栏
    NSString *cls = NSStringFromClass([v class]);
    if ([cls containsString:@"TabBar"]) return YES;

    // b. 祖先链 / 兄弟视图里有底栏特征
    UIView *parent = v.superview;
    for (UIView *p = parent; p; p = p.superview) {
        NSString *pc = NSStringFromClass([p class]);
        if ([pc containsString:@"TabBar"] || [pc containsString:@"MMTabBarController"]) return YES;
        for (UIView *sib in p.subviews) {
            if (sib != v && WCLGClassHas(sib, WCLGTabButtonKeywords())) return YES;
        }
    }
    for (UIView *sib in parent.subviews) {
        if (sib != v && WCLGClassHas(sib, WCLGTabButtonKeywords())) return YES;
    }

    // c. 几何兜底：屏幕下方的一条矮条 → 底部 dock（顶部效果条会被排除）
    UIWindow *win = v.window;
    if (win && CGRectGetHeight(win.bounds) > 0) {
        CGRect r = [v convertRect:v.bounds toView:win];
        CGFloat winH = CGRectGetHeight(win.bounds);
        if (CGRectGetMidY(r) > winH * 0.62 && CGRectGetHeight(r) < winH * 0.25) return YES;
    }
    return NO;
}

static BOOL WCLGEnabledForView(UIView *v) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kWCLGEnabledKey]) return NO;
    return WCLGIsDockView(v);           // ← 顶部在这里被挡掉
}

#pragma mark - 几何 / 层级工具

static NSArray<UIView *> *WCLGSortedTabButtons(UIView *bar) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    for (UIView *sub in bar.subviews) {
        if (sub.hidden) continue;
        if (WCLGClassHas(sub, WCLGTabButtonKeywords())) [out addObject:sub];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMinX(a.frame), bx = CGRectGetMinX(b.frame);
        if (ax < bx) return NSOrderedAscending;
        if (ax > bx) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return out;
}

static CGRect WCLGUnionRect(NSArray<UIView *> *buttons) {
    CGRect r = CGRectNull;
    for (UIView *b in buttons) {
        r = CGRectIsNull(r) ? b.frame : CGRectUnion(r, b.frame);
    }
    return r;
}

static UIView *WCLGExistingPlatter(UIView *bar) {
    for (UIView *sub in bar.subviews) {
        if (WCLGClassHas(sub, WCLGPlatterKeywords())) return sub;
    }
    return nil;
}

static void WCLGRemovePlatters(UIView *bar) {
    for (UIView *sub in [bar.subviews copy]) {
        if (WCLGClassHas(sub, WCLGPlatterKeywords())) [sub removeFromSuperview];
    }
}

#pragma mark - 钩子实现（C 函数 + 保存的原实现指针，与原版二进制一致）

static void (*orig_setHidden)(id, SEL, BOOL);
static void (*orig_setStandardAppearance)(id, SEL, id);
static void (*orig_setScrollEdgeAppearance)(id, SEL, id);
static void (*orig_setBackgroundImage)(id, SEL, id);
static void (*orig_setShadowImage)(id, SEL, id);
static void (*orig_setBarTintColor)(id, SEL, id);
static void (*orig_setBackgroundColor)(id, SEL, id);
static void (*orig_layoutSubviews)(id, SEL);
static void (*orig_didAddSubview)(id, SEL, UIView *);
static void (*orig_didMoveToWindow)(id, SEL);
static void (*orig_didMoveToSuperview)(id, SEL);

static void wclg_setHidden(id self, SEL _cmd, BOOL hidden) {
    if (orig_setHidden) orig_setHidden(self, _cmd, hidden);
    if (!WCLGEnabledForView(self)) WCLGRemovePlatters(self);   // 关掉时不残留
}

static void wclg_setStandardAppearance(id self, SEL _cmd, id appearance) {
    if (WCLGEnabledForView(self)) {
        if (orig_setStandardAppearance) orig_setStandardAppearance(self, _cmd, nil);
        return;
    }
    if (orig_setStandardAppearance) orig_setStandardAppearance(self, _cmd, appearance);
}

static void wclg_setScrollEdgeAppearance(id self, SEL _cmd, id appearance) {
    if (WCLGEnabledForView(self)) {
        if (orig_setScrollEdgeAppearance) orig_setScrollEdgeAppearance(self, _cmd, nil);
        return;
    }
    if (orig_setScrollEdgeAppearance) orig_setScrollEdgeAppearance(self, _cmd, appearance);
}

static void wclg_setBackgroundImage(id self, SEL _cmd, id image) {
    if (orig_setBackgroundImage) {
        orig_setBackgroundImage(self, _cmd, WCLGEnabledForView(self) ? nil : image);
    }
}

static void wclg_setShadowImage(id self, SEL _cmd, id image) {
    if (orig_setShadowImage) {
        orig_setShadowImage(self, _cmd, WCLGEnabledForView(self) ? nil : image);
    }
}

static void wclg_setBarTintColor(id self, SEL _cmd, id color) {
    if (orig_setBarTintColor) {
        orig_setBarTintColor(self, _cmd, WCLGEnabledForView(self) ? [UIColor clearColor] : color);
    }
}

static void wclg_setBackgroundColor(id self, SEL _cmd, id color) {
    if (orig_setBackgroundColor) {
        orig_setBackgroundColor(self, _cmd, WCLGEnabledForView(self) ? [UIColor clearColor] : color);
    }
}

// 核心：只在底部 dock 上造浮动胶囊
static void wclg_layoutSubviews(id self, SEL _cmd) {
    if (orig_layoutSubviews) orig_layoutSubviews(self, _cmd);
    if (!WCLGEnabledForView(self)) return;              // 顶部 / 其它位置：原样

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    NSArray<UIView *> *buttons = WCLGSortedTabButtons(self);
    if (buttons.count == 0) {
        [CATransaction commit];
        return;
    }
    CGRect pill = CGRectInset(WCLGUnionRect(buttons), -12.0, -6.0);

    UIView *platter = WCLGExistingPlatter(self);
    if (!platter) {
        UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:nil];
        v.userInteractionEnabled = NO;
        v.opaque = NO;
        v.backgroundColor = [UIColor clearColor];
        [self insertSubview:v atIndex:0];
        platter = v;
    }
    if ([platter isKindOfClass:[UIVisualEffectView class]]) {
        [(UIVisualEffectView *)platter setEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    }
    platter.frame = pill;
    platter.center = CGPointMake(CGRectGetMidX(pill), CGRectGetMidY(pill));
    platter.layer.cornerRadius = CGRectGetHeight(pill) / 2.0;
    platter.layer.masksToBounds = YES;
    platter.hidden = NO;

    for (UIView *b in buttons) {
        b.backgroundColor = [UIColor clearColor];
        [self bringSubviewToFront:b];
    }
    [CATransaction commit];
}

static void wclg_didAddSubview(id self, SEL _cmd, UIView *subview) {
    if (orig_didAddSubview) orig_didAddSubview(self, _cmd, subview);
    if (WCLGEnabledForView(self)) [self setNeedsLayout];
}

static void wclg_didMoveToWindow(id self, SEL _cmd) {
    if (orig_didMoveToWindow) orig_didMoveToWindow(self, _cmd);
    if (!WCLGEnabledForView(self)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [CATransaction commit];
}

static void wclg_didMoveToSuperview(id self, SEL _cmd) {
    if (orig_didMoveToSuperview) orig_didMoveToSuperview(self, _cmd);
    if (!WCLGEnabledForView(self)) WCLGRemovePlatters(self);
}

#pragma mark - 安装（候选顺序：底栏优先）

static void WCLGInstallHooks(void) {
    static BOOL installed = false;
    if (installed) return;
    installed = true;

    Class target = objc_getClass("MMTabBar");
    if (!target) target = objc_getClass("WCTabBar");
    if (!target) target = NSClassFromString(@"MMTabBarController");
    if (!target) target = objc_getClass("UITabBar");
    // iOS 26：底栏效果视图与顶部共用同一个类 → 靠 WCLGIsDockView() 区分，钩子仍可安装
    if (!target) target = NSClassFromString(@"UIKit.ScrollEdgeEffectView");
    if (!target) target = objc_getClass("_TtC5UIKit20ScrollEdgeEffectView");
    if (!target) return;

    MSHookMessageEx(target, @selector(setHidden:),               (IMP)&wclg_setHidden,               (IMP *)&orig_setHidden);
    MSHookMessageEx(target, @selector(setStandardAppearance:),   (IMP)&wclg_setStandardAppearance,   (IMP *)&orig_setStandardAppearance);
    MSHookMessageEx(target, @selector(setScrollEdgeAppearance:), (IMP)&wclg_setScrollEdgeAppearance, (IMP *)&orig_setScrollEdgeAppearance);
    MSHookMessageEx(target, @selector(setBackgroundImage:),      (IMP)&wclg_setBackgroundImage,      (IMP *)&orig_setBackgroundImage);
    MSHookMessageEx(target, @selector(setShadowImage:),          (IMP)&wclg_setShadowImage,          (IMP *)&orig_setShadowImage);
    MSHookMessageEx(target, @selector(setBarTintColor:),         (IMP)&wclg_setBarTintColor,         (IMP *)&orig_setBarTintColor);
    MSHookMessageEx(target, @selector(setBackgroundColor:),      (IMP)&wclg_setBackgroundColor,      (IMP *)&orig_setBackgroundColor);
    MSHookMessageEx(target, @selector(layoutSubviews),           (IMP)&wclg_layoutSubviews,          (IMP *)&orig_layoutSubviews);
    MSHookMessageEx(target, @selector(didAddSubview:),           (IMP)&wclg_didAddSubview,           (IMP *)&orig_didAddSubview);
    MSHookMessageEx(target, @selector(didMoveToWindow),          (IMP)&wclg_didMoveToWindow,          (IMP *)&orig_didMoveToWindow);
    MSHookMessageEx(target, @selector(didMoveToSuperview),       (IMP)&wclg_didMoveToSuperview,       (IMP *)&orig_didMoveToSuperview);
    // 故意不装 -objectForInfoDictionaryKey:（原版用它伪造 UIDesignRequiresCompatibility，
    // 那是全局设计开关，会连顶部一起改）。
}

#pragma mark - 开关（供 wczz 设置页调用）

BOOL WCZZTabBarGlassEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWCLGEnabledKey];
}

// 找到所有底部 dock 视图，开关切换后立即刷新（开→造胶囊，关→拆胶囊）
static void WCLGRefreshDockInView(UIView *root) {
    if (!root) return;
    if (WCLGIsDockView(root)) {
        if (WCZZTabBarGlassEnabled()) {
            [root setNeedsLayout];
        } else {
            WCLGRemovePlatters(root);
        }
    }
    for (UIView *sub in root.subviews) WCLGRefreshDockInView(sub);
}

void WCZZSetTabBarGlassEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWCLGEnabledKey];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *win in [UIApplication sharedApplication].windows) {
            WCLGRefreshDockInView(win);
        }
    });
}

%ctor {
    WCLGInstallHooks();
}
