#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// WeChat 8.0.75 verified headers.

@interface MMContext : NSObject
@property (nonatomic, readonly) id serviceCenter;
+ (instancetype)activeUserContext;
+ (instancetype)currentContext;
+ (instancetype)lastContext;
- (id)getService:(Class)serviceClass;
- (NSString *)userName;
@end

@interface CContactMgr : NSObject
- (id)getSelfContact;
- (id)getContactByName:(NSString *)userName;
@end

// Runtime-only declarations used by the backup sender. The implementation
// still checks every selector so unsupported WeChat builds simply report that
// the file-send API is unavailable.
@interface MMServiceCenter : NSObject
+ (instancetype)defaultCenter;
+ (instancetype)sharedInstance;
- (id)getService:(Class)serviceClass;
@end

@interface CMessageWrap : NSObject
- (instancetype)initWithMsgType:(NSInteger)messageType;
@property (nonatomic, copy) NSString *m_nsFromUsr;
@property (nonatomic, copy) NSString *m_nsToUsr;
@property (nonatomic, copy) NSString *m_nsRealChatUsr;
@property (nonatomic, copy) NSString *m_nsFilePath;
@property (nonatomic, copy) NSString *m_nsFileName;
@property (nonatomic, copy) NSString *m_nsTitle;
@property (nonatomic, copy) NSString *m_nsContent;
@property (nonatomic, assign) NSUInteger m_uiMessageType;
@property (nonatomic, assign) NSUInteger m_uiStatus;
@property (nonatomic, assign) NSUInteger m_uiCreateTime;
@end

@interface CMessageMgr : NSObject
- (void)AddMsg:(NSString *)userName MsgWrap:(CMessageWrap *)message;
- (void)AddMsg:(NSString *)userName MsgWrap:(CMessageWrap *)message NewMsgArriveNotify:(BOOL)notify;
@end

@interface CBaseContact : NSObject
@property (nonatomic, retain) NSString *m_nsUsrName;
@property (nonatomic, retain) NSString *m_nsHeadImgUrl;
@property (nonatomic, retain) NSString *m_nsHeadHDImgUrl;
- (UIImage *)getContactHeadImage;
@end

@interface MMHeadImageView : UIView
- (instancetype)initWithUsrName:(NSString *)userName
                      headImgUrl:(NSString *)headImageURL
                     bAutoUpdate:(BOOL)autoUpdate
                    bRoundCorner:(BOOL)roundCorner;
@end

@interface BaseMessageCellView : UIView
@property (nonatomic, readonly) id viewModel;
- (id)filteredMenuItems:(id)items;
- (id)generateOperationMenu;
- (id)operationMenuItems;
@end

@interface CommonMessageCellView : BaseMessageCellView
@end

@interface EmoticonMessageCellView : CommonMessageCellView
- (id)operationMenuItems;
@end

// MMMenuController: sharedMenuController is the single instance.
// The property holding the current responder cell is `responder`, NOT `targetView`.
@interface MMMenuController : UIViewController
@property (nonatomic, weak) UIResponder *responder;
@property (nonatomic, readonly) NSArray *currentMenuItems;
+ (instancetype)sharedMenuController;
- (void)setMenuItems:(NSArray *)items;
- (void)setMenuVisible:(BOOL)visible animated:(BOOL)animated;
@end

@interface NewSettingViewController : UIViewController
- (void)viewDidLoad;
- (void)viewDidAppear:(BOOL)animated;
@end

// WCPluginsMgr may or may not be present; checked at runtime.
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
@end

// WeChat native table view managers (used by WCHook settings UI).
@interface MMTableViewInfo : NSObject
- (UITableView *)getTableView;
- (void)addSection:(id)section;
- (void)insertSection:(id)section At:(NSInteger)index;
@end

@interface WCTableViewManager : NSObject
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style;
- (void)addTableViewToSuperView:(UIView *)view;
- (void)clearAllSection;
- (void)addSection:(id)section;
@property (nonatomic, strong) UITableView *tableView;
@end

@interface WCTableViewSectionManager : NSObject
+ (instancetype)sectionInfoHeader:(NSString *)header Footer:(NSString *)footer;
+ (instancetype)defaultSection;
- (void)addCell:(id)cell;
@end

@interface WCTableViewCellManager : NSObject
+ (instancetype)switchCellForSel:(SEL)sel target:(id)target title:(NSString *)title on:(BOOL)on;
+ (instancetype)switchCellForSel:(SEL)sel
                           target:(id)target
                        leftImage:(UIImage *)leftImage
                            title:(NSString *)title
                             desc:(NSString *)desc
                               on:(BOOL)on;
@end

@interface WCTableViewNormalCellManager : NSObject
+ (instancetype)normalCellForSel:(SEL)sel
                           target:(id)target
                            title:(NSString *)title
                       rightValue:(NSString *)value
                    accessoryType:(UITableViewCellAccessoryType)accessoryType;
+ (instancetype)normalCellForSel:(SEL)sel
                           target:(id)target
                            title:(NSString *)title
                    accessoryType:(UITableViewCellAccessoryType)accessoryType;
- (id)cellConfig;
@end

@interface WCTableViewCellNormalConfig : NSObject
- (id)rightConfig;
@end

@interface WCTableViewCellRightConfig : NSObject
- (void)setDetail:(NSString *)detail;
@end

@interface MinimizeViewController : UIViewController
@end
