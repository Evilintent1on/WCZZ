//
//  HBGroupService.h
//  微信私有接口桥
//
//  这一层是整套代码里唯一直接调微信私有类的地方。
//  微信每次大版本更新，私有类名/选择器都可能变，所以：
//   - 所有类名走候选列表 + NSClassFromString，取到哪个用哪个；
//   - 所有调用包在 @try 里，取不到就静默跳过、绝不崩；
//   - 换微信版本通常只要改这一个文件。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface HBGroupService : NSObject

+ (instancetype)shared;

/// 当前登录账号
- (nullable NSString *)currentAccount;

/// 全部会话（数组里是微信的会话对象）
- (NSArray *)allSessions;

/// 让微信首页重建会话列表
- (void)rebuildMainSessions;

/// 重新统计未读
- (void)recountUnread;

#pragma mark - 会话操作

- (BOOL)markRead:(NSString *)userName;
- (BOOL)deleteSession:(NSString *)userName;
- (BOOL)hideSession:(NSString *)userName;
- (BOOL)setHideSession:(NSString *)userName hidden:(BOOL)hidden;
- (BOOL)changeUnreadCount:(NSString *)userName to:(NSUInteger)count;

#pragma mark - 跳转 / 选择器

- (void)openSession:(id)session fromController:(UIViewController *)controller;

/// 弹出「选择会话」界面（微信自带的 SessionSelectController）
- (void)presentSessionPickerForChatMode:(BOOL)chatMode
                                   from:(UIViewController *)controller
                             completion:(void (^)(NSArray<NSString *> *selected))completion;

/// 关闭首页会话 cell 的长按菜单
- (void)closeSessionMenus;

/// 选群界面关闭时回收选中结果（供 hook 调用）
+ (void)finishPicker:(id)picker;

/// 轻提示
- (void)toast:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
