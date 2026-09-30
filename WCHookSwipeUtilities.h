#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CommonMessageCellView;

@interface WCHookSwipeUtilities : NSObject

+ (CGFloat)thresholdForView:(UIView *)view;
+ (BOOL)shouldIgnoreTranslation:(CGPoint)translation;
+ (BOOL)isVelocityEligible:(CGPoint)velocity;
+ (CGFloat)clampedTranslation:(CGFloat)translation threshold:(CGFloat)threshold;
+ (BOOL)shouldTriggerWithTranslation:(CGPoint)translation
                            velocity:(CGPoint)velocity
                           threshold:(CGFloat)threshold;
+ (NSArray<UIView *> *)relatedMessageViewsForCommonView:(CommonMessageCellView *)view;
+ (void)applyTransform:(CGAffineTransform)transform toViews:(NSArray<UIView *> *)views;
+ (void)animateResetForViews:(NSArray<UIView *> *)views animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
