#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
//  wctabbar v4
//
//  ★ 重要：v3 里我改顶部的那些代码**全部删掉了**（顶部栏对齐、搜索框宽度/高度、
//    按钮居中、标题居中）—— 那些是我在没有实测数据时猜的几何量，就是它把搜索框改坏的。
//    顶部现在与你的原版**完全一致**。
//
//  本版只做两件事：
//    1) 原版逻辑原封不动（擦底 / 关毛玻璃 / 底栏图标对齐 / NSBundle / ScrollEdgeEffectView / 两个底栏钩子）
//    2) 新增「输入框液态」——纯新增一层玻璃垫在输入条后面，不改任何既有布局，
//       用 wclg_input_glass 可以随时关掉
//
//  另外内置一个**诊断模式**：把顶部栏的真实视图树（类名 + frame）打到弹窗里，
//  你截图发我，我按真实数字一次性改对，不再猜。
//    用法：把下面的 WCLG_DIAG 改成 1 → 重新编译安装 → 进微信主界面（几秒后弹窗）
//    → 截图弹窗内容发我 → 改回 0
// ============================================================

#define WCLG_DIAG 1          // ← 1 = 内置诊断（首次启动后自动弹出一次 + 三指长按随时打开）；修完后改 0

// ---------- 微信真实类 ----------
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// 主界面控制器（诊断用；只声明继承关系，不碰它的布局）
@interface NewMainFrameViewController : UIViewController
@end

// ---------- 开关 ----------
static NSString *const kWCLGEnabledKey    = @"wclg_native_tabbar_enabled";  // 总开关（原有）
static NSString *const kWCLGDesignKey     = @"wclg_ios26_design";           // 默认开 = 原版行为
static NSString *const kWCLGInputGlassKey = @"wclg_input_glass";            // 默认开 = 新增的输入框液态

static BOOL WCLGFlag(NSString *key, BOOL fallback) {
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	id v = [d objectForKey:key];
	return v == nil ? fallback : [d boolForKey:key];
}

static BOOL WCLGEnabled(void) {
	static BOOL cached;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cached = WCLGFlag(kWCLGEnabledKey, YES);
	});
	return cached;
}

static BOOL WCLGDesignEnabled(void) { return WCLGFlag(kWCLGDesignKey, YES); }
static BOOL WCLGInputGlassEnabled(void) { return WCLGFlag(kWCLGInputGlassKey, YES); }

// ============================================================
//  原版逻辑：关掉毛玻璃
// ============================================================
static void WCLGKillBlur(UIView *v, NSInteger depth) {
	if (depth > 10) return;
	for (UIView *sub in v.subviews) {
		if ([sub isKindOfClass:[UIVisualEffectView class]]) {
			UIVisualEffectView *vev = (UIVisualEffectView *)sub;
			vev.effect = nil;
			vev.hidden = YES;
			continue;
		}
		WCLGKillBlur(sub, depth + 1);
	}
}

// ============================================================
//  新增：iOS 26 液态玻璃效果（拿不到退回系统材质模糊）
// ============================================================
static UIVisualEffect *WCLGGlassEffect(void) {
	Class glass = NSClassFromString(@"UIGlassEffect");
	if (glass && [glass respondsToSelector:NSSelectorFromString(@"effectWithStyle:")]) {
		@try {
			id e = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glass,
						NSSelectorFromString(@"effectWithStyle:"), 0);
			if ([e isKindOfClass:[UIVisualEffect class]]) return e;
		} @catch (__unused NSException *ex) {}
	}
	return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

// ============================================================
//  新增：输入框液态
//
//  认出输入条的条件（全部满足）：贴底 / 宽度 > 屏宽 60% / 高度 36~170 / 内部含输入控件。
//  最后一条是关键：底栏、Tab 栏这些没有输入控件，绝不会被误判。
//  做法只是在它后面**垫**一层玻璃（index 0、不拦触摸），不改它的 frame / 约束 / 颜色以外的任何东西。
// ============================================================
static BOOL WCLGContainsTextInput(UIView *v, NSInteger depth) {
	if (!v || depth > 6) return NO;
	if ([v isKindOfClass:[UITextView class]] || [v isKindOfClass:[UITextField class]]) return YES;
	for (UIView *s in v.subviews) {
		if (WCLGContainsTextInput(s, depth + 1)) return YES;
	}
	return NO;
}

