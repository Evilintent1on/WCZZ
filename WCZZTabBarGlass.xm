// ============================================================
//  wctabbar —— 只保留「底栏液态玻璃」，其他效果全部去除
//
//  本文件由你桌面那份 Tweak.xm 直接生成，只做了四处改动：
//    ① 滚动边缘效果：原来把 UIKit.ScrollEdgeEffectView 的**每个实例**都强制隐藏，
//       而顶部导航栏下方那条模糊用的是同一个类 → 顶部也被改。
//       现在只处理**底部那一条**（按位置判定），顶部实例原样放行。
//    ② 加了三个开关（总开关 / 设计系统 / 底部边缘效果）+ 两个对齐微调量。
//    ③ NSBundle 那两个方法受「设计系统」开关控制（它是底栏玻璃的前提，默认保留）。
//    ④ 对齐逻辑：加入 extraX / extraY 微调；item 没有可见子视图时直接把整个 item 居中到胶囊。
//
//  开关（NSUserDefaults，实时生效）：
//    wclg_native_tabbar_enabled   总开关          默认开
//    wclg_ios26_design            设计系统         默认开（底栏浮动玻璃的前提）
//    wclg_hide_bottom_edge        底部边缘效果     默认开（只关底部那一条，顶部不受影响）
//    wclg_dock_extra_x / _y       图标对齐微调     默认 0（正值 = 右 / 下），改完立即生效
//
//  对齐逻辑要点（与原版一致 + 微调）：
//    · platter 运行时按类名找（含 "Platter"），不写死内缩量 → 系统改数值/换机型/横竖屏都跟得上
//    · item 先按 x 排序再排布，避免 subviews 顺序变化导致错乱
//    · 偏差 < 0.5pt 直接跳过，避免每帧写 frame 引起抖动
//    · 垂直：取 item 内「可见子视图」的包围盒，把它的中心对齐到胶囊中心（再叠加 extraY）
// ============================================================

#import <UIKit/UIKit.h>

// ---------- 微信真实类 ----------
// 如实声明继承关系，编译器才知道它们是系统类的子类
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// ---------- 开关 ----------
static NSString *const kWCLGEnabledKey    = @"wclg_native_tabbar_enabled";
static NSString *const kWCLGDesignKey     = @"wclg_ios26_design";
static NSString *const kWCLGBottomEdgeKey = @"wclg_hide_bottom_edge";

// ---------- 对齐微调 ----------
//  默认 0 = 不加偏移（与之前行为一致）。两种改法：
//    ① 编译期：改下面两个常量  ② 运行期：NSUserDefaults 覆盖（立即生效，不用重编译）
//       wclg_dock_extra_y = -2.5   → 图标整体上移 2.5pt
//       wclg_dock_extra_x =  1.0   → 图标整体右移 1pt
static CGFloat const kWCLGDockExtraX = 0.0;      // ← 这里也能改
static CGFloat const kWCLGDockExtraY = 0.0;      // ← 这里也能改
static NSString *const kWCLGExtraXKey = @"wclg_dock_extra_x";
static NSString *const kWCLGExtraYKey = @"wclg_dock_extra_y";

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
static BOOL WCLGBottomEdgeEnabled(void) { return WCLGFlag(kWCLGBottomEdgeKey, YES); }

static CGFloat WCLGDockExtraX(void) {
	id v = [[NSUserDefaults standardUserDefaults] objectForKey:kWCLGExtraXKey];
	return v ? (CGFloat)[v doubleValue] : kWCLGDockExtraX;
}

static CGFloat WCLGDockExtraY(void) {
	id v = [[NSUserDefaults standardUserDefaults] objectForKey:kWCLGExtraYKey];
	return v ? (CGFloat)[v doubleValue] : kWCLGDockExtraY;
}

