#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

FOUNDATION_EXPORT NSString * const MMMenuEntryIdentifierKey;
FOUNDATION_EXPORT NSString * const MMMenuEntryTitleKey;
FOUNDATION_EXPORT NSString * const MMMenuEntryRemoveKey;
FOUNDATION_EXPORT NSString * const MMMenuEntryBuiltinKey;

FOUNDATION_EXPORT NSString * const MMMenuDefaultPluginTitle;
FOUNDATION_EXPORT NSString * const MMMenuDefaultPluginVersion;

/// Compact build stamp shown at the bottom of the settings screen.
FOUNDATION_EXPORT NSString * const MMMenuBuildDateString;

BOOL MMMenuIsEnabled(void);
void MMMenuSetEnabled(BOOL enabled);

BOOL MMMenuIsSortingEnabled(void);
void MMMenuSetSortingEnabled(BOOL enabled);

NSArray<NSDictionary *> *MMMenuDefaultEntries(void);
NSArray<NSDictionary *> *MMMenuLoadEntries(void);
void MMMenuSaveEntries(NSArray<NSDictionary *> *entries);

NSString *MMMenuPluginTitle(void);
NSString *MMMenuPluginVersion(void);
void MMMenuSetPluginIdentity(NSString *title, NSString *version);

/// Accepts `1`, `12`, `1.2`, `1.2-3`, `1.2.3` and `1.2.3-4` shaped strings.
BOOL MMMenuIsValidVersionString(NSString * _Nullable value);

NSString * _Nullable MMMenuNormalizeTitle(id _Nullable value);
NSString * _Nullable MMMenuItemTitle(id _Nullable item);
NSArray *MMMenuApplyPolicy(NSArray *items);

/// Captures titles from a live WeChat menu and merges any unseen titles into
/// the stored entries so they become manageable (hide/reorder) in settings.
/// Safe to call on every menu presentation; only new titles trigger a save.
void MMMenuCaptureTitles(NSArray *items);

/// File path of the harvested icon PNG for a captured menu title, if any.
NSString *MMMenuIconPathForTitle(NSString *title);

BOOL MMMenuPluginManagerAvailable(void);
void MMMenuRegisterWithPluginManager(void);

/// Re-registers under a new title/version and drops the previously registered
/// row so the plugin manager updates in place instead of gaining a duplicate.
void MMMenuUpdatePluginManagerRegistration(void);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