// 递归找「贴底的输入条」。
// 关键修正（v4 找不到东西的两个原因）：
//   ① v4 只看了 1~2 层子视图 —— 微信聊天页层级更深，改成就地递归到 6 层；
//   ② v4 拿子视图在**自己父视图**里的 frame 去比根视图高度 —— 坐标系不对，
//      现在统一 [c convertRect:c.bounds toView:root] 换算到根视图再判断。
static UIView *WCLGFindInputBarIn(UIView *root, UIView *v, NSInteger depth,
								  CGFloat rootH, CGFloat rootW,
								  UIView **best, CGFloat *bestY) {
	if (!v || depth > 6) return *best;

	CGRect r = [v convertRect:v.bounds toView:root];
	BOOL bottom = CGRectGetMinY(r) > rootH * 0.5;
	BOOL wide = CGRectGetWidth(r) > rootW * 0.5;
	BOOL tall = CGRectGetHeight(r) >= 30.0 && CGRectGetHeight(r) <= 200.0;
	if (bottom && wide && tall && WCLGContainsTextInput(v, 0)) {
		if (CGRectGetMinY(r) > *bestY) { *bestY = CGRectGetMinY(r); *best = v; }
		return *best;   // 命中就不再往下钻（避免找到更里层的输入框本体）
	}
	for (UIView *sub in v.subviews) {
		WCLGFindInputBarIn(root, sub, depth + 1, rootH, rootW, best, bestY);
	}
	return *best;
}

static UIView *WCLGFindInputBar(UIView *root) {
	if (!root) return nil;
	CGFloat H = CGRectGetHeight(root.bounds), W = CGRectGetWidth(root.bounds);
	if (H < 100 || W < 100) return nil;
	UIView *best = nil;
	CGFloat bestY = -1;
	return WCLGFindInputBarIn(root, root, 0, H, W, &best, &bestY);
}

// 把「挡在玻璃前面」的不透明底色清掉：输入条自己 + 它里面挡满的不透明子视图 +
// 只包着它的一层壳（高度不超过输入条的 2.5 倍，避免把整个聊天页清透明）。
static void WCLGClearBackdrop(UIView *bar, UIView *root) {
	if (!bar) return;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	bar.backgroundColor = [UIColor clearColor];
	bar.opaque = NO;
	bar.layer.backgroundColor = [UIColor clearColor].CGColor;

	CGFloat bw = CGRectGetWidth(bar.bounds), bh = CGRectGetHeight(bar.bounds);
	for (UIView *g in bar.subviews) {
		if ([g isKindOfClass:[UIVisualEffectView class]]) continue;
		if (g.backgroundColor && CGColorGetAlpha(g.backgroundColor) > 0.01) {
			g.backgroundColor = [UIColor clearColor];
		}
		if (g.layer.backgroundColor && CGColorGetAlpha(g.layer.backgroundColor) > 0.01) {
			g.layer.backgroundColor = [UIColor clearColor].CGColor;
		}
		g.opaque = NO;
	}

	UIView *sup = bar.superview;
	NSInteger guard = 0;
	while (sup && sup != root && guard < 3) {
		guard++;
		CGRect sr = [sup convertRect:sup.bounds toView:root];
		CGFloat barH = CGRectGetHeight([bar convertRect:bar.bounds toView:root]);
		if (CGRectGetHeight(sr) > barH * 2.5) break;      // 太大 → 不是壳，别清
		if (sup.backgroundColor && CGColorGetAlpha(sup.backgroundColor) > 0.01) {
			sup.backgroundColor = [UIColor clearColor];
		}
		if (sup.layer.backgroundColor && CGColorGetAlpha(sup.layer.backgroundColor) > 0.01) {
			sup.layer.backgroundColor = [UIColor clearColor].CGColor;
		}
		sup.opaque = NO;
		sup = sup.superview;
	}
	(void)bw; (void)bh;
	[CATransaction commit];
}

static const void *kWCLGInputGlassAssocKey = &kWCLGInputGlassAssocKey;

