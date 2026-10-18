#import "ShareMenuConfig.h"

// ============================================================
//  分享/转发面板项目：抓取 + 自定义隐藏
//
//  面板出现的两种形态都要覆盖：
//    A. 新控制器弹出   → UIViewController -viewDidAppear: 能感知
//    B. 只是加在当前页面/窗口上的视图（实测这种最常见）→ 没有任何控制器回调
//  所以除了 A，这里还做了两件事：
//    · UIWindow -sendEvent: 钩子：用户点开面板后 0.25 秒扫一次（带防抖）
//    · 2 秒兜底扫描（节点数与深度都有上限），防止某些路径不经过 sendEvent:
//
//  识别不依赖文字（文字只是加分项）：
//    · 文字特征：同一视图里同时有「转发给…」和「取消」            → 直接认定
//    · 结构特征：宽度 ≈ 满屏、高度 250~0.88屏、内部有 ≥4 个「图标+标题」格子 → 认定
//  项目识别：从每个带文本的视图往上找「图标 + 标题」的一格（宽 40~150、高 40~190、≥2 子视图）。
//  隐藏：命中就 hidden=YES，同排等大的格子按原间距重排（不留洞）。
//
//  诊断：每次抓到面板都会把结构缓存到 wczz.share.lastTree，
//        「抓取详情」在面板关掉后依然能显示上次抓到的内容
//        （面板是模态的，进设置页时它已经消失，不可能现场抓）。
//
//  存储：NSUserDefaults wczz.share.entries = @[ @{t: title, h: @(hidden), c: @(seen)} ]
// ============================================================

NSString * const WCZZShareMenuTitleKey  = @"t";
NSString * const WCZZShareMenuHiddenKey = @"h";
NSString * const WCZZShareMenuSeenKey   = @"c";

static NSString *const kWCZZShareStoreKey     = @"wczz.share.entries";
static NSString *const kWCZZShareEnabledKey   = @"wczz.share.enabled";
static NSString *const kWCZZShareReflowKey    = @"wczz.share.reflow";
static NSString *const kWCZZShareLastTreeKey  = @"wczz.share.lastTree";
static NSString *const kWCZZShareLastTreeTime = @"wczz.share.lastTreeTime";

static CFAbsoluteTime WCZZShareLastSheetTime = 0;
CFAbsoluteTime WCZZShareMenuLastActivity(void) { return WCZZShareLastSheetTime; }

#pragma mark - 存储

static BOOL WCZZShareFlag(NSString *key, BOOL fallback) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d objectForKey:key];
    return v == nil ? fallback : [v boolValue];
}

BOOL WCZZShareMenuIsEnabled(void) { return WCZZShareFlag(kWCZZShareEnabledKey, YES); }

void WCZZShareMenuSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWCZZShareEnabledKey];
}

static BOOL WCZZShareReflowEnabled(void) { return WCZZShareFlag(kWCZZShareReflowKey, YES); }

NSArray<NSDictionary *> *WCZZShareMenuLoadEntries(void) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    id raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kWCZZShareStoreKey];
    if ([raw isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)raw) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id title = ((NSDictionary *)item)[WCZZShareMenuTitleKey];
            if (![title isKindOfClass:[NSString class]] || ![(NSString *)title length]) continue;
            id hidden = ((NSDictionary *)item)[WCZZShareMenuHiddenKey];
            id seen = ((NSDictionary *)item)[WCZZShareMenuSeenKey];
            [out addObject:@{
                WCZZShareMenuTitleKey:  title,
                WCZZShareMenuHiddenKey: @([hidden respondsToSelector:@selector(boolValue)] ? [hidden boolValue] : NO),
                WCZZShareMenuSeenKey:   @([seen respondsToSelector:@selector(integerValue)] ? [seen integerValue] : 1),
            }];
        }
    }
    return out;
}