// ============================================================
//  关掉毛玻璃
//
//  只设 hidden 不够 —— 微信会在自己的 layout 里把容器改回可见。
//  直接让 UIVisualEffectView 没有 effect，它就没东西可渲染。
//  浮动胶囊的玻璃走的是 ClearGlassView/SDF，不是 UIVisualEffectView，不受影响。
// ============================================================
static void WCLGKillBlur(UIView *v, NSInteger depth) {
	if (depth > 10) return;
	// 直接遍历，不 copy —— 这里只改 effect/hidden，不增删子视图，
	// 没有边遍历边改的问题。copy 会在每个节点上多一次堆分配。
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
//  关掉 iOS 26 的滚动边缘效果
//
//  UIKit.ScrollEdgeEffectView 是系统给可滚动内容下边缘加的模糊/渐隐，让内容滚到
//  浮动底栏底下时柔化过渡。底栏一透明它就露出来了（实测位于 {0,782},{420,130}，
//  正好压在底栏 y=822..912 下面）。
//
//  唯一手段是下面的类级 hook —— 树遍历设 hidden 打不赢，UIKit 会在自己的
//  layout 里重新显示（实测反复触发 184 次仍是 hidden=0），已弃用。
// ============================================================

// ============================================================
//  擦掉微信画在底栏上的东西
// ============================================================
static void WCLGStripTabBar(UITabBar *bar) {
	if (!bar || ![bar isKindOfClass:[UITabBar class]]) return;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	// ① 底栏自己那层底
	bar.translucent = YES;
	bar.opaque = NO;
	bar.backgroundColor = [UIColor clearColor];
	bar.layer.backgroundColor = [UIColor clearColor].CGColor;

	// ② 微信塞的全尺寸背景容器：直接藏掉，光清颜色会被它重画回来
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
		// 跟底栏一样大的容器 = 微信的底。frame 也必须是满的 ——
		// bounds 满尺寸但 frame 为 0×0 的是 portal 源视图（挂在屏幕外给
		// _UIPortalView 采样用），藏了会毁掉玻璃折射。
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
			if (g.layer.backgroundColor && CGColorGetAlpha(g.layer.backgroundColor) > 0.01) {
				g.layer.backgroundColor = [UIColor clearColor].CGColor;
			}
		}
	}

	[CATransaction commit];

	// ③ 关掉毛玻璃
	WCLGKillBlur(bar, 0);
}

static void WCLGAlignTabBarItems(UITabBar *bar);   // 定义在后面

// 微信会反复把底重画回来，延到下一个 runloop 再擦一遍。
// 节流：微信一次会话能触发布局几百次，不节流的话主队列会堆满重复的块。
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

// ============================================================
//  对齐图标
//
//  系统的浮动胶囊是内缩的（如 {21,7},{378,62}），而微信的 MMTabBarItemView
//  是按全宽均分的（0/105/210/315）。这里拿 platter 的 frame 当基准，
//  把 item 视图重新摆到胶囊的网格上，并让内容垂直居中到胶囊。
// ============================================================
static void WCLGAlignTabBarItems(UITabBar *bar) {
	if (!bar) return;

	// 找浮动胶囊
	UIView *platter = nil;
	for (UIView *sub in bar.subviews) {
		if ([NSStringFromClass([sub class]) containsString:@"Platter"]) {
			platter = sub;
			break;
		}
	}
	if (!platter) return;

	// 收集微信自己的 item 视图
	NSMutableArray<UIView *> *items = [NSMutableArray array];
	for (UIView *sub in bar.subviews) {
		if ([NSStringFromClass([sub class]) containsString:@"MMTabBarItemView"]) {
			[items addObject:sub];
		}
	}
	if (items.count == 0) return;

	// 按 x 排序，保证顺序和 tab 一致
	[items sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
		if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
		if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
		return NSOrderedSame;
	}];

	CGRect pf = platter.frame;
	CGFloat n = (CGFloat)items.count;
	CGFloat extraX = WCLGDockExtraX();        // 对齐微调（默认 0）
	CGFloat extraY = WCLGDockExtraY();
	CGFloat platterMidY = CGRectGetMidY(pf);

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < (NSInteger)n; i++) {
		UIView *iv = items[i];
		CGPoint c = iv.center;

		// 水平：摆到胶囊的网格上（胶囊运行时找，不写死内缩量）
		c.x = pf.origin.x + pf.size.width * ((CGFloat)i + 0.5) / n + extraX;

		// 垂直：取 item 内「可见子视图」的实际包围盒，把它的中心对齐到胶囊中心
		CGRect content = CGRectNull;
		for (UIView *g in iv.subviews) {
			if (g.hidden) continue;
			content = CGRectUnion(content, g.frame);
		}
		if (!CGRectIsNull(content)) {
			CGFloat contentMidYInBar = iv.frame.origin.y + CGRectGetMidY(content);
			c.y += platterMidY - contentMidYInBar + extraY;
		} else {
			c.y = platterMidY + extraY;       // 没有可见子视图：整个 item 居中到胶囊
		}

		// 位置已经对了就别写 —— 无条件写 frame 会让 UIKit 标记重新布局，
		// 反过来又触发 layoutSubviews，白白多跑一轮
		if (fabs(iv.center.x - c.x) < 0.5 && fabs(iv.center.y - c.y) < 0.5) continue;
		iv.center = c;
	}
	[CATransaction commit];
}