static void WCLGApplyInputGlass(UIViewController *vc) {
	if (!vc || ![vc isKindOfClass:[UIViewController class]]) return;
	if (!vc.isViewLoaded) return;

	UIView *bar = WCLGFindInputBar(vc.view);
	if (!bar || CGRectIsEmpty(bar.bounds)) return;

	// 已经加过就只更新 frame
	UIVisualEffectView *glass = objc_getAssociatedObject(bar, kWCLGInputGlassAssocKey);
	if (!glass) {
		glass = [[UIVisualEffectView alloc] initWithEffect:WCLGGlassEffect()];
		glass.userInteractionEnabled = NO;
		glass.opaque = NO;
		glass.backgroundColor = [UIColor clearColor];
		glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		glass.layer.cornerRadius = 18.0;
		glass.layer.cornerCurve = kCACornerCurveContinuous;
		glass.layer.masksToBounds = YES;
		[bar insertSubview:glass atIndex:0];
		objc_setAssociatedObject(bar, kWCLGInputGlassAssocKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	WCLGClearBackdrop(bar, vc.view);

	CGRect want = CGRectInset(bar.bounds, 2.0, 2.0);
	if (!CGRectEqualToRect(glass.frame, want)) {
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		glass.frame = want;
		[CATransaction commit];
	}
	[bar sendSubviewToBack:glass];
}

// ============================================================
//  原版逻辑：擦掉微信画在底栏上的东西
// ============================================================
static void WCLGStripTabBar(UITabBar *bar) {
	if (!bar || ![bar isKindOfClass:[UITabBar class]]) return;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	bar.translucent = YES;
	bar.opaque = NO;
	bar.backgroundColor = [UIColor clearColor];
	bar.layer.backgroundColor = [UIColor clearColor].CGColor;

	CGFloat bw = CGRectGetWidth(bar.bounds), bh = CGRectGetHeight(bar.bounds);
	for (UIView *sub in bar.subviews) {
		NSString *cn = NSStringFromClass([sub class]);
		if ([cn containsString:@"Platter"] ||
			[cn containsString:@"LiquidLens"] ||
			[cn containsString:@"TabBarButton"] ||
			[cn containsString:@"ItemView"] ||
			[cn containsString:@"Container"] ||
			[cn containsString:@"_UITabButton"]) {
			continue;
		}
		BOOL fullSize = CGRectGetWidth(sub.bounds) >= bw - 1.0 &&
						CGRectGetHeight(sub.bounds) >= bh - 1.0 &&
						CGRectGetWidth(sub.frame) > 1.0 &&
						CGRectGetHeight(sub.frame) > 1.0;
		if (!fullSize) continue;

		sub.hidden = YES;
		sub.backgroundColor = [UIColor clearColor];
		sub.layer.backgroundColor = [UIColor clearColor].CGColor;

		for (UIView *g in sub.subviews) {
			if ([g isKindOfClass:[UIVisualEffectView class]]) {
				((UIVisualEffectView *)g).effect = nil;
			}
			g.opaque = NO;
			if (g.backgroundColor && CGColorGetAlpha(g.backgroundColor) > 0.01) {
				g.backgroundColor = [UIColor clearColor];
			}
			if (g.layer.backgroundColor && CGColorGetAlpha(g.layer.backgroundColor) > 0.01) {
				g.layer.backgroundColor = [UIColor clearColor].CGColor;
			}
		}
	}

	[CATransaction commit];

	WCLGKillBlur(bar, 0);
}

static void WCLGAlignTabBarItems(UITabBar *bar);

static void WCLGStripTabBarDeferred(UITabBar *bar) {
	if (!bar) return;
	static CFAbsoluteTime last = 0;
	CFAbsoluteTime now = CACurrentMediaTime();
	if (now - last < 0.2) return;
	last = now;

	__weak UITabBar *weakBar = bar;
	dispatch_async(dispatch_get_main_queue(), ^{
		WCLGStripTabBar(weakBar);
		WCLGAlignTabBarItems(weakBar);
	});
}

// 原版逻辑：对齐图标
static void WCLGAlignTabBarItems(UITabBar *bar) {
	if (!bar) return;

	UIView *platter = nil;
	for (UIView *sub in bar.subviews) {
		if ([NSStringFromClass([sub class]) containsString:@"Platter"]) {
			platter = sub;
			break;
		}
	}
	if (!platter) return;

	NSMutableArray<UIView *> *items = [NSMutableArray array];
	for (UIView *sub in bar.subviews) {
		if ([NSStringFromClass([sub class]) containsString:@"MMTabBarItemView"]) {
			[items addObject:sub];
		}
	}
	if (items.count == 0) return;

	[items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
		if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
		if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
		return NSOrderedSame;
	}];

	CGRect pf = platter.frame;
	CGFloat n = (CGFloat)items.count;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < (NSInteger)n; i++) {
		UIView *iv = items[i];
		CGPoint c = iv.center;

		c.x = pf.origin.x + pf.size.width * ((CGFloat)i + 0.5) / n;

		CGRect content = CGRectNull;
		for (UIView *g in iv.subviews) {
			if (g.hidden) continue;
			content = CGRectUnion(content, g.frame);
		}
		if (!CGRectIsNull(content)) {
			CGFloat contentMidYInBar = iv.frame.origin.y + CGRectGetMidY(content);
			c.y += CGRectGetMidY(pf) - contentMidYInBar;
		}

		if (fabs(iv.center.x - c.x) < 0.5 && fabs(iv.center.y - c.y) < 0.5) continue;
		iv.center = c;
	}
	[CATransaction commit];
}

