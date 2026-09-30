#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// Shared palette so the settings screen and every dialog stay in sync.
UIColor *MMAccentColor(void);
UIColor *MMSoftAccentColor(void);
UIColor *MMGroupedBackground(void);

#ifdef __cplusplus
}
#endif

typedef NS_ENUM(NSInteger, MMAlertActionStyle) {
    /// Filled accent button, used for the affirmative action.
    MMAlertActionStylePrimary = 0,
    /// Tinted accent button for secondary but non-destructive choices.
    MMAlertActionStyleDefault,
    /// Tinted red button.
    MMAlertActionStyleDestructive,
    /// Neutral grey button; also enables tap-outside-to-dismiss.
    MMAlertActionStyleCancel,
};

@interface MMAlertAction : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, assign, readonly) MMAlertActionStyle style;
@property (nonatomic, copy, readonly, nullable) void (^handler)(void);

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(MMAlertActionStyle)style
                        handler:(void (^ _Nullable)(void))handler;
@end

/// A rounded, theme-aware replacement for UIAlertController.  Buttons stack
/// vertically so Chinese labels never get truncated, and an optional text
/// field keeps the add/rename flows inside the same visual language.
@interface MMAlertController : UIViewController

+ (instancetype)alertWithSymbol:(nullable NSString *)symbolName
                          title:(NSString *)title
                        message:(nullable NSString *)message;

- (void)addAction:(MMAlertAction *)action;

/// Adds a single-line input. `hint` renders under the field in a smaller font.
- (void)addTextFieldWithPlaceholder:(nullable NSString *)placeholder
                               text:(nullable NSString *)text
                               hint:(nullable NSString *)hint;

/// Trimmed contents of the text field, or nil when there is no field.
@property (nonatomic, copy, readonly, nullable) NSString *textValue;

- (void)presentFrom:(UIViewController *)host;

/// Convenience for the very common "one message, one 确定 button" case.
+ (void)showInfoFrom:(UIViewController *)host
              symbol:(nullable NSString *)symbolName
               title:(NSString *)title
             message:(nullable NSString *)message;

@end

NS_ASSUME_NONNULL_END
