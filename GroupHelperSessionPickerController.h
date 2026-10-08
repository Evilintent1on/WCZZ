//
//  GroupHelperSessionPickerController.h
//  选择页（两种用途）：
//    常用群   —— 只列群聊，勾选 = 不进分组（群聊信息页开关的批量版）
//    手动加入 —— 列全部会话，勾选 = 手动加进分组（分组页右上角「＋」）
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, GroupHelperPickerMode) {
    GroupHelperPickerModeCommon = 0,   // 常用群（不折叠）
    GroupHelperPickerModeManual        // 手动加入分组
};

@interface GroupHelperSessionPickerController : UITableViewController

- (instancetype)initWithMode:(GroupHelperPickerMode)mode
                  completion:(void (^)(NSUInteger count))completion;

@end
