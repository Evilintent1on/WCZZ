#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// ============================================================
//  wctabbar v3 —— 在你原版基础上修 4 个问题 + 加输入框液态
//
//  原版逻辑（擦底 / 关毛玻璃 / 对齐底栏图标 / MMTabBar 系列钩子）**一行未动**。
//  本次新增（全部可开关，出问题能单独关掉定位）：
//    ★1 顶部液态胶囊里按钮不居中 → WCLGCenterButtonsInGlass()
//    ★2 顶部整体偏移         → fakeNavBarView 对齐系统导航栏 frame
//    ★3 搜索框变窄/被压缩     → 恢复宽度 + 撑开表头高度（根因：搜索框是表头视图）
//    ★4 输入框没有液态       → 聊天页底部的输入条后面垫一层 Liquid Glass
//
//  说明：问题 1~3 的根因是「微信是按旧设计量好的布局，被我们切成新设计后
//  系统给的容器尺寸变了」。所以修法是**布局后校正**，而不是改系统。
// ============================================================

// ---------- 微信真实类 ----------
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// 顶部自定义栏（NewMainFrameViewController.fakeNavBarView 的类型）
@interface MainFrameCustomBarView : UIView
@end

// 主界面控制器：这里用到 self.navigationController / self.view，必须显式声明继承关系
@interface NewMainFrameViewController : UIViewController
@property (nonatomic, retain) MainFrameCustomBarView *fakeNavBarView;   // 顶部自定义栏
@property (nonatomic, retain) UIView *searchBar;                        // 实为 WCSearchBar
@end

// ---------- 开关 ----------
static NSString *const kWCLGEnabledKey    = @"wclg_native_tabbar_enabled";  // 总开关
static NSString *const kWCLGDesignKey     = @"wclg_ios26_design";           // 全局设计系统（原生玻璃前提）
static NSString *const kWCLGTopFixKey     = @"wclg_fix_top_layout";         // ★1★2★3 顶部校正
static NSString *const kWCLGInputGlassKey = @"wclg_input_glass";            // ★4 输入框液态

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
static BOOL WCLGTopFixEnabled(void) { return WCLGFlag(kWCLGTopFixKey, YES); }
static BOOL WCLGInputGlassEnabled(void) { return WCLGFlag(kWCLGInputGlassKey, YES); }

// ============================================================
//  通用工具
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

// iOS 26 的液态玻璃效果（拿不到就退回系统材质模糊）
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
//  ★1 顶部液态胶囊里按钮不居中
//
//  新设计下系统会给导航栏按钮套一层玻璃胶囊（类名含 Platter / LiquidLens /
//  Glass / Container），而微信自己的按钮视图还按旧尺寸摆 → 看着偏。
//  这里把胶囊里的按钮按胶囊中心重新摆一次（位置已对就不写，避免触发多余布局）。
// ============================================================
static BOOL WCLGIsGlassContainer(UIView *v) {
	NSString *cn = NSStringFromClass([v class]);
	if (!cn) return NO;
	return [cn containsString:@"Platter"] || [cn containsString:@"LiquidLens"] ||
		   [cn containsString:@"Glass"] || [cn containsString:@"Capsule"] ||
		   [cn containsString:@"Container"];
}

static BOOL WCLGLooksLikeButton(UIView *v) {
	if ([v isKindOfClass:[UIButton class]]) return YES;
	NSString *cn = NSStringFromClass([v class]);
	return cn && [cn containsString:@"Button"];
}

// 顶部标题：只把「位于条目中间区域」的标题视图水平居中，避免误动左右按钮
static void WCLGCenterTitle(UIView *bar) {
	if (!bar) return;
	CGFloat W = CGRectGetWidth(bar.bounds);
	if (W < 40.0) return;
	for (UIView *sub in bar.subviews) {
		NSString *cn = NSStringFromClass([sub class]);
		BOOL isTitle = [cn containsString:@"Title"] && ![cn containsString:@"Button"];
		if (!isTitle && ![sub isKindOfClass:[UILabel class]]) continue;

		CGRect r = sub.frame;
		CGFloat midX = CGRectGetMidX(r);
		// 只在中间 60% 区域内、且确实偏了才校正
		if (midX < W * 0.2 || midX > W * 0.8) continue;
		CGFloat want = W * 0.5;
		if (fabs(midX - want) < 1.0) continue;

		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		CGPoint c = sub.center;
		c.x = want;
		sub.center = c;
		[CATransaction commit];
	}
}

