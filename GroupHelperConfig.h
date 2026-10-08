//
//  GroupHelperConfig.h
//  群助手（会话分组）配置 + 落地逻辑。
//
//  设计：和 MessageMenuConfig 一样走 C 函数接口，状态存在 NSUserDefaults。
//  名单(RoomList) → 微信原生折叠(foldSessionByNames:)；同时反向读取微信自己折叠的
//  会话（shouldFoldSession:），保证两边不打架。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults keys
FOUNDATION_EXPORT NSString * const MMGroupEnabledKey;   // wczz.group.enabled
FOUNDATION_EXPORT NSString * const MMGroupListKey;      // wczz.group.list
FOUNDATION_EXPORT NSString * const MMGroupFoldedKey;    // wczz.group.foldedByUs

/// 开关
BOOL MMGroupIsEnabled(void);
void MMGroupSetEnabled(BOOL enabled);

/// 名单（纯状态操作，不会触发落地；落地请显式调用 MMGroupApplyFold）
NSArray<NSString *> *MMGroupUserNameList(void);
void MMGroupSetUserNameList(NSArray<NSString *> *list);
BOOL MMGroupContainsUserName(NSString * _Nullable userName);
void MMGroupAddUserName(NSString * _Nullable userName);
void MMGroupRemoveUserName(NSString * _Nullable userName);
void MMGroupClearUserNames(void);

/// 会话枚举（供选择页使用）：-[MMNewSessionMgr GetSessionInfoList]
NSArray *MMGroupAllSessions(void);

/// 反向同步：把微信自己折叠（shouldFoldSession:）的会话补进名单。
/// 必须传入调用方已有的会话数组，否则在 GetSessionInfoList 的 hook 里会递归。
void MMGroupSyncFromNativeFold(NSArray * _Nullable sessions);

/// 落地：diff 之后调用 foldSessionByNames: / unfoldSessionByName:，并刷新会话列表。
/// 只会展开「我们自己折过」的会话（MMGroupFoldedKey），不会动用户手动折叠的。
void MMGroupApplyFold(void);

/// 显示名：备注 > 昵称 > username
NSString *MMGroupDisplayName(NSString * _Nullable userName, NSString * _Nullable fallback);

/// 带异常保护的 KVC 取值（选择页展示用）。
id _Nullable MMGroupValueSafe(id _Nullable object, NSString *key);

NS_ASSUME_NONNULL_END
