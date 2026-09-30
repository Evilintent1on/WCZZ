#import "MessageMenuConfig.h"
#import "WeChatHeaders.h"

#import <objc/message.h>
#import <objc/runtime.h>

NSString * const MMMenuEntryIdentifierKey = @"identifier";
NSString * const MMMenuEntryTitleKey = @"title";
NSString * const MMMenuEntryRemoveKey = @"remove";
NSString * const MMMenuEntryBuiltinKey = @"builtin";

NSString * const MMMenuDefaultPluginTitle = @"菜单自定义";
NSString * const MMMenuDefaultPluginVersion = @"1.1-0";
NSString * const MMMenuBuildDateString = @"Built on 2026.08.19";

static NSString * const kMMMenuEnabledKey        = @"MessageMenu.enabled";
static NSString * const kMMMenuSortingEnabledKey  = @"MessageMenu.sortingEnabled";
static NSString * const kMMMenuEntriesKey         = @"MessageMenu.entries.v1";
static NSString * const kMMMenuPluginTitleKey     = @"MessageMenu.pluginTitle";
static NSString * const kMMMenuPluginVersionKey   = @"MessageMenu.pluginVersion";

// Backward-compat key kept for migration from older versions.
static NSString * const kMMLegacyRemoveTitlesKey  = @"jj_custom_remove_menu_titles";

static NSDictionary *MMMenuEntry(NSString *identifier, NSString *title,
                                  BOOL remove, BOOL builtin) {
    return @{
        MMMenuEntryIdentifierKey: identifier,
        MMMenuEntryTitleKey:      title,
        MMMenuEntryRemoveKey:     @(remove),
        MMMenuEntryBuiltinKey:    @(builtin),
    };
}

NSString *MMMenuNormalizeTitle(id value) {
    if ([value isKindOfClass:[NSAttributedString class]]) {
        value = [(NSAttributedString *)value string];
    }
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *s = [(NSString *)value
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length > 0 ? s : nil;
}

NSArray<NSDictionary *> *MMMenuDefaultEntries(void) {
    static NSArray<NSDictionary *> *entries;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        entries = @[
            MMMenuEntry(@"copy",            @"复制",         NO, YES),
            MMMenuEntry(@"forward",         @"转发",         NO, YES),
            MMMenuEntry(@"favorite",        @"收藏",         NO, YES),
            MMMenuEntry(@"quote",           @"引用",         NO, YES),
            MMMenuEntry(@"translate",       @"翻译",         NO, YES),
            MMMenuEntry(@"search",          @"搜一搜",       NO, YES),
            MMMenuEntry(@"remind",          @"提醒",         NO, YES),
            MMMenuEntry(@"revoke",          @"撤回",         NO, YES),
            MMMenuEntry(@"delete",          @"删除",         NO, YES),
            MMMenuEntry(@"multi_select",    @"多选",         NO, YES),
            MMMenuEntry(@"open",            @"打开",         NO, YES),
        ];
    });
    return entries;
}