void WCZZShareMenuSaveEntries(NSArray<NSDictionary *> *entries) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (entries.count == 0) {
        [d removeObjectForKey:kWCZZShareStoreKey];
    } else {
        [d setObject:entries forKey:kWCZZShareStoreKey];
    }
    [d synchronize];
}

static NSInteger WCZZShareIndexForTitle(NSArray<NSDictionary *> *entries, NSString *title) {
    for (NSInteger i = 0; i < (NSInteger)entries.count; i++) {
        id t = entries[(NSUInteger)i][WCZZShareMenuTitleKey];
        if ([t isKindOfClass:[NSString class]] && [t isEqualToString:title]) return i;
    }
    return -1;
}

BOOL WCZZShareMenuIsTitleHidden(NSString *title) {
    if (![title isKindOfClass:[NSString class]] || !title.length) return NO;
    NSArray<NSDictionary *> *entries = WCZZShareMenuLoadEntries();
    NSInteger idx = WCZZShareIndexForTitle(entries, title);
    if (idx < 0) return NO;
    return [entries[(NSUInteger)idx][WCZZShareMenuHiddenKey] boolValue];
}

void WCZZShareMenuSetTitleHidden(NSString *title, BOOL hidden) {
    if (![title isKindOfClass:[NSString class]] || !title.length) return;
    NSMutableArray<NSDictionary *> *entries = [WCZZShareMenuLoadEntries() mutableCopy];
    NSInteger idx = WCZZShareIndexForTitle(entries, title);
    if (idx < 0) {
        [entries addObject:@{WCZZShareMenuTitleKey: title,
                             WCZZShareMenuHiddenKey: @(hidden),
                             WCZZShareMenuSeenKey: @(1)}];
    } else {
        NSMutableDictionary *item = [entries[(NSUInteger)idx] mutableCopy];
        item[WCZZShareMenuHiddenKey] = @(hidden);
        entries[(NSUInteger)idx] = item;
    }
    WCZZShareMenuSaveEntries(entries);
}

void WCZZShareMenuResetAll(void) { WCZZShareMenuSaveEntries(@[]); }

#pragma mark - 视图工具

static NSString *WCZZShareClassName(id obj) {
    if (!obj) return @"(nil)";
    NSString *s = NSStringFromClass([obj class]);
    return s ?: @"(?)";
}

static NSString *WCZZShareFrameString(UIView *v) {
    if (!v) return @"(nil)";
    CGRect r = v.frame;
    return [NSString stringWithFormat:@"(%.0f,%.0f %.0fx%.0f)", r.origin.x, r.origin.y,
            r.size.width, r.size.height];
}

