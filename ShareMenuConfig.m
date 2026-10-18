#import "ShareMenuConfig.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
//  分享/转发面板项目：抓取 + 自定义隐藏（v3）
//
//  v3 相对上一版的三处关键修正：
//    ① 隐藏「外层布局格子」而不是内层包装 —— 内层藏了外层坑还在，就是「有缝隙」的原因；
//       同时把同一行剩余格子**居中重排**（按原间距），缝隙消失。
//    ② 不再抓「转发给」好友那一排：
//       · 好友排是横向可滚动的 → 祖先里有横向滚动视图的格子跳过；
//       · 再按 y 分带，若存在 ≥2 带，跳过最上面一带（好友排永远在最上）。
//       可用 wczz.share.skip_first_row 关掉（默认开）。
//    ③ 面板结构缓存照旧写 wczz.share.lastTree，抓取详情可在面板关掉后查看。
//
//  面板形态：可能是新控制器，也可能只是加在当前页面上的视图 → 三种触发都保留：
//    UIViewController 回调 / UIWindow -sendEvent:（点击后 0.25s）/ 2 秒兜底扫描。
// ============================================================

NSString * const WCZZShareMenuTitleKey  = @"t";
NSString * const WCZZShareMenuHiddenKey = @"h";
NSString * const WCZZShareMenuSeenKey   = @"c";

static NSString *const kWCZZShareStoreKey     = @"wczz.share.entries";
static NSString *const kWCZZShareEnabledKey   = @"wczz.share.enabled";
static NSString *const kWCZZShareReflowKey    = @"wczz.share.reflow";
static NSString *const kWCZZShareSkipFirstKey = @"wczz.share.skip_first_row";
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

BOOL WCZZShareMenuSkipsFirstRow(void) { return WCZZShareFlag(kWCZZShareSkipFirstKey, YES); }
void WCZZShareMenuSetSkipsFirstRow(BOOL skip) {
    [[NSUserDefaults standardUserDefaults] setBool:skip forKey:kWCZZShareSkipFirstKey];
}

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
    if (entries.count == 0) [d removeObjectForKey:kWCZZShareStoreKey];
    else [d setObject:entries forKey:kWCZZShareStoreKey];
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

#pragma mark - 基础工具

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

static BOOL WCZZShareIsItemCell(UIView *v) {
    if (!v || v.hidden) return NO;
    CGRect r = v.frame;
    if (CGRectGetWidth(r) < 24.0 || CGRectGetWidth(r) > 220.0) return NO;
    if (CGRectGetHeight(r) < 24.0 || CGRectGetHeight(r) > 240.0) return NO;
    if (v.subviews.count < 2) return NO;
    BOOL hasIcon = NO, hasText = NO;
    for (UIView *g in v.subviews) {
        if (WCZZShareTextOf(g).length) hasText = YES;
        // 图标不一定是 UIImageView：可能是 UIButton / 有背景色 / 有 layer 内容
        if ([g isKindOfClass:[UIImageView class]] || [g isKindOfClass:[UIButton class]] ||
            g.layer.contents != nil ||
            (g.backgroundColor && CGColorGetAlpha(g.backgroundColor.CGColor) > 0.01)) {
            hasIcon = YES;
        }
    }
    return hasText && hasIcon;
}

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

// 分享面板特有的标题（附件面板/表情面板没有这些）—— 用于排除误判
static BOOL WCZZShareHasShareOnlyTitle(NSMutableSet<NSString *> *texts) {
    static NSArray<NSString *> *titles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = @[@"转发给朋友", @"保存图片", @"保存视频", @"用其他应用打开",
                   @"用小程序打开", @"此聊天中的图片视频", @"定位到聊天位置", @"浮窗"];
    });
    for (NSString *t in texts) {
        for (NSString *probe in titles) {
            if ([t rangeOfString:probe].location != NSNotFound) return YES;
        }
    }
    return NO;
}

BOOL WCZZShareMenuLooksLikeSheet(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.05) return NO;
    if (!view.window) return NO;

    NSMutableSet<NSString *> *texts = [NSMutableSet set];
    WCZZShareCollectTexts(view, 0, texts);
    if (texts.count > 0) {
        BOOL hasForward = NO, hasCancel = NO;
        for (NSString *t in texts) {
            if ([t rangeOfString:@"转发给"].location != NSNotFound) hasForward = YES;
            if ([t rangeOfString:@"取消"].location != NSNotFound) hasCancel = YES;
        }
        if (hasForward && hasCancel) return YES;
        // ★ 结构判定必须带分享面板特有标题，否则会把「+」附件面板、表情面板也认成分享面板
        if (!WCZZShareHasShareOnlyTitle(texts)) return NO;
    } else {
        return NO;
    }

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