static NSArray<NSDictionary *> *MMMenuSanitizedEntries(NSArray *rawEntries,
                                                        BOOL appendMissingDefaults) {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    NSMutableSet<NSString *> *seenTitles      = [NSMutableSet set];

    if ([rawEntries isKindOfClass:[NSArray class]]) {
        for (id rawEntry in rawEntries) {
            if (![rawEntry isKindOfClass:[NSDictionary class]]) continue;

            NSDictionary *dict  = (NSDictionary *)rawEntry;
            NSString *title     = MMMenuNormalizeTitle(dict[MMMenuEntryTitleKey]);
            if (!title || [seenTitles containsObject:title]) continue;

            NSString *identifier = MMMenuNormalizeTitle(dict[MMMenuEntryIdentifierKey]);
            if (!identifier || [seenIdentifiers containsObject:identifier]) {
                identifier = [NSString stringWithFormat:@"custom.%@",
                              [[NSUUID UUID] UUIDString]];
            }

            id removeValue = dict[MMMenuEntryRemoveKey];
            id builtinValue = dict[MMMenuEntryBuiltinKey];
            BOOL remove = [removeValue respondsToSelector:@selector(boolValue)]
                ? [removeValue boolValue] : NO;
            BOOL builtin = [builtinValue respondsToSelector:@selector(boolValue)]
                ? [builtinValue boolValue] : NO;
            [result addObject:MMMenuEntry(identifier, title, remove, builtin)];
            [seenIdentifiers addObject:identifier];
            [seenTitles addObject:title];
        }
    }

    if (appendMissingDefaults) {
        for (NSDictionary *def in MMMenuDefaultEntries()) {
            NSString *identifier = def[MMMenuEntryIdentifierKey];
            NSString *title      = def[MMMenuEntryTitleKey];
            if ([seenIdentifiers containsObject:identifier] ||
                [seenTitles containsObject:title]) continue;
            [result addObject:def];
            [seenIdentifiers addObject:identifier];
            [seenTitles addObject:title];
        }
    }

    return [result copy];
}

/// Entries dropped from the built-in list in this version. Stored
/// configurations and imported backups from earlier builds may still contain
/// them, so built-in copies are pruned whenever data crosses the config API.
static NSArray<NSString *> *MMMenuRetiredIdentifiers(void) {
    return @[@"edit", @"save_image", @"scan_qr", @"plus_one", @"emoticon_resize"];
}

static NSArray<NSString *> *MMMenuRetiredTitles(void) {
    return @[@"编辑", @"保存图片", @"识别图中二维码", @"+1", @"大大小小"];
}

static NSArray<NSDictionary *> *MMMenuEntriesWithoutRetiredDefaults(NSArray<NSDictionary *> *entries) {
    NSSet<NSString *> *identifiers = [NSSet setWithArray:MMMenuRetiredIdentifiers()];
    NSSet<NSString *> *titles      = [NSSet setWithArray:MMMenuRetiredTitles()];

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:entries.count];
    for (NSDictionary *entry in entries) {
        // A retired built-in identifier is authoritative even if an older
        // backup lost its `builtin` flag. User-created entries that merely use
        // the same title keep their data and remain available.
        if ([identifiers containsObject:entry[MMMenuEntryIdentifierKey]] ||
            ([entry[MMMenuEntryBuiltinKey] boolValue] &&
             [titles containsObject:entry[MMMenuEntryTitleKey]])) {
            continue;
        }
        [result addObject:entry];
    }
    return [result copy];
}

static NSArray<NSString *> *MMMenuLegacyRemoveTitles(void) {
    NSString *raw = MMMenuNormalizeTitle(
        [[NSUserDefaults standardUserDefaults] stringForKey:kMMLegacyRemoveTitlesKey]);
    if (!raw) return @[];

    NSCharacterSet *seps = [NSCharacterSet characterSetWithCharactersInString:@",，、;；\n\r"];
    NSMutableOrderedSet<NSString *> *titles = [NSMutableOrderedSet orderedSet];
    for (NSString *part in [raw componentsSeparatedByCharactersInSet:seps]) {
        NSString *t = MMMenuNormalizeTitle(part);
        if (t) [titles addObject:t];
    }
    return titles.array;
}

