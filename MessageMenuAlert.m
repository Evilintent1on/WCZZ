#import "MessageMenuAlert.h"

#import <QuartzCore/QuartzCore.h>

UIColor *MMAccentColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:1.0 green:0.42 blue:0.65 alpha:1.0]
                : [UIColor colorWithRed:0.82 green:0.16 blue:0.42 alpha:1.0];
        }];
    }
    return [UIColor colorWithRed:0.82 green:0.16 blue:0.42 alpha:1.0];
}

UIColor *MMSoftAccentColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:0.30 green:0.12 blue:0.20 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.94 blue:0.97 alpha:1.0];
        }];
    }
    return [UIColor colorWithRed:1.0 green:0.94 blue:0.97 alpha:1.0];
}

UIColor *MMGroupedBackground(void) {
    if (@available(iOS 13.0, *)) return [UIColor systemGroupedBackgroundColor];
    return [UIColor colorWithWhite:0.98 alpha:1.0];
}

@implementation MMAlertAction

+ (instancetype)actionWithTitle:(NSString *)title
                          style:(MMAlertActionStyle)style
                        handler:(void (^)(void))handler {
    MMAlertAction *action = [[MMAlertAction alloc] init];
    if (action) {
        action->_title = [title copy];
        action->_style = style;
        action->_handler = [handler copy];
    }
    return action;
}

@end

@interface MMAlertController () <UITextFieldDelegate, UIViewControllerTransitioningDelegate>
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, copy) NSString *alertTitle;
@property (nonatomic, copy) NSString *alertMessage;
@property (nonatomic, strong) NSMutableArray<MMAlertAction *> *actions;
@property (nonatomic, strong) UIView *dimmingView;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, copy) NSString *fieldPlaceholder;
@property (nonatomic, copy) NSString *fieldText;
@property (nonatomic, copy) NSString *fieldHint;
@property (nonatomic, assign) BOOL wantsTextField;
@property (nonatomic, assign) BOOL allowsBackdropDismiss;
@property (nonatomic, strong) NSLayoutConstraint *cardCenterConstraint;
@property (nonatomic, strong) NSLayoutConstraint *cardBottomConstraint;
@property (nonatomic, assign) BOOL isDismissing;
@end

// A single animator owns both directions of the transition.  The previous
// version combined `crossDissolve` with a second scale animation started in
// `viewDidAppear`, which read as the dialog appearing twice.
@interface MMAlertTransition : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic, assign) BOOL presenting;
@end

@implementation MMAlertTransition

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    (void)context;
    return self.presenting ? 0.30 : 0.20;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *from = [context viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    MMAlertController *alert = (MMAlertController *)(self.presenting ? to : from);
    if (![alert isKindOfClass:[MMAlertController class]]) {
        [context completeTransition:!context.transitionWasCancelled];
        return;
    }

    if (self.presenting) {
        UIView *container = [context containerView];
        alert.view.frame = [context finalFrameForViewController:alert];
        [container addSubview:alert.view];
        [alert.view layoutIfNeeded];

        alert.dimmingView.alpha = 0.0;
        alert.card.alpha = 0.0;
        alert.card.transform = CGAffineTransformMakeScale(0.94, 0.94);
        [UIView animateWithDuration:[self transitionDuration:context]
                              delay:0.0
             usingSpringWithDamping:0.90
              initialSpringVelocity:0.0
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            alert.dimmingView.alpha = 1.0;
            alert.card.alpha = 1.0;
            alert.card.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            (void)finished;
            [context completeTransition:!context.transitionWasCancelled];
        }];
        return;
    }

    [UIView animateWithDuration:[self transitionDuration:context]
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        alert.dimmingView.alpha = 0.0;
        alert.card.alpha = 0.0;
        alert.card.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        (void)finished;
        if (!context.transitionWasCancelled) [alert.view removeFromSuperview];
        [context completeTransition:!context.transitionWasCancelled];
    }];
}

@end

@implementation MMAlertController