// ============================================================
//  原版逻辑：让 UIKit 认为微信没申请旧版设计
// ============================================================
static BOOL WCLGIsMainBundle(NSBundle *b) {
	return b == [NSBundle mainBundle];
}

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
	if (WCLGEnabled() && WCLGDesignEnabled() &&
		WCLGIsMainBundle(self) && [key isEqualToString:@"UIDesignRequiresCompatibility"]) {
		return @NO;
	}
	return %orig;
}

- (NSDictionary *)infoDictionary {
	NSDictionary *d = %orig;
	if (WCLGEnabled() && WCLGDesignEnabled() &&
		WCLGIsMainBundle(self) && d[@"UIDesignRequiresCompatibility"] != nil) {
		NSMutableDictionary *m = [d mutableCopy];
		[m removeObjectForKey:@"UIDesignRequiresCompatibility"];
		return m;
	}
	return d;
}

%end

// ============================================================
//  原版逻辑：关掉滚动边缘效果
// ============================================================
static void (*wclg_orig_SEV_setHidden)(id, SEL, BOOL);
static void wclg_SEV_setHidden(id self, SEL _cmd, BOOL hidden) {
	wclg_orig_SEV_setHidden(self, _cmd, YES);
}

static void (*wclg_orig_SEV_layoutSubviews)(id, SEL);
static void wclg_SEV_layoutSubviews(id self, SEL _cmd) {
	wclg_orig_SEV_layoutSubviews(self, _cmd);
	((UIView *)self).hidden = YES;
}

static void WCLGHookScrollEdgeEffectView(void) {
	static BOOL done = NO;
	if (done) return;
	done = YES;

	Class c = NSClassFromString(@"UIKit.ScrollEdgeEffectView");
	if (!c) c = objc_getClass("_TtC5UIKit20ScrollEdgeEffectView");
	if (!c) return;

	MSHookMessageEx(c, @selector(setHidden:),
		(IMP)wclg_SEV_setHidden, (IMP *)&wclg_orig_SEV_setHidden);
	MSHookMessageEx(c, @selector(layoutSubviews),
		(IMP)wclg_SEV_layoutSubviews, (IMP *)&wclg_orig_SEV_layoutSubviews);
}

#if WCLG_DIAG

// ============================================================
//  内置诊断（WCLG_DIAG = 1 时编译）
//
//  目的：一次抓全，避免来回试。报告含：
//    · 环境（微信/系统版本、四个开关、屏幕尺寸）
//    · 当前控制器链
//    · 底栏：类名/frame/子视图/是否找到 Platter
//    · 输入条：是否找到 + 类名 + frame + 父链 3 层 + 是否已插入玻璃 + 底部半屏视图树
//    · 顶部：fakeNavBarView 树 + 每个子视图相对栏中心的 Δx、searchBar + 父 + 表头 + 表视图
//            contentInset、navigationBar 树 + Δx
//  三指长按窗口可随时重新打开；文本框可滚动、可选中复制。
// ============================================================
static NSString *WCLGShortClass(id obj) {
	if (!obj) return @"(nil)";
	NSString *s = NSStringFromClass([obj class]);
	return s ?: @"(?)";
}

