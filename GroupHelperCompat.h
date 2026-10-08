//
//  GroupHelperCompat.h
//  群助手 (group helper) 用到的微信私有类声明。
//
//  注意：这个头文件必须在 WeChatHeaders.h **之后**导入 —— MMServiceCenter /
//  CContactMgr 已经在那边声明过了，而 WeChatHeaders.h 没有 include guard，
//  这里不能重复声明、也不能再 import 一次。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 会话模型：群助手要读 username / 昵称 / 未读数，并合成一个「群助手」入口会话
// （合成走 KVC，字段见 GroupHelperConfig.m）。
@interface MMSessionInfo : NSObject
@property (nonatomic, copy) NSString *m_nsUserName;
@property (nonatomic, copy) NSString *m_nsNickName;
@property (nonatomic, assign) unsigned int m_uUnReadCount;
@end

// 会话管理：会话列表、按用户名取/造会话。
// 每个调用点都会先 respondsToSelector:，老版本微信不会崩。
@interface MMNewSessionMgr : NSObject
- (id)GetSessionInfoList;
- (id)GetSessionByUserName:(NSString *)userName;
- (id)genSessionInfoByUserName:(NSString *)userName;   // 合成入口会话用
- (void)rebuildAndUpdateSessionInfo;
@end

// 群聊信息页：m_chatRoomContact 是当前群，m_tableViewInfo 能取到 table view
// （MMTableViewInfo -getTableView 已在 WeChatHeaders.h 里声明）。
@interface ChatRoomInfoViewController : UIViewController
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)reloadTableData;
@end

// 运行时新增方法的声明（实现由 Logos 的 %new 提供），避免 clang 报 method not found。
@interface ChatRoomInfoViewController (WCZZGroupHelper)
- (void)wczzGroupInstallCommonSwitch;
- (void)wczzGroupCommonChanged:(UISwitch *)sender;
- (UIView *)wczzGroupMakeCommonHeader:(NSString *)userName;
- (UITableView *)wczzGroupFindTableView:(UIView *)root;
@end
