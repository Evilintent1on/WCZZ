#import <UIKit/UIKit.h>

// ---------- 微信真实类 ----------
// 如实声明继承关系，编译器才知道它们是系统类的子类
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// ---------- 开关 ----------
static NSString *const kWCLGEnabledKey = @"wclg_native_tabbar_enabled";

static BOOL WCLGEnabled(void) {
	static BOOL cached;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
		cached = ([d objectForKey:kWCLGEnabledKey] == nil) ? YES : [d boolForKey:kWCLGEnabledKey];
	});
	return cached;
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

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < (NSInteger)n; i++) {
		UIView *iv = items[i];
		CGPoint c = iv.center;

		// 水平：摆到胶囊的网格上
		c.x = pf.origin.x + pf.size.width * ((CGFloat)i + 0.5) / n;

		// 垂直：让 item 内容的中心落在胶囊中心
		CGRect content = CGRectNull;
		for (UIView *g in iv.subviews) {
			if (g.hidden) continue;
			content = CGRectUnion(content, g.frame);
		}
		if (!CGRectIsNull(content)) {
			CGFloat contentMidYInBar = iv.frame.origin.y + CGRectGetMidY(content);
			c.y += CGRectGetMidY(pf) - contentMidYInBar;
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
	if (WCLGIsMainBundle(self) && [key isEqualToString:@"UIDesignRequiresCompatibility"]) {
		return @NO;
	}
	return %orig;
}

- (NSDictionary *)infoDictionary {
	NSDictionary *d = %orig;
	if (WCLGIsMainBundle(self) && d[@"UIDesignRequiresCompatibility"] != nil) {
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
//  wczz 设置页对接（加在原版末尾，原有代码一字未动）
// ============================================================
BOOL WCZZTabBarGlassEnabled(void) {
	return WCLGEnabled();
}

void WCZZSetTabBarGlassEnabled(BOOL enabled) {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWCLGEnabledKey];
}