+ (instancetype)alertWithSymbol:(NSString *)symbolName
                          title:(NSString *)title
                        message:(NSString *)message {
    MMAlertController *alert = [[MMAlertController alloc] init];
    alert.symbolName = symbolName;
    alert.alertTitle = title;
    alert.alertMessage = message;
    alert.actions = [NSMutableArray array];
    alert.modalPresentationStyle = UIModalPresentationCustom;
    alert.transitioningDelegate = alert;
    return alert;
}

- (id<UIViewControllerAnimatedTransitioning>)
        animationControllerForPresentedController:(UIViewController *)presented
                             presentingController:(UIViewController *)presenting
                                 sourceController:(UIViewController *)source {
    (void)presented; (void)presenting; (void)source;
    MMAlertTransition *transition = [[MMAlertTransition alloc] init];
    transition.presenting = YES;
    return transition;
}

- (id<UIViewControllerAnimatedTransitioning>)
        animationControllerForDismissedController:(UIViewController *)dismissed {
    (void)dismissed;
    return [[MMAlertTransition alloc] init];
}

- (void)addAction:(MMAlertAction *)action {
    if (!action) return;
    [self.actions addObject:action];
    if (action.style == MMAlertActionStyleCancel) self.allowsBackdropDismiss = YES;
}

- (void)addTextFieldWithPlaceholder:(NSString *)placeholder
                               text:(NSString *)text
                               hint:(NSString *)hint {
    self.wantsTextField = YES;
    self.fieldPlaceholder = placeholder;
    self.fieldText = text;
    self.fieldHint = hint;
}

- (NSString *)textValue {
    if (!self.textField) return nil;
    return [self.textField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)presentFrom:(UIViewController *)host {
    UIViewController *presenter = host;
    while (presenter.presentedViewController) {
        presenter = presenter.presentedViewController;
    }
    [presenter presentViewController:self animated:YES completion:nil];
}

+ (void)showInfoFrom:(UIViewController *)host
              symbol:(NSString *)symbolName
               title:(NSString *)title
             message:(NSString *)message {
    MMAlertController *alert = [self alertWithSymbol:symbolName title:title message:message];
    [alert addAction:[MMAlertAction actionWithTitle:@"确定"
                                              style:MMAlertActionStylePrimary
                                            handler:nil]];
    [alert presentFrom:host];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    _dimmingView = [[UIView alloc] init];
    _dimmingView.translatesAutoresizingMaskIntoConstraints = NO;
    _dimmingView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.34];
    [self.view addSubview:_dimmingView];

    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_backdropTapped)];
    [_dimmingView addGestureRecognizer:tap];

    [self _buildCard];
    [self _installConstraints];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_keyboardWillChange:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // The card animation is owned by MMAlertTransition; starting a second one
    // here is what made the dialog look like it appeared twice.
    [self.textField becomeFirstResponder];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!self.viewIfLoaded.window) return;
    self.card.layer.borderColor = [MMAccentColor() colorWithAlphaComponent:0.16].CGColor;
}

#pragma mark - Card construction

- (void)_buildCard {
    _card = [[UIView alloc] init];
    _card.translatesAutoresizingMaskIntoConstraints = NO;
    _card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    _card.layer.cornerRadius = 8.0;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.borderWidth = 1.0;
    _card.layer.borderColor = [MMAccentColor() colorWithAlphaComponent:0.16].CGColor;
    _card.layer.shadowColor = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.16;
    _card.layer.shadowRadius = 24.0;
    _card.layer.shadowOffset = CGSizeMake(0, 10);
    [self.view addSubview:_card];

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _scrollView.layer.cornerRadius = 8.0;
    _scrollView.clipsToBounds = YES;
    [_card addSubview:_scrollView];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.spacing = 10.0;
    [_scrollView addSubview:_contentStack];

    if (self.symbolName.length) [self.contentStack addArrangedSubview:[self _iconBadge]];

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = self.alertTitle;
    titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.numberOfLines = 2;
    [self.contentStack addArrangedSubview:titleLabel];

    if (self.alertMessage.length) {
        UILabel *messageLabel = [[UILabel alloc] init];
        messageLabel.font = [UIFont systemFontOfSize:14.5];
        messageLabel.textColor = [UIColor secondaryLabelColor];
        messageLabel.textAlignment = NSTextAlignmentCenter;
        messageLabel.numberOfLines = 0;

        NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
        paragraph.alignment = NSTextAlignmentCenter;
        paragraph.lineSpacing = 3.0;
        messageLabel.attributedText =
            [[NSAttributedString alloc] initWithString:self.alertMessage
                                            attributes:@{NSParagraphStyleAttributeName: paragraph}];
        [self.contentStack addArrangedSubview:messageLabel];
        [self.contentStack setCustomSpacing:6.0 afterView:titleLabel];
    }

    if (self.wantsTextField) [self _appendTextField];
    [self _appendButtons];
}