static NSArray<NSDictionary *> *MMMenuEntriesMigratedFromLegacy(void) {
    NSMutableArray<NSDictionary *> *entries =
        [NSMutableArray arrayWithArray:MMMenuDefaultEntries()];

    for (NSString *legacyTitle in MMMenuLegacyRemoveTitles()) {
        if ([MMMenuRetiredTitles() containsObject:legacyTitle]) continue;
        NSUInteger index = [entries indexOfObjectPassingTest:
            ^BOOL(NSDictionary *e, NSUInteger i, BOOL *s) {
        (void)i; (void)s;
                return [e[MMMenuEntryTitleKey] isEqualToString:legacyTitle];
            }];
        if (index != NSNotFound) {
            NSMutableDictionary *updated = [entries[index] mutableCopy];
            updated[MMMenuEntryRemoveKey] = @YES;
            entries[index] = [updated copy];
        } else {
            NSString *ident = [NSString stringWithFormat:@"custom.%@",
                               [[NSUUID UUID] UUIDString]];
            [entries addObject:MMMenuEntry(ident, legacyTitle, YES, NO)];
        }
    }
    return MMMenuSanitizedEntries(entries, YES);
}

BOOL MMMenuIsEnabled(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kMMMenuEnabledKey];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES;
}

void MMMenuSetEnabled(BOOL enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:enabled forKey:kMMMenuEnabledKey];
    [d synchronize];
}

BOOL MMMenuIsSortingEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kMMMenuSortingEnabledKey];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

void MMMenuSetSortingEnabled(BOOL enabled) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:enabled forKey:kMMMenuSortingEnabledKey];
    [d synchronize];
}

NSArray<NSDictionary *> *MMMenuLoadEntries(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:kMMMenuEntriesKey];
    if (![stored isKindOfClass:[NSArray class]]) return MMMenuEntriesMigratedFromLegacy();

    NSArray<NSDictionary *> *entries = MMMenuSanitizedEntries((NSArray *)stored, YES);
    NSArray<NSDictionary *> *pruned = MMMenuEntriesWithoutRetiredDefaults(entries);
    if (pruned.count != entries.count) {
        [defaults setObject:pruned forKey:kMMMenuEntriesKey];
        [defaults synchronize];
    }
    return pruned;
}

void MMMenuSaveEntries(NSArray<NSDictionary *> *entries) {
    NSArray<NSDictionary *> *sanitized = MMMenuEntriesWithoutRetiredDefaults(
        MMMenuSanitizedEntries(entries, YES));
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:sanitized forKey:kMMMenuEntriesKey];

    // Also keep legacy key in sync for other plugins that may read it.
    NSMutableArray<NSString *> *removeTitles = [NSMutableArray array];
    for (NSDictionary *entry in sanitized) {
        if ([entry[MMMenuEntryRemoveKey] boolValue]) {
            NSString *t = MMMenuNormalizeTitle(entry[MMMenuEntryTitleKey]);
            if (t) [removeTitles addObject:t];
        }
    }
    if (removeTitles.count > 0) {
        [defaults setObject:[removeTitles componentsJoinedByString:@"，"]
                     forKey:kMMLegacyRemoveTitlesKey];
    } else {
        [defaults removeObjectForKey:kMMLegacyRemoveTitlesKey];
    }
    [defaults synchronize];
}

NSString *MMMenuPluginTitle(void) {
    NSString *t = MMMenuNormalizeTitle(
        [[NSUserDefaults standardUserDefaults] stringForKey:kMMMenuPluginTitleKey]);
    return t ?: MMMenuDefaultPluginTitle;
}

NSString *MMMenuPluginVersion(void) {
    NSString *v = MMMenuNormalizeTitle(
        [[NSUserDefaults standardUserDefaults] stringForKey:kMMMenuPluginVersionKey]);
    return v ?: MMMenuDefaultPluginVersion;
}

BOOL MMMenuIsValidVersionString(NSString *value) {
    NSString *version = MMMenuNormalizeTitle(value);
    if (version.length == 0 || version.length > 20) return NO;

    // Accepted shapes: 1, 1.2, 1.2.3 and any of those with a -N build suffix.
    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        expression = [NSRegularExpression
            regularExpressionWithPattern:@"^[0-9]+(\\.[0-9]+){0,2}(-[0-9]+)?$"
                                 options:0
                                   error:NULL];
    });
    if (!expression) return YES;

    NSRange range = NSMakeRange(0, version.length);
    return [expression numberOfMatchesInString:version options:0 range:range] == 1;
}