static NSString *WCLGFrameStr(UIView *v, UIView *ref) {
	if (!v) return @"(nil)";
	CGRect r = ref ? [v convertRect:v.bounds toView:ref] : v.frame;
	return [NSString stringWithFormat:@"(%.0f,%.0f %.0fx%.0f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

// 顶部用：相对父视图中心的水平偏移（正数=偏右）
static NSString *WCLGDeltaX(UIView *v) {
	if (!v.superview) return @"";
	CGFloat c = v.center.x, mid = CGRectGetWidth(v.superview.bounds) / 2.0;
	CGFloat d = c - mid;
	return [NSString stringWithFormat:@" Δx=%+.1f", d];
}

static void WCLGDumpTree(UIView *v, NSInteger depth, NSInteger maxDepth,
						 NSMutableString *out, NSString *indent, UIView *ref, BOOL withDelta) {
	if (!v || depth > maxDepth || out.length > 6000) return;
	[out appendFormat:@"%@%@ %@%@%@\n", indent, WCLGShortClass(v), WCLGFrameStr(v, ref),
		v.hidden ? @" hidden" : @"", withDelta ? WCLGDeltaX(v) : @""];
	if (depth == maxDepth) return;
	NSString *next = [indent stringByAppendingString:@"  "];
	for (UIView *sub in v.subviews) {
		WCLGDumpTree(sub, depth + 1, maxDepth, out, next, ref, withDelta);
	}
}

// 只dump 下半屏（找输入条用）
static void WCLGDumpBottomHalf(UIView *root, NSInteger depth, NSInteger maxDepth,
							   NSMutableString *out, NSString *indent) {
	if (!root || depth > maxDepth || out.length > 6000) return;
	CGFloat H = CGRectGetHeight(root.bounds);
	for (UIView *sub in root.subviews) {
		CGRect r = [sub convertRect:sub.bounds toView:root];
		if (CGRectGetMaxY(r) < H * 0.5) continue;         // 完全在上半屏 → 跳过
		[out appendFormat:@"%@%@ %@%@\n", indent, WCLGShortClass(sub), WCLGFrameStr(sub, root),
			sub.hidden ? @" hidden" : @""];
		WCLGDumpBottomHalf(sub, depth + 1, maxDepth, out, [indent stringByAppendingString:@"  "]);
	}
}

static BOOL WCLGViewTreeContains(UIView *v, NSInteger depth, BOOL (^pred)(UIView *)) {
	if (!v || depth > 6) return NO;
	if (pred(v)) return YES;
	for (UIView *s in v.subviews) {
		if (WCLGViewTreeContains(s, depth + 1, pred)) return YES;
	}
	return NO;
}

static UIWindow *WCLGKeyWindow(void) {
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

static UIViewController *WCLGTopMostVC(void) {
	UIViewController *vc = WCLGKeyWindow().rootViewController;
	while (vc.presentedViewController) vc = vc.presentedViewController;
	if ([vc isKindOfClass:[UINavigationController class]]) {
		UIViewController *top = ((UINavigationController *)vc).topViewController;
		if (top) vc = top;
	}
	if ([vc isKindOfClass:[UITabBarController class]]) {
		UIViewController *sel = ((UITabBarController *)vc).selectedViewController;
		if (sel) vc = sel;
	}
	return vc;
}

static void WCLGCollectVCs(UIViewController *vc, NSMutableArray<UIViewController *> *out, NSInteger depth) {
	if (!vc || depth > 8 || out.count > 40) return;
	[out addObject:vc];
	if (vc.presentedViewController) WCLGCollectVCs(vc.presentedViewController, out, depth + 1);
	if ([vc isKindOfClass:[UINavigationController class]]) {
		for (UIViewController *c in ((UINavigationController *)vc).viewControllers) {
			WCLGCollectVCs(c, out, depth + 1);
		}
	}
	if ([vc isKindOfClass:[UITabBarController class]]) {
		for (UIViewController *c in ((UITabBarController *)vc).viewControllers) {
			WCLGCollectVCs(c, out, depth + 1);
		}
	}
	for (UIViewController *c in vc.childViewControllers) {
		WCLGCollectVCs(c, out, depth + 1);
	}
}

static NSString *WCLGBuildReport(void) {
	NSMutableString *o = [NSMutableString string];
	NSBundle *mb = [NSBundle mainBundle];
	NSString *appVer = [mb objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	NSString *build = [mb objectForInfoDictionaryKey:@"CFBundleVersion"];

	[o appendFormat:@"wctabbar 诊断\n微信 %@ (%@)  iOS %@\n屏幕 %.0fx%.0f\n",
		appVer ?: @"?", build ?: @"?", [[UIDevice currentDevice] systemVersion],
		CGRectGetWidth([UIScreen mainScreen].bounds), CGRectGetHeight([UIScreen mainScreen].bounds)];
	[o appendFormat:@"开关: 总开关=%@ 设计系统=%@ 输入框液态=%@\n",
		WCLGEnabled() ? @"开" : @"关", WCLGDesignEnabled() ? @"开" : @"关",
		WCLGInputGlassEnabled() ? @"开" : @"关"];

	UIViewController *top = WCLGTopMostVC();
	[o appendFormat:@"\n[当前控制器] %@  view %@\n", WCLGShortClass(top), WCLGFrameStr(top.view, nil)];

	// ---------- 底栏 ----------
	[o appendString:@"\n=== 底栏 ===\n"];
	@try {
		Class barCls = objc_getClass("MMTabBar");
		__block UIView *bar = nil;
		if (barCls) {
			WCLGViewTreeContains(WCLGKeyWindow(), 0, ^BOOL(UIView *v) {
				if ([v isKindOfClass:barCls]) { bar = v; return YES; }
				return NO;
			});
		}
		if (bar) {
			[o appendFormat:@"%@ %@\n", WCLGShortClass(bar), WCLGFrameStr(bar, WCLGKeyWindow())];
			for (UIView *s in bar.subviews) {
				[o appendFormat:@"  %@ %@\n", WCLGShortClass(s), WCLGFrameStr(s, bar)];
			}
			BOOL hasPlatter = WCLGViewTreeContains(bar, 0, ^BOOL(UIView *v) {
				return [WCLGShortClass(v) containsString:@"Platter"];
			});
			[o appendFormat:@"  Platter: %@\n", hasPlatter ? @"有" : @"无"];
		} else {
			[o appendString:@"MMTabBar 未找到\n"];
		}
	} @catch (__unused NSException *e) { [o appendString:@"底栏读取异常\n"]; }

	// ---------- 输入条 ----------
	[o appendString:@"\n=== 输入条 ===\n"];
	NSMutableArray<UIViewController *> *vcs = [NSMutableArray array];
	WCLGCollectVCs(WCLGKeyWindow().rootViewController, vcs, 0);
	UIView *foundBar = nil;
	UIViewController *foundVC = nil;
	for (UIViewController *c in vcs) {
		if (!c.isViewLoaded) continue;
		UIView *b = WCLGFindInputBar(c.view);
		if (b) {
			[o appendFormat:@"  %@ → 找到 %@ %@\n", WCLGShortClass(c), WCLGShortClass(b),
				WCLGFrameStr(b, c.view)];
			if (!foundBar) { foundBar = b; foundVC = c; }
		}
	}
	[o appendFormat:@"控制器数 %lu，输入条 %@\n", (unsigned long)vcs.count,
		foundBar ? @"已找到" : @"未找到"];
	if (foundBar) {
		BOOL glassIn = objc_getAssociatedObject(foundBar, kWCLGInputGlassAssocKey) != nil;
		[o appendFormat:@"  玻璃已插入: %@\n", glassIn ? @"是" : @"否"];
		UIView *p = foundBar;
		for (NSInteger i = 0; i < 3 && p.superview; i++) {
			p = p.superview;
			[o appendFormat:@"  父%d %@ %@ bg=%@\n", (int)i + 1, WCLGShortClass(p),
				WCLGFrameStr(p, foundVC.view),
				p.backgroundColor ? [NSString stringWithFormat:@"a=%.2f", CGColorGetAlpha(p.backgroundColor)] : @"nil"];
		}
	}
	if (foundVC) {
		[o appendString:@"  — 下半屏视图树 —\n"];
		WCLGDumpBottomHalf(foundVC.view, 0, 4, o, @"  ");
	}

	// ---------- 顶部 ----------
	[o appendString:@"\n=== 顶部 ===\n"];
	@try {
		UINavigationBar *nb = nil;
		for (UIViewController *c in vcs) {
			if (c.navigationController.navigationBar) { nb = c.navigationController.navigationBar; break; }
		}
		if (nb) {
			[o appendFormat:@"navigationBar %@ %@\n", WCLGShortClass(nb),
				WCLGFrameStr(nb, WCLGKeyWindow())];
			for (UIView *s in nb.subviews) {
				[o appendFormat:@"  %@ %@%@\n", WCLGShortClass(s), WCLGFrameStr(s, nb), WCLGDeltaX(s)];
			}
		} else {
			[o appendString:@"navigationBar = nil\n"];
		}
	} @catch (__unused NSException *e) { [o appendString:@"导航栏读取异常\n"]; }

	// 主界面自定义栏 + 搜索框
	Class mfCls = objc_getClass("NewMainFrameViewController");
	UIViewController *mf = nil;
	for (UIViewController *c in vcs) {
		if (mfCls && [c isKindOfClass:mfCls]) { mf = c; break; }
	}
	if (mf) {
		@try {
			UIView *fake = [mf valueForKey:@"fakeNavBarView"];
			[o appendFormat:@"fakeNavBarView %@\n", fake ? @"" : @"= nil"];
			if (fake) {
				[o appendFormat:@"  %@ %@\n", WCLGShortClass(fake), WCLGFrameStr(fake, mf.view)];
				for (UIView *s in fake.subviews) {
					[o appendFormat:@"    %@ %@%@\n", WCLGShortClass(s), WCLGFrameStr(s, fake), WCLGDeltaX(s)];
				}
			}
		} @catch (__unused NSException *e) { [o appendString:@"fakeNavBarView 读取异常\n"]; }

		@try {
			UIView *sb = [mf valueForKey:@"searchBar"];
			if (sb) {
				[o appendFormat:@"searchBar %@ %@  父 %@ %@\n", WCLGShortClass(sb),
					WCLGFrameStr(sb, mf.view), WCLGShortClass(sb.superview),
					WCLGFrameStr(sb.superview, mf.view)];
				UIView *p = sb.superview;
				NSInteger i = 0;
				while (p && i < 3) {
					[o appendFormat:@"  祖%d %@ %@\n", (int)i + 1, WCLGShortClass(p), WCLGFrameStr(p, mf.view)];
					p = p.superview; i++;
				}
			} else {
				[o appendString:@"searchBar = nil\n"];
			}
		} @catch (__unused NSException *e) { [o appendString:@"searchBar 读取异常\n"]; }

		@try {
			id tv = [mf valueForKey:@"tableView"];
			if ([tv isKindOfClass:[UITableView class]]) {
				UITableView *table = (UITableView *)tv;
				[o appendFormat:@"tableView %@ inset t=%.0f b=%.0f  headerH=%.0f\n",
					WCLGFrameStr(table, mf.view), table.contentInset.top, table.contentInset.bottom,
					CGRectGetHeight(table.tableHeaderView.frame)];
			}
		} @catch (__unused NSException *e) {}
		[o appendFormat:@"view %@ safeTop=%.0f safeBottom=%.0f\n",
			WCLGFrameStr(mf.view, nil), mf.view.safeAreaInsets.top, mf.view.safeAreaInsets.bottom];
	} else {
		[o appendString:@"当前不在主界面（NewMainFrameViewController 未在控制器链中）\n"];
	}

	return o;
}

// ---------- 可滚动、可复制的诊断界面 ----------
@interface WCLGDiagViewController : UIViewController
@property (nonatomic, copy) NSString *report;
@end

@implementation WCLGDiagViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor systemBackgroundColor];

	UITextView *tv = [[UITextView alloc] initWithFrame:CGRectInset(self.view.bounds, 8.0, 56.0)];
	tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	tv.editable = NO;
	tv.selectable = YES;
	tv.alwaysBounceVertical = YES;
	tv.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
	tv.text = self.report;
	[self.view addSubview:tv];

	UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
	close.frame = CGRectMake(8.0, CGRectGetHeight(self.view.bounds) - 48.0,
							 CGRectGetWidth(self.view.bounds) - 16.0, 40.0);
	close.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
	[close setTitle:@"关闭（三指长按可再次打开）" forState:UIControlStateNormal];
	[close addTarget:self action:@selector(wclgClose) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:close];
}

- (void)wclgClose {
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void WCLGShowDiagnostics(void) {
	@try {
		UIViewController *root = WCLGKeyWindow().rootViewController;
		if (!root) return;
		if ([root.presentedViewController isKindOfClass:[WCLGDiagViewController class]]) return;
		WCLGDiagViewController *vc = [[WCLGDiagViewController alloc] init];
		vc.report = WCLGBuildReport();
		vc.modalPresentationStyle = UIModalPresentationFullScreen;
		[root presentViewController:vc animated:YES completion:nil];
	} @catch (__unused NSException *e) {}
}

@interface WCLGDiagTrigger : NSObject
+ (instancetype)shared;
- (void)onLongPress:(UILongPressGestureRecognizer *)g;
@end

@implementation WCLGDiagTrigger
+ (instancetype)shared {
	static WCLGDiagTrigger *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [[WCLGDiagTrigger alloc] init]; });
	return s;
}
- (void)onLongPress:(UILongPressGestureRecognizer *)g {
	if (g.state != UIGestureRecognizerStateBegan) return;
	WCLGShowDiagnostics();
}
@end

static BOOL WCLGDiagGestureInstalled = NO;

static void WCLGInstallDiagGesture(void) {
	if (WCLGDiagGestureInstalled) return;
	UIWindow *win = WCLGKeyWindow();
	if (!win) return;
	UILongPressGestureRecognizer *g =
		[[UILongPressGestureRecognizer alloc] initWithTarget:[WCLGDiagTrigger shared]
													  action:@selector(onLongPress:)];
	g.numberOfTouchesRequired = 3;
	g.minimumPressDuration = 1.0;
	g.cancelsTouchesInView = NO;
	[win addGestureRecognizer:g];
	WCLGDiagGestureInstalled = YES;
}

// 首次启动后自动弹一次（只一次）；窗口还没好就 4 秒后重试
static void WCLGInstallDiagnostics(void) {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		if (!WCLGKeyWindow()) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
						   dispatch_get_main_queue(), ^{
				WCLGInstallDiagGesture();
				WCLGShowDiagnostics();
			});
			return;
		}
		WCLGInstallDiagGesture();
		static BOOL shown = NO;
		if (shown) return;
		shown = YES;
		WCLGShowDiagnostics();
	});
}
#endif

