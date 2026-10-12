#import <UIKit/UIKit.h>

// ============================================================
//  wctabbar —— 只保留「底栏液态玻璃」，其他效果全部去除
//
//  保留（= 底栏效果本身）：
//    · MMTabBar      擦掉微信画在底栏上的不透明底/毛玻璃，让系统原生浮动玻璃露出来
//    · MMTabBar      把 MMTabBarItemView 对齐到系统胶囊（Platter）的网格上
//    · MMTabBarController relayoutButtons: 之后补擦一次
//
//  保留但加了开关：
//    · NSBundle 抹掉 UIDesignRequiresCompatibility —— 这是**底栏能变成浮动玻璃的前提**
//      （微信 Info.plist 声明了退回旧设计，所以底栏才是全宽不透明）。关掉它底栏就没玻璃了，
//      但顶部绝对不变。默认开。
//
//  去掉（原来会影响底部以外的地方）：
//    · 原来把 UIKit.ScrollEdgeEffectView **每个实例**都强制隐藏 —— 顶部导航栏下方那条
//      模糊/渐隐用的是同一个类，所以顶部也被改。现在只处理**底部那一条**（按位置判定），
//      顶部完全放行。
//    · 输入框玻璃、输入栏重做、顶部校正、诊断 —— 全部删除。
//
//  开关（NSUserDefaults，实时生效）：
//    wclg_native_tabbar_enabled  总开关           默认开
//    wclg_ios26_design           设计系统开关      默认开（底栏玻璃的前提）
//    wclg_hide_bottom_edge       底部边缘效果      默认开（只关底部那一条，不碰顶部）
// ============================================================

// ---------- 微信真实类 ----------
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// ---------- 开关 ----------
static NSString *const kWCLGEnabledKey    = @"wclg_native_tabbar_enabled";
static NSString *const kWCLGDesignKey     = @"wclg_ios26_design";
static NSString *const kWCLGBottomEdgeKey = @"wclg_hide_bottom_edge";

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

// ============================================================
//  关掉毛玻璃（只作用于底栏，天然不影响别处）
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
		// bounds 满尺寸但 frame 为 0×0 的是 portal 源视图，藏了会毁掉玻璃折射。
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
//  系统的浮动胶囊是内缩的，而微信的 MMTabBarItemView 是按全宽均分的。
//  这里拿 platter 的 frame 当基准，把 item 视图摆到胶囊的网格上，并让内容垂直居中到胶囊。
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

		// 位置已经对了就别写 —— 无条件写 frame 会让 UIKit 标记重新布局，反过来又触发 layoutSubviews
		if (fabs(iv.center.x - c.x) < 0.5 && fabs(iv.center.y - c.y) < 0.5) continue;
		iv.center = c;
	}
	[CATransaction commit];
}

// ============================================================
//  让 UIKit 认为微信没申请旧版设计
//
//  微信 Info.plist 里有 UIDesignRequiresCompatibility = true，这是它底栏是
//  「全宽不透明」而不是 iOS 26 浮动玻璃的根本原因。UIKit 走 NSBundle 读这个 key，这里把它屏蔽掉。
//
//  注意：这条是**应用级**的（顶部也会跟着走新设计）。它是底栏玻璃的前提，
//  所以默认保留；不想要的话把 wclg_ios26_design 关掉（底栏也会回到原来的全宽底）。
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
//  滚动边缘效果：**只关底部那一条**
//
//  原版把 UIKit.ScrollEdgeEffectView 的每个实例都强制隐藏 —— 顶部导航栏下方那条
//  模糊/渐隐用的是同一个类，所以顶部也被一起改掉了。
//  现在按位置区分：只有落在屏幕下方 45% 的实例才处理，顶部实例原样放行。
//  （它属于底栏区域的效果，所以默认开；不想要把 wclg_hide_bottom_edge 关掉。）
// ============================================================
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
	return CGRectGetMidY(r) > h * 0.55;
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
	if (!c) return;   // 解析不到就算了，不影响底栏其它逻辑

	MSHookMessageEx(c, @selector(setHidden:),
		(IMP)wclg_SEV_setHidden, (IMP *)&wclg_orig_SEV_setHidden);
	MSHookMessageEx(c, @selector(layoutSubviews),
		(IMP)wclg_SEV_layoutSubviews, (IMP *)&wclg_orig_SEV_layoutSubviews);
}

%ctor {
	WCLGHookScrollEdgeEffectView();
}

// ============================================================
//  底栏
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
