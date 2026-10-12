//
//  HBGroupConfig.m
//  群聊分组 / 好友分组 —— 配置中心实现
//

#import "HBGroupConfig.h"

NSString *const kHBGroupChangedNotification = @"HBGroupChangedNotification";

static NSString *const kPrefDomain = @"com.hb.wechat.groupchat";
static NSString *const kKeyEnabled = @"hb.chatgroup.enabled";
static NSString *const kKeyChatMode = @"hb.chatgroup.chatmode";
static NSString *const kKeyFriendMode = @"hb.chatgroup.friendmode";
static NSString *const kKeyChatGroups = @"hb.chatgroup.groups.chat";
static NSString *const kKeyFriendGroups = @"hb.chatgroup.groups.friend";
static NSString *const kKeyPinned = @"hb.chatgroup.pinned";
static NSString *const kKeyBelowNative = @"hb.chatgroup.belowNativePinned";
static NSString *const kKeyHideSearchBar = @"hb.chatgroup.hideSearchBar";
static NSString *const kKeyHideSummarySender = @"hb.chatgroup.hideSummarySender";
static NSString *const kKeySummaryFormat = @"hb.chatgroup.summaryFormat";
static NSString *const kKeyRowHeight = @"hb.chatgroup.homeRowHeight";
static NSString *const kKeyExclusions = @"hb.chatgroup.exclusions";

@implementation HBGroupItem

- (instancetype)init {
    if ((self = [super init])) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"";
        _members = [NSMutableArray array];
        _order = 0;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    HBGroupItem *item = [[HBGroupItem allocWithZone:zone] init];
    item.identifier = self.identifier;
    item.name = self.name;
    item.members = [self.members mutableCopy];
    item.avatarPath = self.avatarPath;
    item.order = self.order;
    return item;
}

+ (instancetype)itemWithDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    HBGroupItem *item = [[HBGroupItem alloc] init];
    NSString *ident = dict[@"id"];
    if (ident.length) item.identifier = ident;
    NSString *name = dict[@"name"];
    if (name.length) item.name = name;
    NSArray *members = dict[@"members"];
    if ([members isKindOfClass:[NSArray class]]) item.members = [members mutableCopy];
    NSString *avatar = dict[@"avatar"];
    if (avatar.length) item.avatarPath = avatar;
    item.order = [dict[@"order"] integerValue];
    return item;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.identifier ?: @"";
    dict[@"name"] = self.name ?: @"";
    dict[@"members"] = self.members ?: @[];
    if (self.avatarPath) dict[@"avatar"] = self.avatarPath;
    dict[@"order"] = @(self.order);
    return dict;
}

@end


@implementation HBGroupConfig {
    NSDictionary *_cache;
}

+ (instancetype)shared {
    static HBGroupConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HBGroupConfig alloc] init];
        [instance reload];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _summaryFormat = @"%@: %@";
        _homeRowHeight = 64.0;
        _chatGroups = [NSMutableArray array];
        _friendGroups = [NSMutableArray array];
        _exclusions = [NSMutableArray array];
    }
    return self;
}

#pragma mark - 落盘

- (void)reload {
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:kPrefDomain];
    if (![prefs isKindOfClass:[NSDictionary class]]) prefs = @{};
    _cache = prefs;

    _enabled = [self boolForKey:kKeyEnabled defaultValue:YES];
    _chatGroupEnabled = [self boolForKey:kKeyChatMode defaultValue:YES];
    _friendGroupEnabled = [self boolForKey:kKeyFriendMode defaultValue:NO];
    _pinned = [self boolForKey:kKeyPinned defaultValue:YES];
    _belowNativePinned = [self boolForKey:kKeyBelowNative defaultValue:NO];
    _hideSearchBar = [self boolForKey:kKeyHideSearchBar defaultValue:NO];
    _hideSummarySender = [self boolForKey:kKeyHideSummarySender defaultValue:NO];

    NSString *fmt = prefs[kKeySummaryFormat];
    if ([fmt isKindOfClass:[NSString class]] && fmt.length) _summaryFormat = fmt;

    id height = prefs[kKeyRowHeight];
    if ([height respondsToSelector:@selector(doubleValue)]) _homeRowHeight = [height doubleValue];

    _chatGroups = [[self itemArrayForKey:kKeyChatGroups] mutableCopy] ?: [NSMutableArray array];
    _friendGroups = [[self itemArrayForKey:kKeyFriendGroups] mutableCopy] ?: [NSMutableArray array];

    NSArray *exclusions = prefs[kKeyExclusions];
    if ([exclusions isKindOfClass:[NSArray class]]) _exclusions = [exclusions mutableCopy];
    else _exclusions = [NSMutableArray array];
}