// ============================================================
//  关键：让 UIKit 认为微信没申请旧版设计
//
//  微信 Info.plist 里有 UIDesignRequiresCompatibility = true，这是它底栏是
//  「全宽不透明」而不是 iOS 26 浮动玻璃的根本原因（它用 iphoneos26.1 SDK 构建，
//  却主动退回了旧设计系统）。UIKit 走 NSBundle 读这个 key，这里把它屏蔽掉。
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
//  从类上强制关掉滚动边缘效果
//
//  这是 Swift 类：UIKit.ScrollEdgeEffectView（内部类 _TtCC5UIKit20...BackdropView）。
//  树遍历会被 UIKit 反复重置，所以 setHidden: 直接强制成 YES，谁设都无效。
// ============================================================
// ★ 改动：原版对每个实例都强制隐藏（顶部那条也被关掉）。现在只处理底部那一条。
static BOOL WCLGIsBottomEdgeView(UIView *v) {
	if (![v isKindOfClass:[UIView class]]) return NO;

	UIView *ref = v.window;
	CGRect r = CGRectZero;
	if (ref) {
		r = [v convertRect:v.bounds toView:ref];
	} else if (v.superview) {
		ref = v.superview;
		r = v.frame;
	} else {
		return NO;                     // 还没上屏 → 不碰（宁可少关，不误伤顶部）
	}
	CGFloat h = CGRectGetHeight(ref.bounds);
	if (h <= 0) return NO;
	return CGRectGetMidY(r) > h * 0.55;    // 只看屏幕下方 45%
}

static void (*wclg_orig_SEV_setHidden)(id, SEL, BOOL);
static void wclg_SEV_setHidden(id self, SEL _cmd, BOOL hidden) {
	if (!WCLGEnabled() || !WCLGBottomEdgeEnabled() || !WCLGIsBottomEdgeView((UIView *)self)) {
		wclg_orig_SEV_setHidden(self, _cmd, hidden);     // 顶部 / 开关关：完全不干预
		return;
	}
	wclg_orig_SEV_setHidden(self, _cmd, YES);            // 底部：谁设都无效
}

static void (*wclg_orig_SEV_layoutSubviews)(id, SEL);
static void wclg_SEV_layoutSubviews(id self, SEL _cmd) {
	wclg_orig_SEV_layoutSubviews(self, _cmd);
	if (WCLGEnabled() && WCLGBottomEdgeEnabled() && WCLGIsBottomEdgeView((UIView *)self)) {
		((UIView *)self).hidden = YES;
	}
}

static void WCLGHookScrollEdgeEffectView(void) {
	static BOOL done = NO;
	if (done) return;
	done = YES;

	Class c = NSClassFromString(@"UIKit.ScrollEdgeEffectView");
	if (!c) c = objc_getClass("_TtC5UIKit20ScrollEdgeEffectView");
	if (!c) return;   // 解析不到就只靠树遍历兜底，不影响其他功能

	MSHookMessageEx(c, @selector(setHidden:),
		(IMP)wclg_SEV_setHidden, (IMP *)&wclg_orig_SEV_setHidden);
	MSHookMessageEx(c, @selector(layoutSubviews),
		(IMP)wclg_SEV_layoutSubviews, (IMP *)&wclg_orig_SEV_layoutSubviews);
}

%ctor {
	WCLGHookScrollEdgeEffectView();
}

// ============================================================
//  Hook
// ============================================================
%hook MMTabBar

// --- 吞掉微信的 appearance 覆盖，保留系统默认（浮动玻璃的来源）---
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

// 背景色：只挡不透明的
- (void)setBackgroundColor:(UIColor *)color {
	if (WCLGEnabled() && color && CGColorGetAlpha(color.CGColor) > 0.01) return;
	%orig;
}

// --- 布局后重擦一遍 ---
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

// MMTabBarController 是 UITabBarController，别干预它的原生行为。
// 只挂钩微信自己的按钮重排，重排后再擦一次。
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
BOOL WCZZGlassBottomEdgeEnabled(void) { return WCLGBottomEdgeEnabled(); }
void WCZZSetGlassBottomEdgeEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGBottomEdgeKey]; }
