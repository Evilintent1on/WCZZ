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

// 会话模型：群助手要读 username / 昵称 / 未读数。
@interface MMSessionInfo : NSObject
@property (nonatomic, copy) NSString *m_nsUserName;
@property (nonatomic, copy) NSString *m_nsNickName;
@property (nonatomic, assign) unsigned int m_uUnReadCount;
@property (nonatomic, assign) BOOL m_isFolding;
@end

// 会话管理：8.0.75/8.0.79 原生折叠 API 都在这里。
// 每个调用点都会先 respondsToSelector:，所以老版本微信不会崩。
@interface MMNewSessionMgr : NSObject
- (id)GetSessionInfoList;
- (BOOL)shouldFoldSession:(id)session;
- (void)foldSessionByNames:(NSArray *)names;
- (void)unfoldSessionByName:(NSString *)name;
- (void)unfoldAllSessions;
- (void)rebuildAndUpdateSessionInfo;
@end

// 会话 cell 的左滑菜单：菜单项数组由父类设置。
@interface MMBaseMultiMenuTableViewCell : UITableViewCell
- (void)setMenuItemsWithNoDeleteBtn:(NSArray *)items;
- (void)setMenuItemsWithDefaultDeleteBtn:(NSArray *)items;
@end

@interface NewMainFrameCell : MMBaseMultiMenuTableViewCell
- (void)updateCellContent:(id)content withContact:(id)contact;
@end

// 运行时新增方法的声明（实现由 Logos 的 %new 提供），避免 clang 报 method not found。
@interface MMBaseMultiMenuTableViewCell (WCZZGroupHelper)
- (void)wczzGroupToggle:(id)sender;
@end
