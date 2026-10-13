// wctabbar —— 让微信底栏回归 iOS 26 原生 Liquid Glass
//
//   MMTabBar                    : UITabBar
//   MMTabBarController          : UITabBarController
//   MainTabBarViewController    : MMTabBarController        ← 当前在用的
//   NewMainTabBarViewController : WCTabBarController : UIViewController  ← 新版自绘，挂不上系统 platter
//   MMTabbarItem                : UITabBarItem
//
// 思路是「减法」——微信自己就是 UITabBarController + UITabBar，它只是把外观覆盖掉了。
// 所以不去替换它，而是把覆盖剥掉，交还给系统渲染：
//   1. 屏蔽 UIDesignRequiresCompatibility（微信主动申请了旧版设计，这是根本原因）
//   2. 清掉微信画上去的背景容器
//   3. 把微信的 item 视图对齐到系统浮动胶囊的网格上
//   4. 关掉系统的滚动边缘模糊（底栏透明后它会露出来）

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------- 微信真实类 ----------
// 如实声明继承关系，编译器才知道它们是系统类的子类
@interface MMTabBar : UITabBar
@end

@interface MMTabBarController : UITabBarController
@end

// ---------- 开关 ----------
// 没有设置界面，直接读 NSUserDefaults 的 wclg_native_tabbar_enabled（默认开）。
// 启动时读一次并缓存 —— 底栏的 hook 在布局过程中反复跑，中途切换状态容易
// 和微信自己的 layout 打架，所以改动要重启微信才生效。
static NSString *const kWCLGEnabledKey = @"wclg_native_tabbar_enabled";

static BOOL WCLGEnabled(void) {
	static BOOL cached;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
		cached = ([d objectForKey:kWCLGEnabledKey] == nil) ? YES
														   : [d boolForKey:kWCLGEnabledKey];
	});
	return cached;
}

// ============================================================
//  关掉 iOS 26 的滚动边缘效果
//
//  UIKit.ScrollEdgeEffectView 是系统给可滚动内容下边缘加的模糊/渐隐，让内容滚到
//  浮动底栏底下时柔化过渡。底栏一透明它就露出来了（实测位于 {0,782},{420,130}，
//  正好压在底栏 y=822..912 下面）。
//
//  手段是下面的类级 hook：hook setHidden: 强制成 YES，UIKit 自己怎么设都无效。
// ============================================================

// ============================================================
//  擦掉微信画在底栏上的东西
//
//    · WCLGResetBarChrome        —— 底栏自身的底色，窗口/外观变化时做
//    · WCLGRemoveChromeContainer —— 微信塞的全尺寸背景容器，摘掉
//
//  容器检查必须放在 layoutSubviews 里：微信是「先 addSubview、再由自己的
//  layout 设尺寸」，didAddSubview: 那一刻子视图的 frame 还是 0，
//  满尺寸判定必然过不了。
// ============================================================
static void WCLGResetBarChrome(UITabBar *bar) {
	if (!bar || ![bar isKindOfClass:[UITabBar class]]) return;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	bar.translucent = YES;
	bar.opaque = NO;
	bar.backgroundColor = [UIColor clearColor];
	bar.layer.backgroundColor = [UIColor clearColor].CGColor;
	[CATransaction commit];
}

// 判断 sub 是不是微信的背景容器；是就摘掉并返回 YES
static BOOL WCLGRemoveChromeContainer(UITabBar *bar, UIView *sub) {
	if (!bar || !sub) return NO;

	NSString *cn = NSStringFromClass([sub class]);
	if ([cn containsString:@"Platter"] ||
		[cn containsString:@"LiquidLens"] ||
		[cn containsString:@"TabBarButton"] ||
		[cn containsString:@"ItemView"] ||
		[cn containsString:@"Container"] ||
		[cn containsString:@"_UITabButton"]) {
		return NO;
	}

	// 跟底栏一样大的容器 = 微信的底。frame 也必须是满的 ——
	// bounds 满尺寸但 frame 为 0×0 的是 portal 源视图（挂在屏幕外给
	// _UIPortalView 采样用），摘了会毁掉玻璃折射。
	CGFloat bw = CGRectGetWidth(bar.bounds), bh = CGRectGetHeight(bar.bounds);
	BOOL fullSize = CGRectGetWidth(sub.bounds) >= bw - 1.0 &&
					CGRectGetHeight(sub.bounds) >= bh - 1.0 &&
					CGRectGetWidth(sub.frame) > 1.0 &&
					CGRectGetHeight(sub.frame) > 1.0;
	if (!fullSize) return NO;

	// 从视图树里摘掉，而不是 hidden=YES —— 藏的话微信还能改回可见，
	// 摘掉就一劳永逸。整个子树一起走，所以不必再逐个清它子视图的底色。
	[sub removeFromSuperview];
	return YES;
}