- (UIView *)_iconBadge {
    UIView *wrapper = [[UIView alloc] init];
    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = [MMAccentColor() colorWithAlphaComponent:0.13];
    badge.layer.cornerRadius = 25.0;
    [wrapper addSubview:badge];

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:23.0
                                                        weight:UIImageSymbolWeightSemibold];
    UIImageView *icon = [[UIImageView alloc] init];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = MMAccentColor();
    icon.image = [UIImage systemImageNamed:self.symbolName withConfiguration:configuration]
        ?: [UIImage systemImageNamed:@"info.circle" withConfiguration:configuration];
    [badge addSubview:icon];

    [NSLayoutConstraint activateConstraints:@[
        [badge.centerXAnchor constraintEqualToAnchor:wrapper.centerXAnchor],
        [badge.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [badge.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-4.0],
        [badge.widthAnchor constraintEqualToConstant:50.0],
        [badge.heightAnchor constraintEqualToConstant:50.0],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:26.0],
        [icon.heightAnchor constraintEqualToConstant:26.0],
    ]];
    return wrapper;
}

- (void)_appendTextField {
    UIView *field = [[UIView alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.backgroundColor = MMSoftAccentColor();
    field.layer.cornerRadius = 8.0;
    field.layer.cornerCurve = kCACornerCurveContinuous;

    _textField = [[UITextField alloc] init];
    _textField.translatesAutoresizingMaskIntoConstraints = NO;
    _textField.placeholder = self.fieldPlaceholder;
    _textField.text = self.fieldText;
    _textField.font = [UIFont systemFontOfSize:16.0];
    _textField.textColor = [UIColor labelColor];
    _textField.tintColor = MMAccentColor();
    _textField.delegate = self;
    _textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _textField.autocorrectionType = UITextAutocorrectionTypeNo;
    _textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textField.returnKeyType = UIReturnKeyDone;
    [field addSubview:_textField];

    [NSLayoutConstraint activateConstraints:@[
        [field.heightAnchor constraintEqualToConstant:44.0],
        [_textField.leadingAnchor constraintEqualToAnchor:field.leadingAnchor constant:13.0],
        [_textField.trailingAnchor constraintEqualToAnchor:field.trailingAnchor constant:-10.0],
        [_textField.centerYAnchor constraintEqualToAnchor:field.centerYAnchor],
    ]];
    [self.contentStack addArrangedSubview:field];
    [self.contentStack setCustomSpacing:14.0 afterView:field];

    if (self.fieldHint.length) {
        UILabel *hint = [[UILabel alloc] init];
        hint.text = self.fieldHint;
        hint.font = [UIFont systemFontOfSize:12.5];
        hint.textColor = [UIColor tertiaryLabelColor];
        hint.textAlignment = NSTextAlignmentCenter;
        hint.numberOfLines = 0;
        [self.contentStack addArrangedSubview:hint];
        [self.contentStack setCustomSpacing:4.0 afterView:field];
        [self.contentStack setCustomSpacing:14.0 afterView:hint];
    }
}

- (void)_appendButtons {
    UIStackView *buttons = [[UIStackView alloc] init];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.alignment = UIStackViewAlignmentFill;
    buttons.spacing = 8.0;

    [self.actions enumerateObjectsUsingBlock:^(MMAlertAction *action, NSUInteger index, BOOL *stop) {
        (void)stop;
        [buttons addArrangedSubview:[self _buttonForAction:action index:index]];
    }];

    UIView *spacer = self.contentStack.arrangedSubviews.lastObject;
    if (spacer) [self.contentStack setCustomSpacing:18.0 afterView:spacer];
    [self.contentStack addArrangedSubview:buttons];
}

- (UIButton *)_buttonForAction:(MMAlertAction *)action index:(NSUInteger)index {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = (NSInteger)index;
    button.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 8.0;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    [button setTitle:action.title forState:UIControlStateNormal];
    [button addTarget:self action:@selector(_actionTapped:)
     forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:46.0].active = YES;

    switch (action.style) {
        case MMAlertActionStylePrimary:
            button.backgroundColor = MMAccentColor();
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            break;
        case MMAlertActionStyleDefault:
            button.backgroundColor = [MMAccentColor() colorWithAlphaComponent:0.12];
            [button setTitleColor:MMAccentColor() forState:UIControlStateNormal];
            break;
        case MMAlertActionStyleDestructive:
            button.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.12];
            [button setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
            break;
        case MMAlertActionStyleCancel:
            button.backgroundColor = [UIColor tertiarySystemFillColor];
            [button setTitleColor:[UIColor secondaryLabelColor] forState:UIControlStateNormal];
            break;
    }
    return button;
}

- (void)_installConstraints {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    _cardCenterConstraint = [_card.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor];
    _cardCenterConstraint.priority = UILayoutPriorityDefaultHigh;
    _cardBottomConstraint = [_card.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor
                                                                       constant:-18.0];

    [NSLayoutConstraint activateConstraints:@[
        [_dimmingView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_dimmingView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_dimmingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_dimmingView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_card.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        _cardCenterConstraint,
        _cardBottomConstraint,
        [_card.topAnchor constraintGreaterThanOrEqualToAnchor:guide.topAnchor constant:18.0],
        [_card.widthAnchor constraintLessThanOrEqualToConstant:330.0],
        [_card.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor
                                                         constant:28.0],
        [_card.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor
                                                       constant:-28.0],

        [_scrollView.topAnchor constraintEqualToAnchor:_card.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],

        [_contentStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor
                                                 constant:22.0],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor
                                                    constant:-18.0],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor
                                                     constant:20.0],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor
                                                      constant:-20.0],
        [_contentStack.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor
                                                  constant:-40.0],
    ]];

    NSLayoutConstraint *width = [_card.widthAnchor constraintEqualToConstant:330.0];
    width.priority = UILayoutPriorityDefaultHigh;
    width.active = YES;

    NSLayoutConstraint *preferredHeight = [_card.heightAnchor
        constraintEqualToAnchor:_contentStack.heightAnchor constant:40.0];
    preferredHeight.priority = 999.0;
    preferredHeight.active = YES;
}

