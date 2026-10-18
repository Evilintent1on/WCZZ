#import "ShareMenuConfig.h"
#import <QuartzCore/QuartzCore.h>

// ============================================================
//  分享/转发面板项目：抓取 + 自定义隐藏
//
//  面板特征：同一个视图里同时出现「转发给…」和「取消」。
//  项目：从每个标题 label 往上找「图标 + 标题」的一格（宽 <150、高 <180、≥2 个子视图）。
//  隐藏：命中就 hidden=YES，并把同一排里等大的格子按原间距重排（不留洞）。
//
//  存储：NSUserDefaults wczz.share.entries = @[ @{t: title, h: @(hidden), c: @(seen)} ]
// ============================================================

NSString * const WCZZShareMenuTitleKey  = @"t";
NSString * const WCZZShareMenuHiddenKey = @"h";
NSString * const WCZZShareMenuSeenKey   = @"c";

static NSString *const kWCZZShareStoreKey   = @"wczz.share.entries";
static NSString *const kWCZZShareEnabledKey = @"wczz.share.enabled";
static NSString *const kWCZZShareReflowKey  = @"wczz.share.reflow";

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
    NSInteger idx = WCZZShareIndexForTitle(WCZZShareMenuLoadEntries(), title);
    if (idx < 0) return NO;
    return [WCZZShareMenuLoadEntries()[(NSUInteger)idx][WCZZShareMenuHiddenKey] boolValue];
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

void WCZZShareMenuResetAll(void) {
    WCZZShareMenuSaveEntries(@[]);
}

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

static void WCZZShareCollectTexts(UIView *v, NSInteger depth, NSMutableSet<NSString *> *out) {
    if (!v || depth > 8 || out.count > 400) return;
    if ([v isKindOfClass:[UILabel class]]) {
        NSString *t = ((UILabel *)v).text;
        if ([t isKindOfClass:[NSString class]] && t.length) [out addObject:t];
    }
    for (UIView *s in v.subviews) WCZZShareCollectTexts(s, depth + 1, out);
}

BOOL WCZZShareMenuLooksLikeSheet(UIView *view) {
    if (!view) return NO;
    NSMutableSet<NSString *> *texts = [NSMutableSet set];
    WCZZShareCollectTexts(view, 0, texts);
    if (texts.count == 0) return NO;

    BOOL hasForward = NO, hasCancel = NO;
    for (NSString *t in texts) {
        if ([t rangeOfString:@"转发给"].location != NSNotFound) hasForward = YES;
        if ([t rangeOfString:@"取消"].location != NSNotFound) hasCancel = YES;
    }
    return hasForward && hasCancel;
}

// 从标题 label 往上找「图标 + 标题」的一格
static UIView *WCZZShareContainerForLabel(UILabel *label, UIView *sheetRoot) {
    if (!label) return nil;
    UIView *v = label;
    for (NSInteger i = 0; i < 6 && v; i++) {
        UIView *p = v.superview;
        if (!p || p == sheetRoot) break;
        CGRect r = p.frame;
        BOOL cellSized = CGRectGetWidth(r) > 20.0 && CGRectGetWidth(r) < 150.0 &&
                         CGRectGetHeight(r) > 20.0 && CGRectGetHeight(r) < 180.0;
        if (cellSized) {
            BOOL hasIcon = NO;
            for (UIView *g in p.subviews) {
                if ([g isKindOfClass:[UIImageView class]]) { hasIcon = YES; break; }
            }
            if (hasIcon && p.subviews.count >= 2) return p;
            if (!hasIcon && p.subviews.count >= 2) return p;   // 有些项没有图片
        }
        v = p;
    }
    return nil;
}

NSDictionary<NSString *, UIView *> *WCZZShareMenuItemsInSheet(UIView *sheet) {
    NSMutableDictionary<NSString *, UIView *> *out = [NSMutableDictionary dictionary];
    if (!sheet) return out;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:sheet];
    NSInteger guard = 0;
    while (stack.count && guard < 2000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        guard++;
        if ([v isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)v];
        for (UIView *s in v.subviews) [stack addObject:s];
    }

    for (UILabel *lb in labels) {
        NSString *t = lb.text;
        if (![t isKindOfClass:[NSString class]] || !t.length) continue;
        NSString *trimmed = [t stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;
        if ([trimmed rangeOfString:@"转发给"].location != NSNotFound) continue;   // 分组标题
        if ([trimmed isEqualToString:@"取消"]) continue;                          // 取消按钮
        UIView *container = WCZZShareContainerForLabel(lb, sheet);
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

#pragma mark - 抓取 / 应用

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

static CFAbsoluteTime WCZZShareLastSheetTime = 0;
CFAbsoluteTime WCZZShareMenuLastActivity(void) { return WCZZShareLastSheetTime; }

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

#pragma mark - 打开中的面板

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
    UIWindow *win = WCZZShareKeyWindow();
    if (!win) return nil;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
    NSInteger guard = 0;
    while (stack.count && guard < 1200) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        guard++;
        if (WCZZShareMenuLooksLikeSheet(v)) return v;
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return nil;
}

NSInteger WCZZShareMenuCaptureOpenSheet(void) {
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return -1;               // -1 = 当前没有面板
    return WCZZShareMenuCaptureFromSheet(sheet);
}

NSInteger WCZZShareMenuApplyOpenSheet(void) {
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return -1;
    return WCZZShareMenuApplyToSheet(sheet);
}

NSString *WCZZShareMenuDebugDump(void) {
    NSMutableString *out = [NSMutableString string];

    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (sheet) {
        [out appendFormat:@"分享面板: %@ %@\n\n", WCZZShareClassName(sheet),
         WCZZShareFrameString(sheet)];
        // 递归 dump（4 层，带 label 文本）
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:sheet];
        NSMutableArray<NSNumber *> *depths = [NSMutableArray arrayWithObject:@(0)];
        NSInteger guard = 0;
        while (stack.count && guard < 600) {
            UIView *v = stack.lastObject;
            NSNumber *d = depths.lastObject;
            [stack removeLastObject];
            [depths removeLastObject];
            guard++;
            NSInteger depth = d.integerValue;
            if (depth > 4) continue;
            NSMutableString *indent = [NSMutableString string];
            for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
            NSString *extra = @"";
            if ([v isKindOfClass:[UILabel class]]) {
                NSString *t = ((UILabel *)v).text;
                if (t.length) extra = [NSString stringWithFormat:@" 「%@」", t];
            }
            [out appendFormat:@"%@%@ %@%@%@\n", indent, WCZZShareClassName(v),
             WCZZShareFrameString(v), v.hidden ? @" hidden" : @"", extra];
            for (UIView *s in v.subviews) {
                [stack addObject:s];
                [depths addObject:@(depth + 1)];
            }
        }
    } else {
        [out appendString:@"当前没有打开的分享面板。\n请先打开一次分享/转发面板，再点这里。\n"];
    }

    [out appendString:@"\n=== 已登记项目 ===\n"];
    NSArray<NSDictionary *> *entries = WCZZShareMenuLoadEntries();
    if (entries.count == 0) {
        [out appendString:@"（空：打开一次分享面板会自动抓取）\n"];
    } else {
        for (NSDictionary *e in entries) {
            [out appendFormat:@"%@  %@  (见过 %@ 次)\n",
             [e[WCZZShareMenuHiddenKey] boolValue] ? @"隐藏" : @"显示",
             e[WCZZShareMenuTitleKey], e[WCZZShareMenuSeenKey]];
        }
    }
    return out;
}
