//
//  GroupHelperConfig.h
//  群助手 —— 完全按微信助手 (MiYou) 3.9-5 的 GroupTool 语义复刻。
//
//  MiYou 模型（pseudo/GroupTool.h 逆向所得）：
//    * RoomList              白名单：**手动加进去的会话**才会被收进群助手
//    * isOpenRoomEnable      功能总开关
//    * isOpenRoomHelper      是否显示「群助手」入口行
//    * isHelperTop / roomIdx 入口行的位置（置顶 / 指定下标）
//    * helperIncoType        入口未读样式（0 数字 / 1 红点）
//    * roomName              入口名称（默认「群助手」）
//    * roomReadCount         入口未读 = 组内未读之和
//    * inRoomList            （运行时）点进入口后，同一个会话列表只显示组内会话，标题变 roomName
//    * createSessionWithUserName:nickName:showRedDot:readAsRedDot:  造入口会话
//
//  会话列表里的入口行被点击时**不跳页面**，而是置 inRoomList，把会话列表就地切成组内视图。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults keys
FOUNDATION_EXPORT NSString * const MMGroupEnabledKey;    // wczz.group.enabled     isOpenRoomEnable
FOUNDATION_EXPORT NSString * const MMGroupShowHelperKey; // wczz.group.showHelper  isOpenRoomHelper
FOUNDATION_EXPORT NSString * const MMGroupHelperTopKey;  // wczz.group.helperTop   isHelperTop
FOUNDATION_EXPORT NSString * const MMGroupHelperIdxKey;  // wczz.group.helperIdx   roomIdx
FOUNDATION_EXPORT NSString * const MMGroupIncoTypeKey;   // wczz.group.incoType    helperIncoType
FOUNDATION_EXPORT NSString * const MMGroupRoomListKey;   // wczz.group.roomList    RoomList（白名单）
FOUNDATION_EXPORT NSString * const MMGroupTitleKey;      // wczz.group.title       roomName
FOUNDATION_EXPORT NSString * const MMGroupDebugKey;      // wczz.group.debug

#pragma mark - 开关（对应 GroupTool 的 isOpen*）

BOOL MMGroupIsEnabled(void);                 // isOpenRoomEnable
void MMGroupSetEnabled(BOOL enabled);
BOOL MMGroupShowHelper(void);                // isOpenRoomHelper（默认 YES）
void MMGroupSetShowHelper(BOOL show);
BOOL MMGroupHelperTop(void);                 // isHelperTop
void MMGroupSetHelperTop(BOOL top);
NSInteger MMGroupHelperIndex(void);          // roomIdx
void MMGroupSetHelperIndex(NSInteger index);
NSInteger MMGroupHelperIncoType(void);       // helperIncoType：0=数字 1=红点
void MMGroupSetHelperIncoType(NSInteger type);

/// 调试日志
BOOL MMGroupDebugEnabled(void);
void MMGroupSetDebugEnabled(BOOL enabled);
void MMGroupLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#pragma mark - RoomList（白名单）

NSString *MMGroupAccountName(void);          // 当前登录账号（RoomList 按账号分存）
NSArray<NSString *> *MMGroupRoomList(void);
void MMGroupSetRoomList(NSArray<NSString *> *list);
BOOL MMGroupIsInRoomList(NSString * _Nullable userName);
void MMGroupSetInRoomList(NSString * _Nullable userName, BOOL inList);
void MMGroupClearRoomList(void);

#pragma mark - 入口会话（createSessionWithUserName:nickName:showRedDot:readAsRedDot:）

NSString *MMGroupHelperUserName(void);       // 固定：wczz_group_helper
NSString *MMGroupHelperTitle(void);          // roomName，默认「群助手」
void MMGroupSetHelperTitle(NSString * _Nullable title);
BOOL MMGroupIsHelperSession(NSString * _Nullable userName);
/// 组内未读之和（roomReadCount）
unsigned int MMGroupRoomReadCount(void);
/// 造入口会话：nickName = roomName，未读 = roomReadCount，样式按 helperIncoType
id _Nullable MMGroupCreateHelperSession(void);

/// inRoomList：点入口后置 YES，同一个会话列表只显示组内会话
BOOL MMGroupIsInsideHelper(void);
void MMGroupSetInsideHelper(BOOL inside);

/// 会话枚举
NSArray *MMGroupAllSessions(void);           // 原始列表（绕过钩子过滤）
NSArray *MMGroupAllGroupSessions(void);                          // 只含群聊
NSArray *MMGroupGroupedSessionsFromList(NSArray *allSessions);   // 组内会话（RoomList 命中的）
BOOL MMGroupIsBypassingListFilter(void);
void MMGroupSetBypassingListFilter(BOOL bypassing);

#pragma mark - 会话 / 界面辅助

NSString * _Nullable MMGroupUserNameOfSession(id _Nullable session);
unsigned int MMGroupUnreadOfSession(id _Nullable session);
unsigned int MMGroupSortTimeOfSession(id _Nullable session);
NSString *MMGroupDisplayName(NSString * _Nullable userName, NSString * _Nullable fallback);
id _Nullable MMGroupValueSafe(id _Nullable object, NSString *key);
UIViewController * _Nullable MMGroupMainFrameController(void);
NSString *MMGroupDescribeSession(id session);

#pragma mark - 钩子安装

NSArray<NSString *> *MMGroupSessionMgrCandidates(void);
BOOL MMGroupInstallSessionListHook(void);
BOOL MMGroupSessionListHookInstalled(void);
NSString *MMGroupSessionListHookClassName(void);
/// 视图层过滤（微信实际读的一层）：
///   -[NewMainFrameViewController logicGetCountForSection:/logicGetSessionAtIndexPath:/logicGetCellDataAtIndexPath:]
///   -[MainFrameLogicController getSessionCountForSection:/getSessionInfoAtIndexPath:/getCellDataAtIndexPath:]
BOOL MMGroupInstallViewHooks(void);
BOOL MMGroupViewHooksInstalled(void);
/// 让会话列表重算并刷新（不触发微信重建，安全）
void MMGroupForceReloadSessions(void);

#pragma mark - 诊断

NSString *MMGroupCellDataProbe(void);
NSString *MMGroupViewLayerReport(void);
void MMGroupNoteCellDataManagerCall(NSString * _Nullable userName, id _Nullable cellData);
NSString *MMGroupRuntimeStatus(void);
NSString *MMGroupDiagnostics(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
