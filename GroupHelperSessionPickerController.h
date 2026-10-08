//
//  GroupHelperSessionPickerController.h
//  群助手名单选择页：勾选式会话多选。
//

#import <UIKit/UIKit.h>

@interface GroupHelperSessionPickerController : UITableViewController

/// done 回调里传入最新的名单数量，用来刷新设置页。
- (instancetype)initWithCompletion:(void (^)(NSUInteger count))completion;

@end