void MMMenuSetPluginIdentity(NSString *title, NSString *version) {
    title   = MMMenuNormalizeTitle(title)   ?: MMMenuDefaultPluginTitle;
    version = MMMenuNormalizeTitle(version) ?: MMMenuDefaultPluginVersion;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([title isEqualToString:MMMenuDefaultPluginTitle]) {
        [d removeObjectForKey:kMMMenuPluginTitleKey];
    } else {
        [d setObject:title forKey:kMMMenuPluginTitleKey];
    }
    if ([version isEqualToString:MMMenuDefaultPluginVersion]) {
        [d removeObjectForKey:kMMMenuPluginVersionKey];
    } else {
        [d setObject:version forKey:kMMMenuPluginVersionKey];
    }
    [d synchronize];
}

// ---------------------------------------------------------------------------
// Title extraction from WeChat menu item objects.
// MMMenuItem : UIMenuItem, so `-title` is standard. We also try a few other
// selectors defensively in case WeChat internally uses a custom subclass that
// overrides or wraps the title differently.
// ---------------------------------------------------------------------------
NSString *MMMenuItemTitle(id item) {
    if (!item) return nil;

    if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)item;
        for (NSString *key in @[@"title", @"menuItemTitle", @"itemTitle", @"m_nsTitle",
                                @"m_nsText", @"text", @"name", @"displayName"]) {
            NSString *value = MMMenuNormalizeTitle(dictionary[key]);
            if (value) return value;
        }
    }

    static SEL titleSelectors[11];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titleSelectors[0] = @selector(title);
        titleSelectors[1] = sel_registerName("menuItemTitle");
        titleSelectors[2] = sel_registerName("itemTitle");
        titleSelectors[3] = sel_registerName("m_nsTitle");
        titleSelectors[4] = sel_registerName("m_nsText");
        titleSelectors[5] = sel_registerName("text");
        titleSelectors[6] = sel_registerName("name");
        titleSelectors[7] = sel_registerName("displayName");
        titleSelectors[8] = @selector(accessibilityLabel);
        titleSelectors[9] = sel_registerName("localizedTitle");
        titleSelectors[10] = sel_registerName("label");
    });

    for (NSUInteger i = 0; i < 11; i++) {
        SEL sel = titleSelectors[i];
        if (![item respondsToSelector:sel]) continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(item, sel);
            NSString *normalized = MMMenuNormalizeTitle(value);
            if (normalized) return normalized;
        } @catch (__unused NSException *e) {}
    }

    // A number of WeChat builds expose the title only through KVC on a
    // private MMMenuItem object. KVC is guarded because some objects throw for
    // unknown keys instead of returning nil.
    for (NSString *key in @[@"title", @"menuItemTitle", @"itemTitle", @"m_nsTitle",
                            @"m_nsText", @"text", @"name", @"displayName"]) {
        @try {
            NSString *value = MMMenuNormalizeTitle([item valueForKey:key]);
            if (value) return value;
        } @catch (__unused NSException *e) {}
    }

    // UIMenuItem always carries its action selector.  This fallback is useful
    // for third-party items that render a title in a custom view but leave the
    // inherited `title` property empty.
    if ([item respondsToSelector:@selector(action)]) {
        @try {
            SEL action = ((SEL (*)(id, SEL))objc_msgSend)(item, @selector(action));
            NSString *name = action ? NSStringFromSelector(action) : nil;
            NSDictionary<NSString *, NSString *> *knownActions = @{
                @"onCopy:":                    @"复制",
                @"copy:":                      @"复制",
                @"onForward:":                 @"转发",
                @"forward:":                   @"转发",
                @"onFavorite:":                @"收藏",
                @"favorite:":                  @"收藏",
                @"onShowMsgReplyMenuItem:":    @"引用",
                @"reply:":                     @"引用",
                @"onTranslate:":               @"翻译",
                @"translate:":                 @"翻译",
                @"onShowFTSIndexMenuItem:":    @"搜一搜",
                @"onSchedule:":                @"提醒",
                @"onRevokeMsg:":               @"撤回",
                @"onEdit:":                    @"编辑",
                @"onDelete:":                  @"删除",
                @"delete:":                    @"删除",
            };
            NSString *mapped = name ? knownActions[name] : nil;
            if (!mapped && name.length) {
                NSString *lower = name.lowercaseString;
                NSArray<NSArray<NSString *> *> *keywords = @[
                    @[@"copy", @"复制"], @[@"forward", @"转发"], @[@"favorite", @"收藏"],
                    @[@"reply", @"引用"], @[@"translate", @"翻译"], @[@"search", @"搜一搜"],
                    @[@"revoke", @"撤回"], @[@"delete", @"删除"], @[@"edit", @"编辑"]
                ];
                for (NSArray<NSString *> *pair in keywords) {
                    if ([lower containsString:pair[0]]) { mapped = pair[1]; break; }
                }
            }
            if (mapped) return mapped;
        } @catch (__unused NSException *e) {}
    }

    for (NSString *key in @[@"m_selAction", @"selector", @"m_selector"]) {
        @try {
            id value = [item valueForKey:key];
            if ([value isKindOfClass:[NSString class]]) {
                NSString *lower = [(NSString *)value lowercaseString];
                NSDictionary<NSString *, NSString *> *keywords = @{
                    @"copy": @"复制", @"forward": @"转发", @"favorite": @"收藏",
                    @"reply": @"引用", @"translate": @"翻译", @"search": @"搜一搜",
                    @"revoke": @"撤回", @"delete": @"删除", @"edit": @"编辑"
                };
                for (NSString *keyword in keywords) {
                    if ([lower containsString:keyword]) return keywords[keyword];
                }
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

NSArray *MMMenuApplyPolicy(NSArray *items) {
    if (!MMMenuIsEnabled() ||
        ![items isKindOfClass:[NSArray class]] ||
        items.count == 0) {
        return items;
    }

    NSArray<NSDictionary *> *entries = MMMenuLoadEntries();
    NSMutableSet<NSString *> *removeTitles = [NSMutableSet set];
    NSMutableDictionary<NSString *, NSNumber *> *rankByTitle =
        [NSMutableDictionary dictionary];

    // The settings UI stores both lists in one backwards-compatible array, but
    // removed entries must never participate in the visible-item ordering.
    // Build ranks from the retained list only.  This is also what makes moving
    // rows in the retained screen deterministic when the removed list changes.
    __block NSUInteger retainedRank = 0;
    [entries enumerateObjectsUsingBlock:^(NSDictionary *entry,
                                          NSUInteger index,
                                          BOOL *stop) {
        (void)index; (void)stop;
        NSString *t = MMMenuNormalizeTitle(entry[MMMenuEntryTitleKey]);
        if (!t) return;
        if ([entry[MMMenuEntryRemoveKey] boolValue]) {
            [removeTitles addObject:t];
            return;
        }
        if (!rankByTitle[t]) rankByTitle[t] = @(retainedRank);
        retainedRank++;
    }];

    BOOL sortEnabled = MMMenuIsSortingEnabled();
    if (removeTitles.count == 0 && !sortEnabled) return items;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        NSString *t = MMMenuItemTitle(item);
        if (t && [removeTitles containsObject:t]) continue;
        [filtered addObject:item];
    }

    if (!sortEnabled || filtered.count < 2) return [filtered copy];

    // Only configured items are reordered; unknown items keep their relative positions.
    NSMutableArray<NSNumber *>    *configuredIndexes = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *configuredItems   = [NSMutableArray array];

    [filtered enumerateObjectsUsingBlock:^(id item, NSUInteger index, BOOL *s) {
        (void)s;
        NSString *t = MMMenuItemTitle(item);
        NSNumber *rank = t ? rankByTitle[t] : nil;
        if (!rank) return;
        [configuredIndexes addObject:@(index)];
        [configuredItems addObject:@{
            @"item":     item,
            @"rank":     rank,
            @"sequence": @(configuredItems.count),
        }];
    }];

    if (configuredItems.count < 2) return [filtered copy];

    [configuredItems sortUsingComparator:^NSComparisonResult(NSDictionary *l,
                                                              NSDictionary *r) {
        NSComparisonResult res = [l[@"rank"] compare:r[@"rank"]];
        return res != NSOrderedSame ? res : [l[@"sequence"] compare:r[@"sequence"]];
    }];

    [configuredIndexes enumerateObjectsUsingBlock:^(NSNumber *idxNum,
                                                     NSUInteger i,
                                                     BOOL *s) {
        (void)s;
        filtered[idxNum.unsignedIntegerValue] = configuredItems[i][@"item"];
    }];

    return [filtered copy];
}

// ---------------------------------------------------------------------------
// Live menu capture: harvest real titles from WeChat's menu items so anything
// WeChat shows (including items missing from the builtin list) becomes
// manageable in settings. Matching stays title-based, same as the policy.
// Icons are also harvested when the item carries one, saved as PNG files so
// the settings list can show the same icon WeChat shows.
// ---------------------------------------------------------------------------
static NSString *MMMenuCapturedIconsDir(void) {
    static NSString *dir;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory, NSUserDomainMask, YES);
        dir = [[paths.firstObject
            stringByAppendingPathComponent:@"WCZZMenuIcons"] copy];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    });
    return dir;
}