// 扫一遍底栏的直接子视图，摘掉微信的背景容器。
//
// 必须在 layoutSubviews 里调用 —— 容器是「先 addSubview、再由微信自己的
// layout 设尺寸」的，didAddSubview: 那一刻它的 frame 还是 0，尺寸判定过不了。
// 摘掉后微信不重加的话，后续扫描就是遍历 ~7 个 subview，开销可忽略。
static BOOL WCLGStripChromeContainers(UITabBar *bar) {
	if (!bar) return NO;
	BOOL removed = NO;
	// 遍历中会 removeFromSuperview 改变数组，必须先 copy
	for (UIView *sub in [bar.subviews copy]) {
		if (WCLGRemoveChromeContainer(bar, sub)) removed = YES;
	}
	return removed;
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

	CGRect pf = [platter convertRect:platter.bounds toView:bar];
	CGFloat n = (CGFloat)items.count;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for (NSInteger i = 0; i < (NSInteger)n; i++) {
		UIView *iv = items[i];
		CGPoint c = iv.center;

		// 先将 item 框放到胶囊网格，再校正实际可见内容的中心。
		c.x = pf.origin.x + pf.size.width * ((CGFloat)i + 0.5) / n;

		CGRect content = CGRectNull;
		for (UIView *g in iv.subviews) {
			if (g.hidden || g.alpha < 0.01) continue;
			content = CGRectUnion(content, g.frame);
		}
		if (!CGRectIsNull(content)) {
			CGFloat contentMidXInBar = iv.frame.origin.x + CGRectGetMidX(content);
			CGFloat contentMidYInBar = iv.frame.origin.y + CGRectGetMidY(content);
			c.x += iv.center.x - contentMidXInBar;
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
//  内部类 _TtCC5UIKit20...BackdropView 跟着它一起被藏。
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

	// 首选 ObjC 名（实测能解析到）。备选的 mangled 名是从内部类
	// _TtCC5UIKit20...BackdropView 推导的，**从未验证过**，也从没生效过 ——
	// 留着是防将来 ObjC 名解析方式变了，成本为零。
	Class c = NSClassFromString(@"UIKit.ScrollEdgeEffectView");
	if (!c) c = objc_getClass("_TtC5UIKit20ScrollEdgeEffectView");
	// 解析不到就放弃（拿 nil 当 Class 调 MSHookMessageEx 会出事）
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

// --- 布局后：摘背景容器 + 对齐图标 ---
- (void)layoutSubviews {
	%orig;
	if (WCLGStripChromeContainers(self)) {
		WCLGResetBarChrome(self);
	}
	WCLGAlignTabBarItems(self);
}

- (void)didMoveToWindow {
	%orig;
	WCLGResetBarChrome(self);
}

- (void)didMoveToSuperview {
	%orig;
	WCLGResetBarChrome(self);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
	%orig;
	WCLGResetBarChrome(self);
}

%end

// MMTabBarController 是 UITabBarController，别干预它的原生行为。
// 只挂钩微信自己的按钮重排，重排后把底栏底色再确认一次。
// 让导航栏液态按钮里的图片符号在按钮可用区域内居中。
static void WCLGCenterNavigationButtonImages(UIView *view) {
	if (!view) return;
	if ([view isKindOfClass:[UIButton class]]) {
		UIButton *button = (UIButton *)view;
		if (button.currentImage) {
			button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
			button.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		}
	}
	for (UIView *subview in view.subviews) {
		WCLGCenterNavigationButtonImages(subview);
	}
}

%hook UINavigationBar
- (void)layoutSubviews {
	%orig;
	WCLGCenterNavigationButtonImages(self);
}
%end

// 搜索框高度过小时恢复标准触控高度，并将输入框垂直居中。
%hook UISearchBar
- (void)layoutSubviews {
	%orig;
	UITextField *field = self.searchTextField;
	if (field && CGRectGetHeight(field.frame) < 32.0) {
		CGRect fieldFrame = field.frame;
		fieldFrame.size.height = 32.0;
		fieldFrame.origin.y = (CGRectGetHeight(self.bounds) - fieldFrame.size.height) * 0.5;
		field.frame = fieldFrame;
	}
}
%end

%hook MMTabBarController

- (void)relayoutButtons:(BOOL)animated {
	%orig;
	WCLGResetBarChrome(self.tabBar);
}

%end


// ============================================================
//  wczz 设置页对接（1 个开关）
// ============================================================
BOOL WCZZTabBarGlassEnabled(void) { return WCLGEnabled(); }
void WCZZSetTabBarGlassEnabled(BOOL v) { [[NSUserDefaults standardUserDefaults] setBool:v forKey:kWCLGEnabledKey]; }
