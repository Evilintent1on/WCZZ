#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// One discovered item of the share / forward sheet.
FOUNDATION_EXPORT NSString * const WCZZShareMenuTitleKey;    // NSString
FOUNDATION_EXPORT NSString * const WCZZShareMenuHiddenKey;   // NSNumber(BOOL)
FOUNDATION_EXPORT NSString * const WCZZShareMenuSeenKey;     // NSNumber(NSInteger)

BOOL WCZZShareMenuIsEnabled(void);
void WCZZShareMenuSetEnabled(BOOL enabled);

/// Entries in discovery order: @{ title, hidden, seen }.
NSArray<NSDictionary *> *WCZZShareMenuLoadEntries(void);
void WCZZShareMenuSaveEntries(NSArray<NSDictionary *> * _Nullable entries);

BOOL WCZZShareMenuIsTitleHidden(NSString *title);
void WCZZShareMenuSetTitleHidden(NSString *title, BOOL hidden);

/// 不抓「转发给」好友那一行（默认 YES）。
BOOL WCZZShareMenuSkipsFirstRow(void);
void WCZZShareMenuSetSkipsFirstRow(BOOL skip);

/// Removes every stored entry (settings page “清空”).
void WCZZShareMenuResetAll(void);

/// A share/forward sheet is a view that contains both “转发给…” and “取消”.
BOOL WCZZShareMenuLooksLikeSheet(UIView * _Nullable view);

/// Walks the sheet and returns @{ title : itemContainerView }.
NSDictionary<NSString *, UIView *> *WCZZShareMenuItemsInSheet(UIView * _Nullable sheet);

/// Merges unseen titles into the stored entries (new ones default to visible).
/// Returns how many titles were added. Safe to call on every presentation.
NSInteger WCZZShareMenuCaptureFromSheet(UIView * _Nullable sheet);

/// Hides every item whose stored hidden flag is YES, then re-flows equal-size
/// cells in the same row. Returns how many containers got hidden this pass.
NSInteger WCZZShareMenuApplyToSheet(UIView * _Nullable sheet);

/// Called from the view-controller hooks: detect + capture + apply.
void WCZZShareMenuHandleHost(UIViewController * _Nullable host);

/// Sheet currently on screen (key window scan), or nil.
UIView * _Nullable WCZZShareMenuFindOpenSheet(void);

/// Capture from the sheet that is on screen right now. Returns added count.
NSInteger WCZZShareMenuCaptureOpenSheet(void);

/// Apply to the sheet that is on screen right now. Returns hidden count.
NSInteger WCZZShareMenuApplyOpenSheet(void);

/// Last time a sheet was handled (CACurrentMediaTime); 0 = never.
CFAbsoluteTime WCZZShareMenuLastActivity(void);

/// Raw view tree of the open sheet plus the stored list — used by “抓取详情”.
NSString *WCZZShareMenuDebugDump(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