static NSUInteger MMMenuStableHash(NSString *s) {
    // DJB2, deterministic across launches (NSString -hash is not guaranteed).
    NSUInteger h = 5381;
    for (NSUInteger i = 0; i < s.length; i++) {
        h = ((h << 5) + h) + [s characterAtIndex:i];
    }
    return h;
}

NSString *MMMenuIconPathForTitle(NSString *title) {
    NSString *name = [NSString stringWithFormat:@"%lx.png",
                      (unsigned long)MMMenuStableHash(title ?: @"")];
    return [MMMenuCapturedIconsDir() stringByAppendingPathComponent:name];
}

static UIImage *MMMenuItemIcon(id item) {
    if (!item) return nil;
    static SEL iconSelectors[5];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        iconSelectors[0] = sel_registerName("image");
        iconSelectors[1] = sel_registerName("icon");
        iconSelectors[2] = sel_registerName("menuImage");
        iconSelectors[3] = sel_registerName("menuIcon");
        iconSelectors[4] = sel_registerName("itemImage");
    });
    for (NSUInteger i = 0; i < 5; i++) {
        SEL sel = iconSelectors[i];
        if (![item respondsToSelector:sel]) continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(item, sel);
            if ([value isKindOfClass:[UIImage class]]) return value;
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

void MMMenuCaptureTitles(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return;

    NSMutableOrderedSet<NSString *> *titles = [NSMutableOrderedSet orderedSet];
    NSMutableDictionary<NSString *, UIImage *> *iconsByTitle = [NSMutableDictionary dictionary];
    for (id item in items) {
        @try {
            NSString *t = MMMenuItemTitle(item);
            if (!t.length) continue;
            [titles addObject:t];
            UIImage *icon = MMMenuItemIcon(item);
            if (icon && !iconsByTitle[t]) iconsByTitle[t] = icon;
        } @catch (__unused NSException *e) {}
    }
    if (titles.count == 0) return;

    NSArray<NSDictionary *> *entries = MMMenuLoadEntries();
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (NSDictionary *e in entries) {
        NSString *t = MMMenuNormalizeTitle(e[MMMenuEntryTitleKey]);
        if (t) [known addObject:t];
    }

    NSMutableArray<NSDictionary *> *merged = [entries mutableCopy];
    NSMutableOrderedSet<NSString *> *newTitles = [NSMutableOrderedSet orderedSet];
    BOOL changed = NO;
    for (NSString *t in titles) {
        if ([known containsObject:t]) continue;
        NSString *ident = [NSString stringWithFormat:@"captured.%@",
                           [[NSUUID UUID] UUIDString]];
        [merged addObject:MMMenuEntry(ident, t, NO, NO)];
        [known addObject:t];
        [newTitles addObject:t];
        changed = YES;
    }
    if (changed) MMMenuSaveEntries(merged);

    // Persist harvested icons for newly captured titles so the settings list
    // can show the same icon WeChat shows.
    for (NSString *t in newTitles) {
        UIImage *icon = iconsByTitle[t];
        if (!icon) continue;
        @try {
            NSData *data = UIImagePNGRepresentation(icon);
            if (data) [data writeToFile:MMMenuIconPathForTitle(t) atomically:YES];
        } @catch (__unused NSException *e) {}
    }
}

// ---------------------------------------------------------------------------
// Plugin manager registration (WCPluginsMgr). Not present in all WeChat
// builds; checked at runtime so absence is silently ignored.
// ---------------------------------------------------------------------------
static id MMMenuPluginManagerInstance(void) {
    Class cls = NSClassFromString(@"WCPluginsMgr");
    SEL   sel = @selector(sharedInstance);
    if (!cls || ![cls respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)((id)cls, sel);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

BOOL MMMenuPluginManagerAvailable(void) {
    id mgr = MMMenuPluginManagerInstance();
    return mgr && [mgr respondsToSelector:
                   @selector(registerControllerWithTitle:version:controller:)];
}

static NSString * const kMMMenuControllerName = @"MessageMenuSettingsController";
static NSString *gMMMenuLastRegisteredSignature;
static __weak id gMMMenuLastManager;

static BOOL MMMenuValueNamesOurController(id object) {
    if ([object isKindOfClass:[NSString class]]) {
        return [(NSString *)object isEqualToString:kMMMenuControllerName];
    }
    if (object && class_isMetaClass(object_getClass(object))) {
        return [NSStringFromClass((Class)object) isEqualToString:kMMMenuControllerName];
    }
    return NO;
}

/// Recognises one plugin row without treating a whole section that happens to
/// contain our row as ours. That distinction prevents deleting sibling plugins
/// when a manager groups rows into nested arrays.
static BOOL MMMenuEntryIsOurs(id object) {
    if (!object) return NO;
    if (MMMenuValueNamesOurController(object)) return YES;

    NSArray<NSString *> *controllerKeys = @[
        @"controller", @"controllerName", @"controllerClass", @"controllerClassName",
        @"className", @"vcName", @"viewController", @"viewControllerName",
        @"targetController", @"targetClassName"
    ];
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        for (NSString *key in controllerKeys) {
            if (MMMenuValueNamesOurController(dictionary[key])) return YES;
        }
        // Some manager versions use an obfuscated key but still store the
        // controller class name as a direct value on the row.
        for (id value in dictionary.allValues) {
            if (MMMenuValueNamesOurController(value)) return YES;
        }
        return NO;
    }
    if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
        for (id value in object) {
            if (MMMenuValueNamesOurController(value)) return YES;
        }
        return NO;
    }

    for (NSString *key in controllerKeys) {
        @try {
            if (MMMenuValueNamesOurController([object valueForKey:key])) return YES;
        } @catch (__unused NSException *e) {}
    }
    return NO;
}

static void MMMenuRemoveOursFromContainer(id container, NSUInteger depth) {
    if (!container || depth > 3) return;

    if ([container isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *array = container;
        NSMutableIndexSet *doomed = [NSMutableIndexSet indexSet];
        [array enumerateObjectsUsingBlock:^(id entry, NSUInteger idx, BOOL *stop) {
            (void)stop;
            if (MMMenuEntryIsOurs(entry)) {
                [doomed addIndex:idx];
            } else {
                MMMenuRemoveOursFromContainer(entry, depth + 1);
            }
        }];
        @try {
            if (doomed.count) [array removeObjectsAtIndexes:doomed];
        } @catch (__unused NSException *e) {}
        return;
    }

    if ([container isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *dictionary = container;
        NSMutableArray *doomed = [NSMutableArray array];
        for (id key in dictionary.allKeys) {
            id value = dictionary[key];
            if (MMMenuEntryIsOurs(value) ||
                ([key isKindOfClass:[NSString class]] &&
                 [(NSString *)key isEqualToString:kMMMenuControllerName])) {
                [doomed addObject:key];
            } else {
                MMMenuRemoveOursFromContainer(value, depth + 1);
            }
        }
        @try {
            for (id key in doomed) [dictionary removeObjectForKey:key];
        } @catch (__unused NSException *e) {}
        return;
    }

    if ([container isKindOfClass:[NSArray class]]) {
        for (id value in container) MMMenuRemoveOursFromContainer(value, depth + 1);
    } else if ([container isKindOfClass:[NSDictionary class]]) {
        for (id value in [(NSDictionary *)container allValues]) {
            MMMenuRemoveOursFromContainer(value, depth + 1);
        }
    }
}

/// Removes our previously registered row from every mutable collection the
/// manager holds.  WCPluginsMgr has no public unregister API and its storage
/// differs between builds, so the ivars are scanned instead of guessed.
static void MMMenuRemoveExistingRegistration(id manager) {
    if (!manager) return;

    for (Class cls = object_getClass(manager); cls && cls != [NSObject class];
         cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        if (!ivars) continue;

        for (unsigned int i = 0; i < count; i++) {
            const char *encoding = ivar_getTypeEncoding(ivars[i]);
            if (!encoding || encoding[0] != '@') continue;

            id value = nil;
            @try { value = object_getIvar(manager, ivars[i]); }
            @catch (__unused NSException *e) { continue; }

            MMMenuRemoveOursFromContainer(value, 0);
        }
        free(ivars);
    }
}

void MMMenuRegisterWithPluginManager(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ MMMenuRegisterWithPluginManager(); });
        return;
    }

    id mgr = MMMenuPluginManagerInstance();
    SEL sel = @selector(registerControllerWithTitle:version:controller:);
    if (!mgr || ![mgr respondsToSelector:sel]) return;

    NSString *title     = MMMenuPluginTitle();
    NSString *version   = MMMenuPluginVersion();
    NSString *signature = [NSString stringWithFormat:@"%@\n%@", title, version];

    if (gMMMenuLastManager == mgr &&
        [gMMMenuLastRegisteredSignature isEqualToString:signature]) return;

    // Registering under a new title/version would otherwise leave the previous
    // row in place and the manager would show one entry per rename.
    MMMenuRemoveExistingRegistration(mgr);

    @try {
        typedef void (*RegIMP)(id, SEL, NSString *, NSString *, NSString *);
        ((RegIMP)objc_msgSend)(mgr, sel, title, version, kMMMenuControllerName);
        gMMMenuLastRegisteredSignature = [signature copy];
        gMMMenuLastManager = mgr;
    } @catch (__unused NSException *e) {
        gMMMenuLastRegisteredSignature = nil;
        gMMMenuLastManager = nil;
    }
}

void MMMenuUpdatePluginManagerRegistration(void) {
    // MMMenuRegisterWithPluginManager already compares the current identity
    // against the last registered signature. Keeping that cache means ordinary
    // menu edits do not rescan and rebuild the plugin manager's collections,
    // while a real title/version change still re-registers immediately.
    MMMenuRegisterWithPluginManager();
}