// 取任意控件上的文本：UILabel 快路径，其余用 KVC 兜底
static NSString *WCZZShareTextOf(UIView *v) {
    if (!v) return nil;
    @try {
        if ([v isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)v).text;
            if ([t isKindOfClass:[NSString class]] && t.length) return t;
        }
        if ([v isKindOfClass:[UIButton class]]) {
            NSString *t = [(UIButton *)v titleForState:UIControlStateNormal];
            if ([t isKindOfClass:[NSString class]] && t.length) return t;
        }
        static NSArray<NSString *> *keys = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            keys = @[@"text", @"attributedText", @"title", @"menuTitle", @"itemTitle"];
        });
        for (NSString *key in keys) {
            SEL sel = NSSelectorFromString(key);
            if (![v respondsToSelector:sel]) continue;
            id val = [v valueForKey:key];
            if ([val isKindOfClass:[NSString class]] && [(NSString *)val length]) return val;
            if ([val isKindOfClass:[NSAttributedString class]]) {
                NSString *s = [(NSAttributedString *)val string];
                if (s.length) return s;
            }
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

static void WCZZShareCollectTexts(UIView *v, NSInteger depth, NSMutableSet<NSString *> *out) {
    if (!v || depth > 8 || out.count > 400) return;
    NSString *t = WCZZShareTextOf(v);
    if (t.length) [out addObject:t];
    for (UIView *s in v.subviews) WCZZShareCollectTexts(s, depth + 1, out);
}

// 「一格」：图标 + 标题
static BOOL WCZZShareIsItemCell(UIView *v) {
    if (!v || v.hidden) return NO;
    CGRect r = v.frame;
    if (CGRectGetWidth(r) < 40.0 || CGRectGetWidth(r) > 150.0) return NO;
    if (CGRectGetHeight(r) < 40.0 || CGRectGetHeight(r) > 190.0) return NO;
    if (v.subviews.count < 2) return NO;
    BOOL hasIcon = NO, hasText = NO;
    for (UIView *g in v.subviews) {
        if ([g isKindOfClass:[UIImageView class]]) hasIcon = YES;
        if (WCZZShareTextOf(g).length) hasText = YES;
    }
    return hasIcon && hasText;
}

// 这一块里有多少个「一格」
static NSInteger WCZZShareCountCells(UIView *root) {
    if (!root) return 0;
    NSInteger count = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@(0)];
    NSInteger guard = 0;
    while (stack.count && guard < 600 && count < 12) {
        UIView *v = stack.lastObject;
        NSNumber *d = depths.lastObject;
        [stack removeLastObject];
        [depths removeLastObject];
        guard++;
        NSInteger depth = d.integerValue;
        if (depth > 5) continue;
        if (WCZZShareIsItemCell(v)) { count++; continue; }
        for (UIView *s in v.subviews) {
            [stack addObject:s];
            [depths addObject:@(depth + 1)];
        }
    }
    return count;
}

static CGFloat WCZZShareScreenH(void) {
    CGFloat h = 0.0;
    @try { h = CGRectGetHeight([UIScreen mainScreen].bounds); } @catch (__unused NSException *e) {}
    return h > 100.0 ? h : 844.0;
}

BOOL WCZZShareMenuLooksLikeSheet(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.05) return NO;
    if (!view.window) return NO;

    // ① 文字特征
    NSMutableSet<NSString *> *texts = [NSMutableSet set];
    WCZZShareCollectTexts(view, 0, texts);
    if (texts.count > 0) {
        BOOL hasForward = NO, hasCancel = NO;
        for (NSString *t in texts) {
            if ([t rangeOfString:@"转发给"].location != NSNotFound) hasForward = YES;
            if ([t rangeOfString:@"取消"].location != NSNotFound) hasCancel = YES;
        }
        if (hasForward && hasCancel) return YES;
    }

    // ② 结构特征
    CGFloat screenH = WCZZShareScreenH();
    CGRect r = [view convertRect:view.bounds toView:view.window];
    CGFloat h = CGRectGetHeight(r), w = CGRectGetWidth(r);
    CGFloat screenW = CGRectGetWidth(view.window.bounds);
    if (h < 250.0 || h > screenH * 0.88) return NO;
    if (w < screenW * 0.9) return NO;
    if (CGRectGetMinY(r) < screenH * 0.15) return NO;
    if ([WCZZShareClassName(view) containsString:@"TabBar"]) return NO;
    return WCZZShareCountCells(view) >= 4;
}

// 从文本视图往上找「一格」
static UIView *WCZZShareContainerForView(UIView *label, UIView *sheetRoot) {
    if (!label) return nil;
    UIView *v = label;
    for (NSInteger i = 0; i < 6 && v; i++) {
        UIView *p = v.superview;
        if (!p || p == sheetRoot) break;
        if (WCZZShareIsItemCell(p)) return p;
        CGRect r = p.frame;
        BOOL cellSized = CGRectGetWidth(r) > 20.0 && CGRectGetWidth(r) < 150.0 &&
                         CGRectGetHeight(r) > 20.0 && CGRectGetHeight(r) < 190.0;
        if (cellSized && p.subviews.count >= 2) return p;
        v = p;
    }
    return nil;
}