// 从文本视图往上找「一格」（内层：图标+标题）
static UIView *WCZZShareContainerForView(UIView *label, UIView *sheetRoot) {
    if (!label) return nil;
    UIView *v = label;
    for (NSInteger i = 0; i < 7 && v; i++) {
        UIView *p = v.superview;
        if (!p || p == sheetRoot) break;
        if (WCZZShareIsItemCell(p)) return p;
        // ★ 宽松兜底（v2 有、v3 被我删掉 → 导致整版抓不到）：尺寸像一格 + ≥2 个子视图就认
        CGRect r = p.frame;
        BOOL cellSized = CGRectGetWidth(r) >= 24.0 && CGRectGetWidth(r) <= 220.0 &&
                         CGRectGetHeight(r) >= 24.0 && CGRectGetHeight(r) <= 240.0;
        if (cellSized && p.subviews.count >= 2) return p;
        v = p;
    }
    return nil;
}

// 找到「一行」容器：≥3 个子视图、高度一致、y 接近；返回该行，cellOut=这一行里的那个格子
static UIView *WCZZShareRowContainerFor(UIView *inner, UIView *sheet, UIView **cellOut) {
    if (cellOut) *cellOut = nil;
    if (!inner) return nil;
    UIView *cell = inner;
    UIView *p = inner.superview;
    NSInteger guard = 0;
    while (p && p != sheet && guard++ < 6) {
        NSArray<UIView *> *kids = p.subviews;
        if (kids.count >= 3) {
            CGFloat h0 = 0.0, y0 = 0.0;
            NSInteger count = 0;
            BOOL sameRow = YES;
            for (UIView *k in kids) {
                if (k.hidden || CGRectIsEmpty(k.frame)) continue;
                if (count == 0) { h0 = CGRectGetHeight(k.frame); y0 = CGRectGetMinY(k.frame); }
                count++;
                if (fabs(CGRectGetHeight(k.frame) - h0) > 2.0 ||
                    fabs(CGRectGetMinY(k.frame) - y0) > 2.0) { sameRow = NO; break; }
            }
            if (sameRow && count >= 3) {
                if (cellOut) *cellOut = cell;
                return p;
            }
        }
        cell = p;
        p = p.superview;
    }
    return nil;
}

// 求一组视图的最低公共祖先（限定在 limit 之内）
static UIView *WCZZShareCommonAncestor(NSArray<UIView *> *views, UIView *limit) {
    if (views.count == 0) return nil;
    UIView *candidate = views[0].superview;
    while (candidate && candidate != limit) {
        BOOL all = YES;
        for (UIView *v in views) {
            UIView *p = v;
            BOOL inside = NO;
            while (p) {
                if (p == candidate) { inside = YES; break; }
                p = p.superview;
            }
            if (!inside) { all = NO; break; }
        }
        if (all) return candidate;
        candidate = candidate.superview;
    }
    return nil;
}