static void WCLGCenterButtonsInGlass(UIView *root, NSInteger depth) {
	if (!root || depth > 6) return;
	for (UIView *sub in root.subviews) {
		if (WCLGIsGlassContainer(sub)) {
			CGPoint target = CGPointMake(CGRectGetMidX(sub.bounds), CGRectGetMidY(sub.bounds));
			for (UIView *g in sub.subviews) {
				if (!WCLGLooksLikeButton(g)) continue;
				CGPoint c = g.center;
				if (fabs(c.x - target.x) < 0.5 && fabs(c.y - target.y) < 0.5) continue;
				[CATransaction begin];
				[CATransaction setDisableActions:YES];
				g.center = target;
				[CATransaction commit];
			}
		}
		WCLGCenterButtonsInGlass(sub, depth + 1);
	}
}

// ============================================================
//  ★4 找聊天页的输入条（不依赖类名，靠位置 + 尺寸 + 含输入控件判定）
// ============================================================
static BOOL WCLGContainsTextInput(UIView *v, NSInteger depth) {
	if (depth > 4) return NO;
	if ([v isKindOfClass:[UITextView class]] || [v isKindOfClass:[UITextField class]]) return YES;
	for (UIView *s in v.subviews) {
		if (WCLGContainsTextInput(s, depth + 1)) return YES;
	}
	return NO;
}

static UIView *WCLGFindInputBar(UIView *root) {
	CGFloat H = CGRectGetHeight(root.bounds), W = CGRectGetWidth(root.bounds);
	if (H < 100 || W < 100) return nil;

	UIView *best = nil;
	CGFloat bestY = -1;
	NSArray<UIView *> *level1 = root.subviews;
	for (UIView *v in level1) {
		NSArray<UIView *> *candidates = @[v];
		for (UIView *g in v.subviews) candidates = [candidates arrayByAddingObject:g];
		for (UIView *c in candidates) {
			CGRect r = c.frame;
			if (CGRectGetMinY(r) < H * 0.55) continue;
			if (CGRectGetWidth(r) < W * 0.6) continue;
			if (CGRectGetHeight(r) < 36.0 || CGRectGetHeight(r) > 170.0) continue;
			if (!WCLGContainsTextInput(c, 0)) continue;
			if (CGRectGetMinY(r) > bestY) { bestY = CGRectGetMinY(r); best = c; }
		}
	}
	return best;
}

static const void *kWCLGInputGlassKey = &kWCLGInputGlassKey;