%ctor {
	WCLGHookScrollEdgeEffectView();
#if WCLG_DIAG
	WCLGInstallDiagnostics();
#endif
}



// ============================================================
//  主界面：正常版只用于「输入框液态」；诊断版额外弹一次视图树
// ============================================================
%hook UIViewController

- (void)viewDidLayoutSubviews {
	%orig;
	if (!WCLGEnabled() || !WCLGInputGlassEnabled()) return;
	WCLGApplyInputGlass(self);      // 只在认出「输入条」时才动，绝不碰其它视图
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	if (!WCLGEnabled() || !WCLGInputGlassEnabled()) return;
	// 有些控制器不调 super 的 viewDidLayoutSubviews，这里再兜一次
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
				   dispatch_get_main_queue(), ^{
		WCLGApplyInputGlass(self);
	});
}



%end

// ============================================================
//  原版逻辑：底栏（一行未改）
// ============================================================
%hook MMTabBar

- (void)setStandardAppearance:(UITabBarAppearance *)appearance {
	if (WCLGEnabled()) return;
	%orig;
}

- (void)setScrollEdgeAppearance:(UITabBarAppearance *)appearance {
	if (WCLGEnabled()) return;
	%orig;
}

- (void)setBackgroundImage:(UIImage *)image {
	if (WCLGEnabled()) return;
	%orig;
}