- (NSArray<HBGroupItem *> *)itemArrayForKey:(NSString *)key {
    NSArray *raw = _cache[key];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:raw.count];
    for (NSDictionary *dict in raw) {
        HBGroupItem *item = [HBGroupItem itemWithDictionary:dict];
        if (item) [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(HBGroupItem *a, HBGroupItem *b) {
        if (a.order == b.order) return NSOrderedSame;
        return a.order < b.order ? NSOrderedAscending : NSOrderedDescending;
    }];
    return items;
}

- (void)synchronize {
    NSMutableDictionary *prefs = [_cache mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[kKeyEnabled] = @(_enabled);
    prefs[kKeyChatMode] = @(_chatGroupEnabled);
    prefs[kKeyFriendMode] = @(_friendGroupEnabled);
    prefs[kKeyPinned] = @(_pinned);
    prefs[kKeyBelowNative] = @(_belowNativePinned);
    prefs[kKeyHideSearchBar] = @(_hideSearchBar);
    prefs[kKeyHideSummarySender] = @(_hideSummarySender);
    prefs[kKeySummaryFormat] = _summaryFormat ?: @"%@: %@";
    prefs[kKeyRowHeight] = @(_homeRowHeight);
    prefs[kKeyExclusions] = _exclusions ?: @[];

    NSMutableArray *chat = [NSMutableArray arrayWithCapacity:_chatGroups.count];
    for (HBGroupItem *item in _chatGroups) [chat addObject:[item dictionaryValue]];
    prefs[kKeyChatGroups] = chat;

    NSMutableArray *friends = [NSMutableArray arrayWithCapacity:_friendGroups.count];
    for (HBGroupItem *item in _friendGroups) [friends addObject:[item dictionaryValue]];
    prefs[kKeyFriendGroups] = friends;

    [[NSUserDefaults standardUserDefaults] setPersistentDomain:prefs forName:kPrefDomain];
    [[NSUserDefaults standardUserDefaults] synchronize];

    _cache = prefs;
    [[NSNotificationCenter defaultCenter] postNotificationName:kHBGroupChangedNotification object:nil];
}

#pragma mark - KV

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def {
    id value = _cache[key];
    if (value == nil) return def;
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return def;
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    NSMutableDictionary *prefs = [_cache mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[key] = @(value);
    _cache = prefs;
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:prefs forName:kPrefDomain];
}

#pragma mark - 分组读写

- (NSArray<HBGroupItem *> *)groupsForChatMode:(BOOL)chatMode {
    return chatMode ? _chatGroups : _friendGroups;
}

- (void)setGroups:(NSArray<HBGroupItem *> *)groups chatMode:(BOOL)chatMode {
    if (chatMode) _chatGroups = [groups mutableCopy] ?: [NSMutableArray array];
    else _friendGroups = [groups mutableCopy] ?: [NSMutableArray array];
}

- (HBGroupItem *)groupWithIdentifier:(NSString *)groupID chatMode:(BOOL)chatMode {
    if (!groupID.length) return nil;
    for (HBGroupItem *item in [self groupsForChatMode:chatMode]) {
        if ([item.identifier isEqualToString:groupID]) return item;
    }
    return nil;
}

- (void)addMembers:(NSArray<NSString *> *)members toGroup:(NSString *)groupID chatMode:(BOOL)chatMode {
    HBGroupItem *item = [self groupWithIdentifier:groupID chatMode:chatMode];
    if (!item) return;
    for (NSString *member in members) {
        if (!member.length) continue;
        if (![item.members containsObject:member]) [item.members addObject:member];
    }
    [self synchronize];
}

- (void)removeMember:(NSString *)member fromGroup:(NSString *)groupID chatMode:(BOOL)chatMode {
    HBGroupItem *item = [self groupWithIdentifier:groupID chatMode:chatMode];
    if (!item || !member.length) return;
    [item.members removeObject:member];
    [self synchronize];
}

@end