// 网格紧凑重排：把可见的 item 按钮按「阅读顺序」重新填回网格槽位（消除隐藏后的空洞）
//  从现有布局推断：列数、每页行数、水平/垂直间距、起点；页宽 = 容器宽
static NSInteger WCZZShareCompactGrid(UIView *grid) {
    if (!grid) return 0;

    NSMutableArray<UIView *> *cells = [NSMutableArray array];
    for (UIView *s in grid.subviews) {
        if (s.hidden || CGRectIsEmpty(s.frame)) continue;
        if (!WCZZShareIsItemCell(s) && !(s.subviews.count >= 2 &&
            CGRectGetWidth(s.frame) >= 24.0 && CGRectGetWidth(s.frame) <= 220.0)) continue;
        [cells addObject:s];
    }
    if (cells.count < 3) return 0;

    // 阅读顺序：先按 y 从上到下，再按 x 从左到右（同一行内）
    [cells sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ay = round(CGRectGetMinY(a.frame) / 8.0), by = round(CGRectGetMinY(b.frame) / 8.0);
        if (ay < by) return NSOrderedAscending;
        if (ay > by) return NSOrderedDescending;
        if (CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame)) return NSOrderedAscending;
        if (CGRectGetMinX(a.frame) > CGRectGetMinX(b.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    CGFloat cellW = CGRectGetWidth(cells[0].frame), cellH = CGRectGetHeight(cells[0].frame);
    CGFloat y0 = CGRectGetMinY(cells[0].frame), x0 = CGFLOAT_MAX;

    // 第一行（y == y0）的按钮 = 每行几个，以及 x 起点/水平间距
    NSMutableArray<UIView *> *firstRow = [NSMutableArray array];
    for (UIView *v in cells) {
        if (fabs(CGRectGetMinY(v.frame) - y0) <= 2.0) [firstRow addObject:v];
    }
    if (firstRow.count < 2) return 0;
    [firstRow sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame)) return NSOrderedAscending;
        if (CGRectGetMinX(a.frame) > CGRectGetMinX(b.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSInteger columns = (NSInteger)firstRow.count;
    x0 = CGRectGetMinX(firstRow[0].frame);
    CGFloat dx = CGRectGetMinX(firstRow[1].frame) - x0;
    if (dx < cellW) dx = cellW + 8.0;

    // 每页行数：不同 y 的个数（最多 4 行）
    NSMutableArray<NSNumber *> *ys = [NSMutableArray array];
    for (UIView *v in cells) {
        CGFloat y = round(CGRectGetMinY(v.frame) / 8.0) * 8.0;
        BOOL seen = NO;
        for (NSNumber *n in ys) if (fabs(n.doubleValue - y) < 4.0) { seen = YES; break; }
        if (!seen) [ys addObject:@(y)];
    }
    if (ys.count == 0) return 0;
    NSInteger rowsPerPage = (NSInteger)MIN((NSInteger)ys.count, 4);

    CGFloat dy = cellH + 8.0;
    if (rowsPerPage >= 2) {
        NSArray<NSNumber *> *sortedYs = [ys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        CGFloat second = sortedYs[1].doubleValue;
        if (second > y0) dy = second - y0;
    }

    CGFloat pageWidth = CGRectGetWidth(grid.bounds);
    if (pageWidth < 100.0) pageWidth = 402.0;
    NSInteger perPage = columns * rowsPerPage;
    if (perPage < 1) return 0;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSInteger i = 0; i < (NSInteger)cells.count; i++) {
        UIView *v = cells[(NSUInteger)i];
        NSInteger page = i / perPage;
        NSInteger slot = i % perPage;
        NSInteger row = slot / columns;
        NSInteger col = slot % columns;
        CGRect f = v.frame;
        f.origin.x = page * pageWidth + x0 + col * dx;
        f.origin.y = y0 + row * dy;
        if (!CGRectEqualToRect(v.frame, f)) v.frame = f;
    }
    [CATransaction commit];
    return (NSInteger)cells.count;
}

// 行内居中重排（缝隙消失）
static NSInteger WCZZShareReflowRowCentered(UIView *row) {
    if (!row) return 0;
    NSMutableArray<UIView *> *visible = [NSMutableArray array];
    for (UIView *s in row.subviews) {
        if (s.hidden || CGRectIsEmpty(s.frame)) continue;
        [visible addObject:s];
    }
    if (visible.count == 0) return 0;

    CGFloat w0 = CGRectGetWidth(visible[0].frame), h0 = CGRectGetHeight(visible[0].frame);
    for (UIView *v in visible) {
        if (fabs(CGRectGetWidth(v.frame) - w0) > 2.0 || fabs(CGRectGetHeight(v.frame) - h0) > 2.0) {
            return 0;       // 不等大 → 不是网格行，别动
        }
    }
    NSArray<UIView *> *sorted = [visible sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        if (CGRectGetMinX(a.frame) < CGRectGetMinX(b.frame)) return NSOrderedAscending;
        if (CGRectGetMinX(a.frame) > CGRectGetMinX(b.frame)) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    CGFloat gap = 8.0;
    if (sorted.count >= 2) {
        CGFloat g = CGRectGetMinX(sorted[1].frame) - CGRectGetMaxX(sorted[0].frame);
        if (g >= 0.0 && g <= 40.0) gap = g;
    }
    CGFloat total = w0 * (CGFloat)sorted.count + gap * (CGFloat)(sorted.count - 1);
    CGFloat x = (CGRectGetWidth(row.bounds) - total) / 2.0;
    if (x < 0.0) x = 0.0;
    CGFloat y = CGRectGetMinY(sorted[0].frame);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (UIView *v in sorted) {
        CGRect f = v.frame;
        if (fabs(f.origin.x - x) > 0.5 || fabs(f.origin.y - y) > 0.5) {
            f.origin.x = x;
            f.origin.y = y;
            v.frame = f;
        }
        x = CGRectGetMaxX(f) + gap;
    }
    [CATransaction commit];
    return (NSInteger)sorted.count;
}

#pragma mark - 收集项目（含好友排过滤）

// 返回 title -> 内层格子；outCells 里是同一格子的外层布局 cell（隐藏用）
static NSDictionary<NSString *, UIView *> *WCZZShareCollectItems(UIView *sheet,
                                                                NSMutableDictionary<NSString *, UIView *> *cellOut,
                                                                NSMutableDictionary<NSString *, UIView *> *rowOut) {
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

    NSMutableDictionary<NSString *, UIView *> *inner = [NSMutableDictionary dictionary];
    for (UIView *lb in labels) {
        NSString *t = WCZZShareTextOf(lb);
        if (![t isKindOfClass:[NSString class]] || !t.length) continue;
        NSString *trimmed = [t stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;
        if ([trimmed rangeOfString:@"转发给"].location != NSNotFound) continue;
        if ([trimmed isEqualToString:@"取消"]) continue;
        if (trimmed.length > 24) continue;
        UIView *container = WCZZShareContainerForView(lb, sheet);
        if (!container) continue;
        if (!inner[trimmed]) inner[trimmed] = container;
    }

    // 按 y 分带，跳过最上面一带（好友排兜底）
    if (WCZZShareMenuSkipsFirstRow() && inner.count > 0) {
        NSMutableArray<NSNumber *> *ys = [NSMutableArray array];
        for (UIView *v in inner.allValues) {
            CGRect r = [v convertRect:v.bounds toView:sheet];
            [ys addObject:@(CGRectGetMinY(r))];
        }
        [ys sortUsingSelector:@selector(compare:)];
        NSInteger bandCount = 0;
        CGFloat lastBandY = -10000.0;
        for (NSNumber *n in ys) {
            if (fabs(n.doubleValue - lastBandY) > 8.0) { bandCount++; lastBandY = n.doubleValue; }
        }
        if (bandCount >= 2) {
            // 把 y 分带（8pt 容差），找「最大间隙」→ 间隙以上的都算好友排
            NSArray<NSNumber *> *sortedYs = [ys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
                return [a compare:b];
            }];
            NSMutableArray<NSNumber *> *bandTops = [NSMutableArray array];
            for (NSNumber *n in sortedYs) {
                if (bandTops.count == 0 ||
                    fabs(n.doubleValue - bandTops.lastObject.doubleValue) > 8.0) {
                    [bandTops addObject:n];
                }
            }
            CGFloat maxGap = 0.0;
            NSInteger splitIndex = 0;      // 间隙之后的第一带
            for (NSInteger i = 1; i < (NSInteger)bandTops.count; i++) {
                CGFloat gap = bandTops[(NSUInteger)i].doubleValue - bandTops[(NSUInteger)(i - 1)].doubleValue;
                if (gap > maxGap) { maxGap = gap; splitIndex = i; }
            }
            if (splitIndex > 0) {
                CGFloat cutoff = bandTops[(NSUInteger)splitIndex].doubleValue - 4.0;
                NSMutableArray<NSString *> *drop = [NSMutableArray array];
                for (NSString *title in inner) {
                    UIView *v = inner[title];
                    CGRect r = [v convertRect:v.bounds toView:sheet];
                    if (CGRectGetMinY(r) < cutoff) [drop addObject:title];
                }
                // 保护：丢掉的不能是大头
                if (drop.count > 0 && drop.count <= (NSInteger)inner.count * 7 / 10) {
                    for (NSString *t in drop) [inner removeObjectForKey:t];
                }
            }
        }
    }

    // ★ 防回归兜底：上面两条过滤若把项目全滤没了，就退回不过滤再收一遍
    if (inner.count == 0) {
        for (UIView *lb in labels) {
            NSString *t = WCZZShareTextOf(lb);
            if (![t isKindOfClass:[NSString class]] || !t.length) continue;
            NSString *trimmed = [t stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!trimmed.length || trimmed.length > 24) continue;
            if ([trimmed rangeOfString:@"转发给"].location != NSNotFound) continue;
            if ([trimmed isEqualToString:@"取消"]) continue;
            UIView *container = WCZZShareContainerForView(lb, sheet);
            if (!container) continue;
            if (!inner[trimmed]) inner[trimmed] = container;
        }
    }

    // 记录每个项目的「外层 cell」和「所在行」
    for (NSString *title in inner) {
        UIView *innerCell = inner[title];
        UIView *cell = nil;
        UIView *row = WCZZShareRowContainerFor(innerCell, sheet, &cell);
        if (cell) cellOut[title] = cell;
        if (row) rowOut[title] = row;
    }
    return inner;
}

NSDictionary<NSString *, UIView *> *WCZZShareMenuItemsInSheet(UIView *sheet) {
    NSMutableDictionary<NSString *, UIView *> *scratchCell = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, UIView *> *scratchRow = [NSMutableDictionary dictionary];
    return WCZZShareCollectItems(sheet, scratchCell, scratchRow);
}

#pragma mark - 抓取 / 应用 / 缓存

NSInteger WCZZShareMenuCaptureFromSheet(UIView *sheet) {
    NSMutableDictionary<NSString *, UIView *> *cells = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, UIView *> *rows = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, UIView *> *items = WCZZShareCollectItems(sheet, cells, rows);
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
            item[WCZZShareMenuSeenKey] = @([item[WCZZShareMenuSeenKey] integerValue] + 1);
            entries[(NSUInteger)idx] = item;
        }
    }
    if (added > 0) WCZZShareMenuSaveEntries(entries);

    // 缓存面板结构（面板关掉后「抓取详情」仍能看到）
    NSMutableString *tree = [NSMutableString string];
    [tree appendFormat:@"面板 %@ %@  共 %lu 项\n\n",
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
    NSMutableDictionary<NSString *, UIView *> *cells = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, UIView *> *rows = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, UIView *> *items = WCZZShareCollectItems(sheet, cells, rows);
    if (items.count == 0) return 0;

    NSInteger hidden = 0;
    NSMutableSet<UIView *> *rowsToReflow = [NSMutableSet set];
    for (NSString *title in items) {
        if (!WCZZShareMenuIsTitleHidden(title)) continue;
        UIView *target = cells[title] ?: items[title];     // 优先隐藏外层布局格子
        if (!target.hidden) {
            target.hidden = YES;
            hidden++;
        }
        UIView *row = rows[title];
        if (row) [rowsToReflow addObject:row];
    }
    if (hidden > 0 && WCZZShareReflowEnabled()) {
        // ① 取所有格子的公共祖先（= 真正的网格容器），对它做紧凑
        NSMutableArray<UIView *> *allCells = [NSMutableArray array];
        for (NSString *title in items) {
            UIView *c = cells[title] ?: items[title];
            if (c) [allCells addObject:c];
        }
        UIView *grid = WCZZShareCommonAncestor(allCells, sheet);
        BOOL compacted = NO;
        if (grid) compacted = (WCZZShareCompactGrid(grid) > 0);
        if (!compacted && grid.superview) compacted = (WCZZShareCompactGrid(grid.superview) > 0);

        // ② 退化方案：逐行居中
        if (!compacted) {
            for (UIView *row in rowsToReflow) WCZZShareReflowRowCentered(row);
        }
    }

    // 注意：这里**不能**再排延迟调用自己（会指数递归）。
    // 反复重压由定时扫描（2s）和 sendEvent 钩子负责。
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

#pragma mark - 找面板 / 触发

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

static void WCZZShareScanOnce(void) {
    if (!WCZZShareMenuIsEnabled()) return;
    UIView *sheet = WCZZShareMenuFindOpenSheet();
    if (!sheet) return;
    WCZZShareLastSheetTime = CACurrentMediaTime();
    WCZZShareMenuCaptureFromSheet(sheet);
    WCZZShareMenuApplyToSheet(sheet);
}

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
    if (cached.length) [out appendString:cached];
    else if (!sheet) [out appendString:@"还没有抓到过面板。\n请先打开一次分享面板（停 1 秒），再回来点这里。\n"];

    [out appendString:@"\n=== 已登记项目 ===\n"];
    NSArray<NSDictionary *> *entries = WCZZShareMenuLoadEntries();
    if (entries.count == 0) [out appendString:@"（空）\n"];
    else {
        for (NSDictionary *e in entries) {
            [out appendFormat:@"%@  %@  (见过 %@ 次)\n",
             [e[WCZZShareMenuHiddenKey] boolValue] ? @"隐藏" : @"显示",
             e[WCZZShareMenuTitleKey], e[WCZZShareMenuSeenKey]];
        }
    }
    [out appendFormat:@"\n跳过好友行: %@\n", WCZZShareMenuSkipsFirstRow() ? @"是" : @"否"];
    return out;
}
