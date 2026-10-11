//
//  GroupHelperConfig.h
//  群助手（MiYou 式）：会话列表里一个「入口会话」+ 插件自己的分组列表页。
//
//  规则：
//    * 开关打开后，**所有群聊默认进入分组**（在会话列表里被收起来）；
//    * 在群聊信息页把某个群设为「常用群」，它就不进分组、留在会话列表；
//    * 分组页右上角「＋」可以把**任意会话**手动加进分组（MiYou 的 RoomList 行为）；
//    * 会话列表里那一项是插件合成的会话（username = wczz_group_helper），
//      未读数 = 分组内所有会话未读之和，点击进入插件自己的列表页。
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

/// NSUserDefaults keys
FOUNDATION_EXPORT NSString * const MMGroupEnabledKey;   // wczz.group.enabled
FOUNDATION_EXPORT NSString * const MMGroupCommonKey;    // wczz.group.common   （常用群 = 不进分组）
FOUNDATION_EXPORT NSString * const MMGroupManualKey;    // wczz.group.manual   （手动加入分组）
FOUNDATION_EXPORT NSString * const MMGroupTitleKey;     // wczz.group.title
FOUNDATION_EXPORT NSString * const MMGroupDebugKey;     // wczz.group.debug

/// 总开关
BOOL MMGroupIsEnabled(void);
void MMGroupSetEnabled(BOOL enabled);

/// 调试日志（设置页开关打开后走 NSLog）
BOOL MMGroupDebugEnabled(void);
void MMGroupSetDebugEnabled(BOOL enabled);
void MMGroupLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// 入口会话
NSString *MMGroupHelperUserName(void);      // 固定值：wczz_group_helper
NSString *MMGroupHelperTitle(void);         // 默认「群助手」
void MMGroupSetHelperTitle(NSString * _Nullable title);
BOOL MMGroupIsHelperSession(NSString * _Nullable userName);

/// 群聊判定
BOOL MMGroupIsGroupUserName(NSString * _Nullable userName);

/// 常用群（不进分组）
NSArray<NSString *> *MMGroupCommonList(void);
void MMGroupSetCommonList(NSArray<NSString *> *list);
BOOL MMGroupIsCommon(NSString * _Nullable userName);
void MMGroupSetCommon(NSString * _Nullable userName, BOOL common);
void MMGroupClearCommonList(void);

/// 手动加入分组的会话
NSArray<NSString *> *MMGroupManualList(void);
void MMGroupSetManualList(NSArray<NSString *> *list);
BOOL MMGroupIsManual(NSString * _Nullable userName);
void MMGroupSetManual(NSString * _Nullable userName, BOOL manual);

/// 会话枚举 / 分组计算
NSArray *MMGroupAllSessions(void);                       // 原始会话列表（绕过会话列表 hook 的过滤）
NSArray *MMGroupAllGroupSessions(void);                  // 只含群聊（常用群选择页用）
NSArray *MMGroupGroupedSessionsFromList(NSArray *allSessions);   // hook 里用这个（不会递归）
NSArray *MMGroupGroupedSessions(void);                   // UI 用

/// 会话列表 hook 用它判断「这次取列表是插件自己要的原始数据，别过滤」
BOOL MMGroupIsBypassingListFilter(void);
void MMGroupSetBypassingListFilter(BOOL bypassing);

/// 合成「群助手」入口会话（未读汇总 + 置顶）
id _Nullable MMGroupMakeHelperSessionFromGrouped(NSArray *grouped);
id _Nullable MMGroupMakeHelperSession(void);

/// 显示名：备注 > 昵称 > username
NSString *MMGroupDisplayName(NSString * _Nullable userName, NSString * _Nullable fallback);
id _Nullable MMGroupValueSafe(id _Nullable object, NSString *key);

/// 会话字段读取（KVC 多 key + ivar 直读兜底，避免某些版本 KVC 取不到）
NSString * _Nullable MMGroupUserNameOfSession(id _Nullable session);
unsigned int MMGroupUnreadOfSession(id _Nullable session);
unsigned int MMGroupSortTimeOfSession(id _Nullable session);

/// 找到主界面控制器（NewMainFrameViewController）
UIViewController * _Nullable MMGroupMainFrameController(void);

/// 诊断用：单个会话的字段探测文本
NSString *MMGroupDescribeSession(id session);

/// 运行时自检
NSString *MMGroupRuntimeStatus(void);

#pragma mark - 会话列表钩子（多候选类名探测安装）

/// 候选类名：不同微信版本会话管理器的叫法不同，逐个探测。
NSArray<NSString *> *MMGroupSessionMgrCandidates(void);
/// 尝试安装 GetSessionInfoList 钩子；返回 YES 表示装上了。
BOOL MMGroupInstallSessionListHook(void);
/// 钩子是否已装 / 装在哪个类上（诊断用）。
BOOL MMGroupSessionListHookInstalled(void);
NSString *MMGroupSessionListHookClassName(void);
/// 让微信重建并刷新会话列表。
void MMGroupForceReloadSessions(void);

#pragma mark - 视图层过滤（微信列表实际读的是主界面的行缓存）

/// 安装视图层过滤钩子（两层都装，自动判断哪一层在驱动列表）：
///   -[NewMainFrameViewController logicGetCountForSection: / logicGetSessionAtIndexPath: / logicGetCellDataAtIndexPath:]
///   -[MainFrameLogicController getSessionCountForSection: / getSessionInfoAtIndexPath: / getCellDataAtIndexPath:]
/// 理由（实测）：只改 GetSessionInfoList 的返回值界面不动；VC 的 logicGet* 也从未被调用过。
BOOL MMGroupInstallViewHooks(void);
BOOL MMGroupViewHooksInstalled(void);
/// 诊断用：入口行 cellData 的字段探测结果
NSString *MMGroupCellDataProbe(void);
/// 诊断用：视图层报告（每层调用次数、判定出的会话列表 section、显示映射）
NSString *MMGroupViewLayerReport(void);
/// Tweak.xm 的 MainFrameCellDataManager 钩子把观察到的调用记进来（诊断用）
void MMGroupNoteCellDataManagerCall(NSString * _Nullable userName, id _Nullable cellData);

/// 一键诊断文本（设置页可复制）：版本、类/方法是否存在、钩子状态、会话统计。
NSString *MMGroupDiagnostics(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