NSDictionary<NSString *, UIView *> *WCZZShareMenuItemsInSheet(UIView *sheet) {
    NSMutableDictionary<NSString *, UIView *> *out = [NSMutableDictionary dictionary];
    if (!sheet) return out;

    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:sheet];
    NSInteger guard = 0;
    while (stack.count && guard < 2500) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        guard++;
        if (WCZZShareTextOf(v).length) [labels addObject:v];
        for (UIView *s in v.subviews) [stack addObject:s];
    }

    for (UIView *lb in labels) {
        NSString *t = WCZZShareTextOf(lb);
        if (![t isKindOfClass:[NSString class]] || !t.length) continue;
        NSString *trimmed = [t stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;
        if ([trimmed rangeOfString:@"转发给"].location != NSNotFound) continue;   // 分组标题
        if ([trimmed isEqualToString:@"取消"]) continue;                          // 取消按钮
        if (trimmed.length > 24) continue;
        UIView *container = WCZZShareContainerForView(lb, sheet);
        if (!container) continue;
        if (!out[trimmed]) out[trimmed] = container;
    }
    return out;
}

// 同排等大格子重排（只在明显是网格时动）
static NSInteger WCZZShareReflowRow(UIView *container) {
    if (!container) return 0;
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *s in container.subviews) {
        if (s.hidden || CGRectIsEmpty(s.frame)) continue;
        [visible addObject:s];
    }
    if (visible.count < 3) return 0;

    CGFloat w0 = CGRectGetWidth(visible[0].frame), h0 = CGRectGetHeight(visible[0].frame);
    for (UIView *v in visible) {
        if (fabs(CGRectGetWidth(v.frame) - w0) > 2.0 || fabs(CGRectGetHeight(v.frame) - h0) > 2.0) {
            return 0;
        }
    }
    NSArray<UIView *> *sorted = [visible sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame)) return NSOrderedAscending;
        if (CGRectGetMinX(a.frame) > CGRectGetMinX(b.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    CGFloat minX = CGRectGetMinX(sorted[0].frame);
    CGFloat originY = CGRectGetMinY(sorted[0].frame);
    CGFloat gap = 8.0;
    if (sorted.count >= 2) {
        CGFloat g = CGRectGetMinX(sorted[1].frame) - CGRectGetMaxX(sorted[0].frame);
        if (g >= 0.0 && g <= 40.0) gap = g;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat x = minX;
    for (UIView *v in sorted) {
        CGRect f = v.frame;
        if (fabs(f.origin.x - x) > 0.5 || fabs(f.origin.y - originY) > 0.5) {
            f.origin.x = x;
            f.origin.y = originY;
            v.frame = f;
        }
        x = CGRectGetMaxX(f) + gap;
    }
    [CATransaction commit];
    return (NSInteger)sorted.count;
}

#pragma mark - 抓取 / 应用 / 缓存结构

NSInteger WCZZShareMenuCaptureFromSheet(UIView *sheet) {
    NSDictionary<NSString *, UIView *> *items = WCZZShareMenuItemsInSheet(sheet);
    if (items.count == 0) return 0;

    NSMutableArray<NSDictionary *> *entries = [WCZZShareMenuLoadEntries() mutableCopy];
    NSInteger added = 0;
    for (NSString *title in items) {
        NSInteger idx = WCZZShareIndexForTitle(entries, title);
        if (idx < 0) {
            [entries addObject:@{WCZZShareMenuTitleKey: title,
                                 WCZZShareMenuHiddenKey: @NO,
                                 WCZZShareMenuSeenKey: @(1)}];
            added++;
        } else {
            NSMutableDictionary *item = [entries[(NSUInteger)idx] mutableCopy];
            NSInteger seen = [item[WCZZShareMenuSeenKey] integerValue] + 1;
            item[WCZZShareMenuSeenKey] = @(seen);
            entries[(NSUInteger)idx] = item;
        }
    }
    if (added > 0) WCZZShareMenuSaveEntries(entries);

    // 缓存结构（面板是模态的，进设置页时它已经不在了，只能看缓存）
    NSMutableString *tree = [NSMutableString string];
    [tree appendFormat:@"面板 %@ %@  共 %lu 个可隐藏项\n\n",
        WCZZShareClassName(sheet), WCZZShareFrameString(sheet), (unsigned long)items.count];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:sheet];
    NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@(0)];
    NSInteger guard = 0;
    while (stack.count && guard < 800 && tree.length < 12000) {
        UIView *v = stack.lastObject;
        NSNumber *d = depths.lastObject;
        [stack removeLastObject];
        [depths removeLastObject];
        guard++;
        NSInteger depth = d.integerValue;
        if (depth > 4) continue;
        NSMutableString *indent = [NSMutableString string];
        for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
        NSString *text = WCZZShareTextOf(v);
        [tree appendFormat:@"%@%@ %@%@%@\n", indent, WCZZShareClassName(v),
            WCZZShareFrameString(v), v.hidden ? @" hidden" : @"",
            text.length ? [NSString stringWithFormat:@" 「%@」", text] : @""];
        for (UIView *s in v.subviews) {
            [stack addObject:s];
            [depths addObject:@(depth + 1)];
        }
    }
    NSUserDefaults *dflt = [NSUserDefaults standardUserDefaults];
    [dflt setObject:tree forKey:kWCZZShareLastTreeKey];
    [dflt setObject:@([[NSDate date] timeIntervalSince1970]) forKey:kWCZZShareLastTreeTime];
    [dflt synchronize];

    return added;
}