#pragma mark - Interaction

- (void)_actionTapped:(UIButton *)sender {
    NSUInteger index = (NSUInteger)sender.tag;
    if (index >= self.actions.count || self.isDismissing) return;
    self.isDismissing = YES;
    MMAlertAction *action = self.actions[index];
    [self.textField resignFirstResponder];
    MMAlertController *alert = self;
    [self dismissViewControllerAnimated:YES completion:^{
        // Keep the controller (and its text field) alive until handlers have
        // read `textValue` and any follow-up dialog has been scheduled.
        (void)alert;
        if (action.handler) action.handler();
    }];
}

- (void)_backdropTapped {
    if (self.textField.isFirstResponder) {
        [self.textField resignFirstResponder];
        return;
    }
    if (!self.allowsBackdropDismiss || self.isDismissing) return;
    self.isDismissing = YES;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)_keyboardWillChange:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(local));
    NSTimeInterval duration =
        [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue] ?: 0.25;

    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat keyboardInset = MAX(0.0, overlap - safeBottom);
    self.cardBottomConstraint.constant = keyboardInset > 0.0
        ? -(keyboardInset + 12.0) : -18.0;
    self.cardCenterConstraint.constant = keyboardInset > 0.0 ? -(keyboardInset / 2.0) : 0.0;
    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseInOut
                     animations:^{ [self.view layoutIfNeeded]; }
                     completion:nil];
}

@end