- (void)setShadowImage:(UIImage *)image {
	if (WCLGEnabled()) return;
	%orig;
}

- (void)setBarTintColor:(UIColor *)color {
	if (WCLGEnabled()) return;
	%orig;
}

- (void)setBackgroundColor:(UIColor *)color {
	if (WCLGEnabled() && color && CGColorGetAlpha(color.CGColor) > 0.01) return;
	%orig;
}

- (void)layoutSubviews {
	%orig;
	WCLGStripTabBar(self);
	WCLGAlignTabBarItems(self);
	WCLGStripTabBarDeferred(self);
}

- (void)didAddSubview:(UIView *)subview {
	%orig;
	WCLGStripTabBar(self);
	WCLGStripTabBarDeferred(self);
}

- (void)didMoveToWindow {
	%orig;
	WCLGStripTabBar(self);
}

- (void)didMoveToSuperview {
	%orig;
	WCLGStripTabBar(self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
	%orig;
	WCLGStripTabBar(self);
}

%end

// 原版逻辑：只挂钩微信自己的按钮重排
%hook MMTabBarController

- (void)relayoutButtons:(BOOL)animated {
	%orig;
	UITabBar *bar = self.tabBar;
	if ([bar isKindOfClass:[UITabBar class]]) WCLGStripTabBar(bar);
}

%end


// ============================================================
//  wczz 设置页对接（3 个开关）
// ============================================================
BOOL WCZZTabBarGlassEnabled(void) { return WCLGEnabled(); }
void WCZZSetTabBarGlassEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGEnabledKey]; }

BOOL WCZZGlassDesignEnabled(void) { return WCLGDesignEnabled(); }
void WCZZSetGlassDesignEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGDesignKey]; }

BOOL WCZZGlassInputEnabled(void) { return WCLGInputGlassEnabled(); }
void WCZZSetGlassInputEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGInputGlassKey]; }