NSInteger WCZZShareMenuApplyToSheet(UIView *sheet) {
    NSDictionary<NSString *, UIView *> *items = WCZZShareMenuItemsInSheet(sheet);
    if (items.count == 0) return 0;

    NSInteger hidden = 0;
    NSMutableSet<UIView *> *parents = [NSMutableSet set];
    for (NSString *title in items) {
        if (!WCZZShareMenuIsTitleHidden(title)) continue;
        UIView *container = items[title];
        if (!container.hidden) {
            container.hidden = YES;
            hidden++;
        }
        if (container.superview) [parents addObject:container.superview];
    }
    if (hidden > 0 && WCZZShareReflowEnabled()) {
        for (UIView *p in parents) WCZZShareReflowRow(p);
    }
    return hidden;
}

void WCZZShareMenuHandleHost(UIViewController *host) {
    if (!WCZZShareMenuIsEnabled() || !host) return;
    if (![host isKindOfClass:[UIViewController class]]) return;
    if (!host.isViewLoaded) return;

    UIView *root = host.view;
    if (!WCZZShareMenuLooksLikeSheet(root)) return;

    WCZZShareLastSheetTime = CACurrentMediaTime();
    WCZZShareMenuCaptureFromSheet(root);
    WCZZShareMenuApplyToSheet(root);
}

#pragma mark - 找面板 / 触发扫描

static UIWindow *WCZZShareKeyWindow(void) {
    UIWindow *win = nil;
    @try {
        win = [UIApplication sharedApplication].keyWindow;
        if (!win) {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
        }
    } @catch (__unused NSException *e) {}
    return win;
}

UIView *WCZZShareMenuFindOpenSheet(void) {
    NSArray<UIWindow *> *windows = nil;
    @try { windows = [UIApplication sharedApplication].windows; } @catch (__unused NSException *e) {}
    if (windows.count == 0) {
        UIWindow *win = WCZZShareKeyWindow();
        windows = win ? @[win] : @[];
    }
    for (UIWindow *win in [windows reverseObjectEnumerator]) {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
        NSInteger guard = 0;
        while (stack.count && guard < 1800) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            guard++;
            if (WCZZShareMenuLooksLikeSheet(v)) return v;
            for (UIView *s in v.subviews) [stack addObject:s];
        }
    }
    return nil;
}