static void WCLGApplyInputGlass(UIViewController *vc) {
	if (!WCLGEnabled() || !WCLGInputGlassEnabled()) return;
	if (![vc isKindOfClass:[UIViewController class]]) return;

	UIView *bar = WCLGFindInputBar(vc.view);
	if (!bar) return;
	if (CGRectIsEmpty(bar.bounds)) return;          // 还没量好，等下一次布局

	UIVisualEffectView *glass = objc_getAssociatedObject(bar, kWCLGInputGlassKey);
	if (!glass) {
		glass = [[UIVisualEffectView alloc] initWithEffect:WCLGGlassEffect()];
		glass.userInteractionEnabled = NO;
		glass.opaque = NO;
		glass.backgroundColor = [UIColor clearColor];
		glass.layer.cornerRadius = 18.0;
		glass.layer.cornerCurve = kCACornerCurveContinuous;
		glass.layer.masksToBounds = YES;
		[bar insertSubview:glass atIndex:0];
		objc_setAssociatedObject(bar, kWCLGInputGlassKey, glass, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		// 输入条自己让出底色，玻璃才看得见
		bar.backgroundColor = [UIColor clearColor];
		bar.opaque = NO;
	}
	CGRect want = CGRectInset(bar.bounds, 2.0, 2.0);
	if (!CGRectEqualToRect(glass.frame, want)) {
		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		glass.frame = want;
		[CATransaction commit];
	}
	// 玻璃垫到最底层，别盖住输入控件
	[bar sendSubviewToBack:glass];
}

// ============================================================
//  擦掉微信画在底栏上的东西（原版逻辑，未改）
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
			if (g.backgroundColor && CGColorGetAlpha(g.backgroundColor.CGColor) > 0.01) {
				g.backgroundColor = [UIColor clearColor];
			}
			if (g.layer.backgroundColor && CGColorGetAlpha(g.layer.backgroundColor.CGColor) > 0.01) {
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

// 底栏图标对齐（原版逻辑，未改）
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
//  让 UIKit 认为微信没申请旧版设计（受 wclg_ios26_design 控制）
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
//  关掉 iOS 26 滚动边缘效果（原版是全部实例；这里保持原版行为）
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

%ctor {
	WCLGHookScrollEdgeEffectView();
}

// ============================================================
//  ★2 + ★3 顶部校正（主界面）
//
//  ★2 偏移：微信的 fakeNavBarView 是按旧设计量好的 → 对齐系统导航栏的 frame
//  ★3 搜索框：搜索框是被当成 tableView 的 headerView 放的（setSearchBarToTableHeaderView），
//     新设计下表格 header 高度不够 → 搜索框被压扁；宽度也会被内边距吃掉。
//     这里恢复宽度、并把 header 高度撑到够放搜索框。
// ============================================================
%hook NewMainFrameViewController

- (void)viewDidLayoutSubviews {
	%orig;
	if (!WCLGEnabled() || !WCLGTopFixEnabled()) return;

	// ★2 顶部自定义栏对齐系统导航栏
	UIView *fakeBar = nil;
	@try { fakeBar = [self valueForKey:@"fakeNavBarView"]; } @catch (__unused NSException *e) {}
	UINavigationBar *sysBar = self.navigationController.navigationBar;
	if (fakeBar && sysBar && sysBar.window) {
		CGRect want = [sysBar convertRect:sysBar.bounds toView:self.view];
		CGRect cur = fakeBar.frame;
		BOOL changed = NO;
		if (fabs(cur.origin.y - want.origin.y) > 0.5) { cur.origin.y = want.origin.y; changed = YES; }
		if (fabs(cur.size.height - want.size.height) > 0.5 && want.size.height > 20.0) {
			cur.size.height = want.size.height; changed = YES;
		}
		if (changed) {
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			fakeBar.frame = cur;
			[CATransaction commit];
		}
	}

	// ★3 搜索框：恢复宽度 + 撑开表头高度
	UIView *searchBar = nil;
	@try { searchBar = [self valueForKey:@"searchBar"]; } @catch (__unused NSException *e) {}
	if (searchBar && searchBar.superview) {
		CGFloat viewW = CGRectGetWidth(self.view.bounds);

		// 宽度：搜索框通常左右各留 8pt；被压窄就恢复
		CGRect f = searchBar.frame;
		CGFloat wantW = viewW - 16.0;
		BOOL changed = NO;
		if (wantW > 40.0 && f.size.width < wantW - 1.0) { f.size.width = wantW; changed = YES; }
		if (fabs(f.origin.x - 8.0) > 0.5 && f.size.width >= wantW - 1.0) { f.origin.x = 8.0; changed = YES; }

		// 高度：别被压扁（低于 32 视为被压）
		CGFloat wantH = MAX(CGRectGetHeight(f), 36.0);
		if (CGRectGetHeight(f) < 32.0) { f.size.height = wantH; changed = YES; }
		if (changed) {
			[CATransaction begin];
			[CATransaction setDisableActions:YES];
			searchBar.frame = f;
			[CATransaction commit];
		}

		// 表头高度不足 → 撑开，否则搜索框会被裁/压
		UIView *header = searchBar.superview;
		if (header && header != self.view) {
			CGRect hf = header.frame;
			CGFloat need = CGRectGetHeight(f) + 8.0;
			if (CGRectGetHeight(hf) < need - 0.5) {
				hf.size.height = need;
				[CATransaction begin];
				[CATransaction setDisableActions:YES];
				header.frame = hf;
				[CATransaction commit];
			}
		}
	}

	// ★1 顶部胶囊里的按钮居中 + 标题居中
	WCLGCenterButtonsInGlass(self.view, 0);
	if (fakeBar) WCLGCenterTitle(fakeBar);
}

%end

// ★1 顶部自定义栏自己重排时也校正一次
%hook MainFrameCustomBarView

- (void)layoutSubviews {
	%orig;
	if (!WCLGEnabled() || !WCLGTopFixEnabled()) return;
	WCLGCenterButtonsInGlass(self, 0);
}

%end

// ============================================================
//  ★4 输入框液态：所有控制器的布局回调里检查一次
//     （不依赖具体类名，靠「贴底 + 宽度接近全宽 + 高度 36~170 + 含输入控件」认出输入条）
// ============================================================
%hook UIViewController

- (void)viewDidLayoutSubviews {
	%orig;
	if (!WCLGEnabled() || !WCLGInputGlassEnabled()) return;
	WCLGApplyInputGlass(self);
}

%end

// ============================================================
//  底栏 Hook（原版逻辑，未改）
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

%hook MMTabBarController

- (void)relayoutButtons:(BOOL)animated {
	%orig;
	UITabBar *bar = self.tabBar;
	if ([bar isKindOfClass:[UITabBar class]]) WCLGStripTabBar(bar);
}

%end

// ============================================================
//  wczz 设置页对接（4 个开关）
// ============================================================
BOOL WCZZTabBarGlassEnabled(void) { return WCLGEnabled(); }
void WCZZSetTabBarGlassEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGEnabledKey]; }

BOOL WCZZGlassDesignEnabled(void) { return WCLGDesignEnabled(); }
void WCZZSetGlassDesignEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGDesignKey]; }

BOOL WCZZGlassTopFixEnabled(void) { return WCLGTopFixEnabled(); }
void WCZZSetGlassTopFixEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGTopFixKey]; }

BOOL WCZZGlassInputEnabled(void) { return WCLGInputGlassEnabled(); }
void WCZZSetGlassInputEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGInputGlassKey]; }