NSInteger WCZZShareMenuCaptureOpenSheet(void) {
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return -1;
    WCZZShareLastSheetTime = CACurrentMediaTime();
    NSInteger added = WCZZShareMenuCaptureFromSheet(sheet);
    WCZZShareMenuApplyToSheet(sheet);
    return added;
}

NSInteger WCZZShareMenuApplyOpenSheet(void) {
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return -1;
    return WCZZShareMenuApplyToSheet(sheet);
}

// 扫一次：找到面板就抓取 + 应用
static void WCZZShareScanOnce(void) {
    if (!WCZZShareMenuIsEnabled()) return;
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return;
    WCZZShareLastSheetTime = CACurrentMediaTime();
    WCZZShareMenuCaptureFromSheet(sheet);
    WCZZShareMenuApplyToSheet(sheet);
}

// 防抖：0.25 秒内多次触发只扫一次
static void WCZZShareScheduleScan(void) {
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        scheduled = NO;
        WCZZShareScanOnce();
    });
}

// UIWindow -sendEvent:（点击后就扫一次；不依赖任何控制器回调）
static void (*WCZZShareOrigSendEvent)(id, SEL, UIEvent *);
static void WCZZShareSendEvent(id self, SEL _cmd, UIEvent *event) {
    if (WCZZShareOrigSendEvent) WCZZShareOrigSendEvent(self, _cmd, event);
    @try {
        if (event.type == UIEventTypeTouches) WCZZShareScheduleScan();
    } @catch (__unused NSException *e) {}
}

static void WCZZShareInstallSendEventHook(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = objc_getClass("UIWindow");
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, @selector(sendEvent:));
    if (!m) return;
    WCZZShareOrigSendEvent = (void (*)(id, SEL, UIEvent *))method_getImplementation(m);
    method_setImplementation(m, (IMP)WCZZShareSendEvent);
    installed = YES;
}

__attribute__((constructor)) static void WCZZShareMenuBootstrap(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WCZZShareInstallSendEventHook();
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                        repeats:YES
                                          block:^(NSTimer *timer) {
            WCZZShareScanOnce();
        }];
    });
}

#pragma mark - 诊断

NSString *WCZZShareMenuDebugDump(void) {
    NSMutableString *out = [NSMutableString string];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *cached = [d stringForKey:kWCZZShareLastTreeKey];
    NSNumber *cachedAt = [d objectForKey:kWCZZShareLastTreeTime];

    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (sheet) {
        [out appendString:@"[当前面板仍在屏幕上]\n"];
        [out appendFormat:@"%@ %@\n\n", WCZZShareClassName(sheet), WCZZShareFrameString(sheet)];
    } else {
        [out appendString:@"[当前没有打开的面板]\n"];
        if (cachedAt) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:[cachedAt doubleValue]];
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"MM-dd HH:mm:ss";
            [out appendFormat:@"下面是上次抓到的面板结构（%@）\n\n", [fmt stringFromDate:date]];
        }
    }

    if (cached.length) {
        [out appendString:cached];
    } else if (!sheet) {
        [out appendString:@"还没有抓到过面板。\n请先点图片右下角的「…」打开一次分享面板（停 1 秒），再回来点这里。\n"];
    }

    [out appendString:@"\n=== 已登记项目 ===\n"];
    NSArray<NSDictionary *> *entries = WCZZShareMenuLoadEntries();
    if (entries.count == 0) {
        [out appendString:@"（空）\n"];
    } else {
        for (NSDictionary *e in entries) {
            [out appendFormat:@"%@  %@  (见过 %@ 次)\n",
             [e[WCZZShareMenuHiddenKey] boolValue] ? @"隐藏" : @"显示",
             e[WCZZShareMenuTitleKey], e[WCZZShareMenuSeenKey]];
        }
    }
    return out;
}
