//
//  UAFInteractiveNavigationController.m
//  RhymesGesturalNavigationControllerProof
//
//  Created by Peng Wang on 6/7/13.
//  Copyright (c) 2013 Everynone. All rights reserved.
//

#import "UAFInteractiveNavigationController.h"

typedef NS_OPTIONS(NSUInteger, Flag) {
  FlagNone             = 0,
  FlagIsPerforming     = 1 << 0,
  FlagIsResetting      = 1 << 1,
  FlagIsStealingPan    = 1 << 2,
  FlagCanDelegate      = 1 << 3,
  FlagCanHandlePan     = 1 << 4,
};

typedef NS_ENUM(NSUInteger, PresentationFlag) {
  PresentationFlagNone,
  PresentationFlagBeingPresented,
  PresentationFlagBeingDismissed,
};

static NSArray *keyPathsToObserve;

@interface UAFInteractiveNavigationController ()

/**
 The base representation for navigational state.
 
 It's the base for implementing `-visibleViewController`,
 `-previousViewController`, `-nextViewController`. It's also buffered via KVO
 into <currentChildIndexBuffer> to help track more complex navigation flows.
 It's updated during navigation.
 */
@property (nonatomic) NSUInteger currentChildIndex;

/**
 Private flag bitmask. 
 
 The state for this component is too complex for a bunch
 of loose booleans. Normal and initial state includes `CanDelegate` and
 `CanHandlePan`. Flags are:
 
 - `None` - No flags.
 - `IsPerforming` - Is performing a navigation transition. During this, further
    navigation and auto-rotation handling are not allowed.
 - `IsResetting` - Is resetting its entire child-controller stack.
    During this, further auto-rotation handling is not allowed.
 - `IsStealingPan` - Is hijacking the pan gesture from a scrollable
    child-controller. During this, the pan gesture gets recognized as
    interactive navigation.
 - `CanDelegate` - Is able to call methods on `delegate`.
 - `CanHandlePan` - Is able to use the current pan gesture for interactive
    navigation.
 */
@property (nonatomic) Flag flags;

@property (strong, nonatomic, readwrite) UIView *containerView;

/**
 Unlike `childViewControllers`, this list is kept in order.
 
 This is to help implement paging and more specifically tiling, where order is
 required. So instead of using `childViewControllers`, this is used in
 conjunction with <currentChildIndex> to access child controllers.
 */
@property (strong, nonatomic) NSMutableArray *orderedChildViewControllers;

@property (nonatomic, readonly, getter = fetchNavigationDirection) UAFNavigationDirection navigationDirection;
@property (nonatomic, readonly, getter = fetchNavigationDuration) NSTimeInterval navigationDuration;

/**
 Whether to call delegate methods and set delegate flags (if applicable) for
 possible interactive navigation.

 Possible navigation means it can still be cancelled. See `pagingDelegate`'s `-
 customNavigationControllerShouldNotifyOfPossibleViewAppearanceChange`. Support
 for delegating on possible navigation allows for updating the child controller
 before it becomes visible when doing interactive navigation.
 */
@property (nonatomic, readonly, getter = shouldDelegatePossibleAppearanceChanges) BOOL shouldDelegatePossibleAppearanceChanges;

/**
 TODO: Document.
 */
@property (nonatomic, readonly, getter = shouldRemoveNextChildViewController) BOOL shouldRemoveNextChildViewController;

/**
 Search for child-controller matching a clue.
 
 This is mainly used to avoid operating on invalid child-controllers and
 to optimize management of child-controllers.
 @param clue Either the child-controller or the view-controller identifier.
 @see indexOfChildViewController:lenient:
 @return Has? using a strict equality test.
 */
- (BOOL)hasChildViewController:(id)clue;
/**
 Get index of child-controller matching a clue.
 
 When using the view-controller identifier approach, `lenient` is automatically
 on, since _we can't actually find a view-controller by it's identifier_.
 @param clue Either the child-controller or the view-controller identifier.
 @param lenient Flag for just checking the child-controller class.
 @see viewControllerForClue:
 @return Index, or `NSNotFound`.
 */
- (NSUInteger)indexOfChildViewController:(id)clue lenient:(BOOL)lenient;
/**
 Produce a view-controller matching a clue.
 
 Mainly used to abstract the translation of a clue into a view-controller.
 @param clue View-controller or view-controller identifier, anything else
 produces `nil`.
 @return View-controller if any.
 */
- (UIViewController *)viewControllerForClue:(id)clue;
/**
 Find the main content scroll-view of a child-controller.
 
 Used for dealing with navigation conflicts with scroll-views.
 @param childController Only `UIScrollViewController` and
 `UICollectionViewController` are supported.
 @return Scroll-view if any.
 */
- (UIScrollView *)scrollViewForChildViewController:(UIViewController *)childController;

/** @name CRUD */

/**
 The base routine for programmatically navigating to a new view-controller.
 
 @param childController Child-controller to register and present as needed.
 @param animated Animate the transition? This flag is passed into the delegate
 methods when applicable.
 @param focused Present `childController` inside <containerView>? Not doing so
 also bypasses the delegation methods, and is useful for informally updating the
 navigation (during a bigger navigation routine, etc.) and also bypasses
 <updateChildViewControllerTilingIfNeeded>. 
 
 Doing so, on the other hand, also does auto pushing (based on
 `nextNavigationItemIdentifier`) and auto replacement/removal (based on
 `previousNavigationItemIdentifier`) of child-controllers.
 
 The mechanics involve just updating frames. The new view's frame is fit into
 <containerView> and then offset one screen in the right direction. It's then
 moved into the current's frame and current view is moved one in the opposite
 direction.
 @param next `YES` means the adding is a 'push'. Otherwise, `childController` is
 inserted immediately before the current child-controller.
 @return Success?
 @see popViewControllerAnimated:focused:
 @note If `pagingEnabled` and child-controller is already registered,
 child-controller registration and setup (per the containment programming
 convention) is skipped. This is due to how child-controllers get stored when
 `pagingEnabled`.
 */
- (BOOL)addChildViewController:(UIViewController *)childController
                      animated:(BOOL)animated
                       focused:(BOOL)focused
                          next:(BOOL)isNext;

/**
 Subroutine for removing (freeing) child-controllers that are deemed no longer
 needed.
 
 This is one of the ways we make sure only the required child-controllers are
 retained in memory. Going in reverse, it checks and removes a child-controller
 unless:
 
 1. `pagingEnabled` is `NO` and the child-controller is not a branch node from
     the current child-controller, but a root node (coming before).
 2. `pagingEnabled` and the current 'tileset' need not be trimmed or the
     child-controller is part of the tileset.
 @return Success?
 */
- (BOOL)cleanChildViewControllersWithNextSiblingExemption:(BOOL)exemptNext;
/**
 Subroutine for deregistering a child-controller, following the containment
 convention.
 
 Named accordingly to avoid conflict with private API. Will also clean up any
 observer and gesture-recognizer bindings as needed.
 @param childController Ditto.
 @return Success?
 */
- (BOOL)handleRemoveChildViewController:(UIViewController *)childController;

/**
 If `pagingEnabled`, optimize storing child-controllers by only keeping the
 siblings within the 'tileset' loaded.
 
 The 'tileset' is hard-coded to only include the immediate siblings, which must
 be provided by the `pagingDelegate`.  Tiling is done by removing the
 unnecessary child-controllers first and then silently adding new ones as
 needed.
 @return Success?
 @see cleanChildViewControllersWithNextSiblingExemption:
 @note On 'success', assertion will be made that final tileset count is expected.
 */
- (BOOL)updateChildViewControllerTilingIfNeeded;

/**
 Subroutine for updating a child-controller's optional boolean presentation
 flags, if allowed by `shouldUpdatePresentationFlags`.
 
 All of the child-controller's presentation flags are updated.
 @param presented Our internal flag type.
 @param childController Ditto.
 @return Success?
 */
- (BOOL)togglePresentedIfNeeded:(PresentationFlag)presented
         forChildViewController:(UIViewController *)childController ;

/** @name Interactivity */

@property (strong, nonatomic, readwrite) UIPanGestureRecognizer *panGestureRecognizer;

/**
 Buffer for the previous child-controller's view, to be used by <handlePan:>.
 */
@property (weak, nonatomic) UIView *previousView;
/**
 Buffer for the 'current' child-controller's view, to be used by <handlePan:>.
 */
@property (weak, nonatomic) UIView *currentView;
/**
 Buffer for the next child-controller's view, to be used by <handlePan:>.
 */
@property (weak, nonatomic) UIView *nextView;
/**
 Contains all of the logic for interactive navigation.
 
 This is bound to not only this controller's view, but to other scroll-views as
 well for handling pan gesture conflicts. 
 
 As far as general mechanics, it looks at current translation and velocity to
 determine if navigation should 'complete' or 'revert', for both of which it
 them performs an animation with associated callbacks.
 
 In detail, it checks the `gesture.state` and performs appropriately, if at all:
 
 - `StateBegan` - Update the view buffers. Reset flags as needed.
   - If dealing with a scroll-view, start stealing pan-gesture if needed. When
     stealing, the scroll-indicator is hidden.
 - During - Derive translation and velocity based on gesture's view (this
   controller's view), guard as needed. Apply a transform to all view buffers
   based on the translation.
   - If dealing with a scroll-view and stealing pan, freeze `contentOffset` to
     the top.
   - Decides if hitting a boundary and if shorting is needed due to `bounces`
     being `NO`.
 - `StateEnded` - Decide if to 'finish' or to 'revert'. The new view is animated
    from a starting center based on the translation to the center of the
    viewport. The old view is animated from that center to be entirely
    offscreen, and in the same direction, such that the effect is both views are
    on the same 'canvas'.
   - If dealing with a scroll-view, end stealing pan-gesture if needed.
 - `StateCancelled`, `StateFailed` - Translation will be 0 so just animating to
    the transform based on the translation will do.
 - Complete (always) - Tiling gets updated as needed.
 @param gesture The pan gesture-recognizer.
 */
- (void)handlePan:(UIPanGestureRecognizer *)gesture;

/** @name Delegation Handlers */

@property (nonatomic) NSUInteger currentChildIndexBuffer;

/**
 Subroutine for delegating additional on-add behavior via `-
 customNavigationController:willAddViewController:`.
 
 Also delegates to `visibleViewController`.
 @param viewController Child-controller.
 @return Success?
 @see `FlagCanDelegate`
 */
- (BOOL)delegateWillAddViewController:(UIViewController *)viewController;
/**
 Subroutine for delegating additional will-show and will-hide behavior via `-
 customNavigationController:willShowViewController:animated:dismissed:`, etc.
 
 Will also call the conventional view-controller appearance handlers and toggle
 presentation flags if needed. The delegation involving the prior
 child-controller is also performed.
 @param viewController Child-controller.
 @param maybe Means the transition is not fully confirmed to complete.
 
 See `shouldDelegatePossibleAppearanceChanges`. Additional delegation does not
 happen, only the bare minimum.
 @param animated Ditto.
 @return Success?
 @see `FlagCanDelegate`
 @see togglePresentedIfNeeded:forChildViewController:
 */
- (BOOL)delegateWillTransitionToViewController:(UIViewController *)viewController
                                         maybe:(BOOL)maybe
                                      animated:(BOOL)animated;
/**
 Same as <delegateWillTransitionToViewController:maybe:animated> minus the
 `maybe` and that presentation flags are just reset.
 @param viewController Child-controller.
 @param animated Ditto.
 @return Success?
 @see `FlagCanDelegate`
 @see togglePresentedIfNeeded:forChildViewController:
 */
- (BOOL)delegateDidTransitionToViewController:(UIViewController *)viewController
                                     animated:(BOOL)animated;
/**
 Subroutine for delegating additional navigation guarding via `-
 customNavigationController:shouldNavigateToViewController:`.
 @param viewController Child-controller.
 @return Should? Default is `YES`.
 @note This one isn't guarded by `FlagCanDelegate` since it shouldn't modify
 delegate state.
 */
- (BOOL)delegateShouldNavigateToViewController:(UIViewController *)viewController;

@end

@implementation UAFInteractiveNavigationController

//-- UAFNavigationController
@synthesize delegate;
@synthesize baseNavigationDirection, onceNavigationDirection;
@synthesize baseNavigationDuration, onceNavigationDuration;
@synthesize pagingDelegate, pagingEnabled;
@synthesize shouldUpdatePresentationFlags;

//-- UAFInertialViewController
@synthesize bounces;

- (void)_commonInit
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    keyPathsToObserve = @[ NSStringFromSelector(@selector(currentChildIndex)) ];
  });
  [super _commonInit];
  //-- Custom initialization.
  self.shouldDebug = YES;
  self.baseNavigationDirection = UAFNavigationDirectionHorizontal;
  self.baseNavigationDuration = 0.8f;
  self.finishTransitionDurationFactor = 2.0f;
  self.finishTransitionDurationMinimum = 0.4f;
  self.bounces = YES;
  self.pagingEnabled = NO;
  self.shouldResetScrollViews = YES;
  self.flags = FlagCanDelegate|FlagCanHandlePan;
  self.orderedChildViewControllers = [NSMutableArray array];
  for (NSString *keyPath in keyPathsToObserve) {
    [self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
  }
}

- (void)dealloc
{
  for (NSString *keyPath in keyPathsToObserve) {
    [self removeObserver:self forKeyPath:keyPath];
  }  
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  //-- Do any additional setup after loading the view.
  //-- Gestures.
  self.panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
  self.panGestureRecognizer.delegate = self;
  [self.view addGestureRecognizer:self.panGestureRecognizer];
  //-- Container.
  self.containerView = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] currentBounds:self.wantsFullScreenLayout]];
  [self.view insertSubview:self.containerView atIndex:0];
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
  //-- Dispose of any resources that can be recreated.
}

/**
 Resizes subviews (child-controller views) inside <containerView> to match the
 latter's new bounds.
 
 @param toInterfaceOrientation Ditto.
 @param duration Ditto.
 */
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
  CGRect bounds = [[UIScreen mainScreen] boundsForOrientation:toInterfaceOrientation fullScreen:self.wantsFullScreenLayout];
  CGSize size = bounds.size;
  BOOL isLandscape = UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
  BOOL isHorizontal = self.baseNavigationDirection == UAFNavigationDirectionHorizontal;
  CGFloat newWidth  = (isLandscape && size.height > size.width) ? size.height : size.width;
  CGFloat newHeight = (isLandscape && size.height > size.width) ? size.width : size.height;
  CGFloat side = isHorizontal ? newWidth : newHeight;
  NSInteger indexOffset = -self.currentChildIndex;
  self.containerView.frame = CGRectMake(0.0f, 0.0f, newWidth, newHeight);
  [self.containerView.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    UIView *subview = obj;
    CGFloat offset = (idx + indexOffset) * side;
    subview.frame = CGRectMake(isHorizontal ? offset : 0.0f,
                               isHorizontal ? 0.0f : offset,
                               newWidth, newHeight);
  }];
  if (self.shouldDebug) DLog(@"%f, %f", newWidth, newHeight);
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
  
}

- (BOOL)shouldAutorotate
{
  return !(self.flags & FlagIsPerforming || self.flags & FlagIsResetting);
}

- (BOOL)shouldAutomaticallyForwardAppearanceMethods {
  return NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  id previousValue = change[NSKeyValueChangeOldKey];
  id value = change[NSKeyValueChangeNewKey];
  if ([value isEqual:previousValue]) {
    return;
  }
  if (object == self) {
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(currentChildIndex))]) {
      self.currentChildIndexBuffer = [previousValue unsignedIntegerValue];
    }
  }
}

#pragma mark - UAFNavigationController

- (BOOL)pushViewController:(id)viewController animated:(BOOL)animated completion:(void (^)(void))completion
{
  BOOL didPush = [self pushViewController:[self viewControllerForClue:viewController] animated:animated];
  if (didPush && completion) {
    if (animated) {
      UAFDispatchAfter(self.navigationDuration, completion);
    } else {
      completion();
    }
  }
  return didPush;
}
- (BOOL)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  return [self pushViewController:viewController animated:animated focused:YES];
}
- (BOOL)pushViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated
{
  return [self pushViewControllerWithIdentifier:identifier animated:animated focused:YES];
}
- (BOOL)pushViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated focused:(BOOL)focused
{
  return [self pushViewController:[self.storyboard instantiateViewControllerWithIdentifier:identifier]
                         animated:animated focused:focused];
}
- (BOOL)pushViewController:(UIViewController *)viewController animated:(BOOL)animated focused:(BOOL)focused
{
  return [self addChildViewController:viewController animated:animated focused:focused next:YES];
}

- (BOOL)popViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion
{
  BOOL didPop = [self popViewControllerAnimated:animated];
  if (didPop && completion) {
    if (animated) {
      UAFDispatchAfter(self.navigationDuration, completion);
    } else {
      completion();
    }
  }
  return didPop;
}
- (BOOL)popViewControllerAnimated:(BOOL)animated
{
  return [self popViewControllerAnimated:animated focused:YES];
}
/**
 The base routine for returning to the previous child-controller on the stack.
 
 This operation does not add or replace a child-controller, but only goes back
 one. If the newly visible child-controller links to the newly hidden one via
 `nextNavigationItemIdentifier`, the child-controller is exempt from removal.
 
 The mechanics involve just updating frames. The destination view is moved down
 to the source's frame, while the source moves down another frame, such that the
 effect is both views are on the same 'canvas'.
 @param animated Animate the transition? This flag is passed into the delegate
 methods when applicable.
 @param focused Delegate and <updateChildViewControllerTilingIfNeeded>?
 @return Success?
 @see addChildViewController:animated:focused:next:
 
 */
- (BOOL)popViewControllerAnimated:(BOOL)animated focused:(BOOL)focused
{
  //-- Guards.
  if (self.flags & FlagIsPerforming || self.currentChildIndex == 0) {
    if (self.shouldDebug) DLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  UIViewController *sourceViewController = self.orderedChildViewControllers[self.currentChildIndex];
  self.currentChildIndex--;
  UIViewController *destinationViewController = self.orderedChildViewControllers[self.currentChildIndex];
  UIScrollView *currentScrollView = nil;
  if (self.shouldResetScrollViews) {
    currentScrollView = [self scrollViewForChildViewController:sourceViewController];
  }
  //-- State.
  self.flags |= FlagIsPerforming;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsPerforming;
    if (focused) {
      [self delegateDidTransitionToViewController:destinationViewController animated:animated];
      if (![self updateChildViewControllerTilingIfNeeded]) {
        [self cleanChildViewControllersWithNextSiblingExemption:YES];
      }
    }
  };
  //-- /State.
  //-- Layout.
  UAFNavigationDirection direction = self.navigationDirection;
  void (^layout)(void) = ^{
    CGRect frame = self.containerView.bounds;
    destinationViewController.view.frame = frame;
    if (direction == UAFNavigationDirectionHorizontal) {
      frame.origin.x += frame.size.width;
    } else if (direction == UAFNavigationDirectionVertical) {
      frame.origin.y += frame.size.height;
    }
    sourceViewController.view.frame = frame;
  };
  //-- /Layout.
  if (focused) {
    [self delegateWillTransitionToViewController:destinationViewController maybe:NO animated:animated];
  }
  if (animated) {
    if (currentScrollView) {
      [currentScrollView setContentOffset:CGPointZero animated:YES];
      [UIView animateWithDuration:self.navigationDuration delay:0.6f options:UIViewAnimationOptionCurveEaseInOut
                       animations:layout completion:tearDown];
    } else {
      [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                       animations:layout completion:tearDown];
    }
  } else {
    layout();
    tearDown(YES);
  }
  return YES;
}

- (BOOL)popToViewController:(id)viewController animated:(BOOL)animated completion:(void (^)(void))completion
{
  BOOL didPop = [self popToViewController:[self viewControllerForClue:viewController] animated:animated];
  if (didPop && completion) {
    if (animated) {
      UAFDispatchAfter(self.navigationDuration, completion);
    } else {
      completion();
    }
  }
  return didPop;
}
- (BOOL)popToViewControllerWithIdentifier:(NSString *)identifier animated:(BOOL)animated
{
  return [self popToViewController:[self.storyboard instantiateViewControllerWithIdentifier:identifier]
                          animated:animated];
}
/**
 Mimics navigating back more than one child-controller.
 
 Instead, what happens is the entire stack is reset (silently), so any
 additional child-controllers between the source and destination are removed.
 Then follows a normal pop operation.
 @param animated Animate the transition? This flag is passed into the delegate
 methods when applicable.
 @return Success?
 @see popViewControllerAnimated:focused:
 @see setViewControllers:animated:focused:
 @see handleRemoveChildViewController:
 */
- (BOOL)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  //-- Guards.
  NSAssert(viewController, @"Avoid passing in nothing for child-controller.");
  if (!viewController) {
    return NO;
  }
  //-- /Guards.
  NSMutableArray *viewControllers = [NSMutableArray array];
  for (UIViewController *childViewController in self.orderedChildViewControllers) {
    [viewControllers addObject:childViewController];
    if (childViewController.class == viewController.class) {
      break;
    }
  }
  [viewControllers addObject:self.visibleViewController];
  BOOL shouldSilence = self.flags & FlagCanDelegate;
  if (shouldSilence) {
    self.flags &= ~FlagCanDelegate;
  }
  BOOL didReset = [self setViewControllers:viewControllers animated:NO focused:YES];
  if (shouldSilence) {
    self.flags |= FlagCanDelegate;
  }
  if (!didReset) {
    return NO;
  }
  return [self popViewControllerAnimated:animated];
}

- (BOOL)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated
{
  return [self setViewControllers:viewControllers animated:animated focused:YES];
}
/**
 Set child-controllers.
 
 This is used to re-/populate the child-controller stack. When just populating,
 push operations usually have focus. The navigation state is also reset to the
 first child-controller.
 @param viewControllers Will replace existing child-controllers, which are first
 removed in reverse. If object is a string, it's assumed to be a
 child-controller identifier and will be used in instantiation.
 @param animated Animate the transition? This flag is passed into the delegate
 methods when applicable.
 @param focused Allow push operations to be focused? (not silent)
 @return Success?
 @see handleRemoveChildViewController:
 */
- (BOOL)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated focused:(BOOL)focused
{
  //-- Guards.
  NSAssert(viewControllers, @"Avoid passing in nothing for child-controllers.");
  if (!viewControllers) {
    return NO;
  }
  if (self.flags & FlagIsResetting) {
    if (self.shouldDebug) DLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  //-- State.
  self.flags |= FlagIsResetting;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsResetting;
  };
  //-- /State.
  void (^addAndLayout)(void) = ^{
    [viewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      UIViewController *viewController = [obj isKindOfClass:[NSString class]]
      ? [self.storyboard instantiateViewControllerWithIdentifier:obj] : (UIViewController *)obj;
      BOOL didPush = [self pushViewController:viewController animated:NO focused:focused];
      NSAssert(didPush, @"Pushing failed! Inadequate view-controller: %@", viewController);
    }];
  };
  //-- Reset.
  //-- TODO: Eventually: Abstract as needed.
  for (NSInteger index = self.orderedChildViewControllers.count - 1; index >= 0; index--) {
    [self handleRemoveChildViewController:self.orderedChildViewControllers[index]];
  }
  self.currentChildIndex = 0;
  //-- /Reset.
  if (animated) {
    //-- TODO: Also: Unproven feature.
    NSTimeInterval duration = self.navigationDuration;
    [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
      self.containerView.alpha = 0.0f;
    } completion:^(BOOL finished) {
      addAndLayout();
      [UIView animateWithDuration:duration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.containerView.alpha = 1.0f;
      } completion:tearDown];
    }];
  } else {
    addAndLayout();
    tearDown(YES);
  }
  return YES;
}

- (BOOL)handleRemovalRequestForViewController:(UIViewController *)viewController
{
  if (![self hasChildViewController:viewController]) {
    if (self.shouldDebug) DLog(@"Guarded.");
    return NO;
  }
  BOOL didRemove = [self handleRemoveChildViewController:viewController];
  return didRemove;
}

- (UIViewController *)topViewController
{
  return self.orderedChildViewControllers.lastObject;
}

- (UIViewController *)visibleViewController
{
  if (!self.orderedChildViewControllers.count) {
    return nil;
  }
  return self.orderedChildViewControllers[self.currentChildIndex];
}

- (UIViewController *)previousViewController
{
  if (!self.orderedChildViewControllers.count || self.currentChildIndex <= 0) {
    return nil;
  }
  return self.orderedChildViewControllers[self.currentChildIndex - 1];
}

- (UIViewController *)nextViewController
{
  if (!self.orderedChildViewControllers.count || self.currentChildIndex >= self.orderedChildViewControllers.count - 1) {
    return nil;
  }
  return self.orderedChildViewControllers[self.currentChildIndex + 1];
}

- (NSArray *)viewControllers
{
  return self.orderedChildViewControllers;
}

#pragma mark - Private

- (UAFNavigationDirection)fetchNavigationDirection
{
  UAFNavigationDirection direction = self.baseNavigationDirection;
  if (self.onceNavigationDirection != UAFNavigationDirectionNone) {
    direction = self.onceNavigationDirection;
  }
  return direction;
}

//-- TODO: Eventually: Document usage.
- (NSTimeInterval)fetchNavigationDuration
{
  NSTimeInterval duration = self.baseNavigationDuration;
  if (self.onceNavigationDuration != kUAFNavigationDurationNone) {
    duration = self.onceNavigationDuration;
  }
  return duration;
}

- (BOOL)shouldDelegatePossibleAppearanceChanges
{
  return (self.pagingDelegate
          && [self.pagingDelegate respondsToSelector:@selector(customNavigationControllerShouldNotifyOfPossibleViewAppearanceChange:)]
          && [self.pagingDelegate customNavigationControllerShouldNotifyOfPossibleViewAppearanceChange:self]);
}

- (BOOL)shouldRemoveNextChildViewController
{
  return !([self.visibleViewController respondsToSelector:@selector(nextNavigationItemIdentifier)]
           && [(id)self.visibleViewController nextNavigationItemIdentifier].length
           && self.nextViewController.class == [[self.storyboard instantiateViewControllerWithIdentifier:
                                                 [(id)self.visibleViewController nextNavigationItemIdentifier]] class]);
}

- (BOOL)hasChildViewController:(id)clue
{
  return !([self indexOfChildViewController:clue lenient:NO] == NSNotFound);
}
- (NSUInteger)indexOfChildViewController:(id)clue lenient:(BOOL)lenient
{
  UIViewController *viewController = [self viewControllerForClue:clue];
  //-- Guard.
  NSAssert(viewController, @"Can't find child-controller for given clue: %@", clue);
  if (!viewController) {
    return NSNotFound;
  }
  __block NSUInteger result = NSNotFound;
  if (lenient || [clue isKindOfClass:[NSString class]]) {
    [self.orderedChildViewControllers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      if ([obj class] == viewController.class) {
        result = idx;
        stop = YES;
      }
    }];
    viewController = nil;
  } else {
    result = [self.orderedChildViewControllers indexOfObject:viewController];
  }
  return result;
}

- (UIViewController *)viewControllerForClue:(id)clue
{
  UIViewController *viewController = nil;
  if ([clue isKindOfClass:[UIViewController class]]) {
    viewController = clue;
  } else if ([clue isKindOfClass:[NSString class]]) {
    viewController = [self.storyboard instantiateViewControllerWithIdentifier:clue];
  }
  return viewController;
}

- (UIScrollView *)scrollViewForChildViewController:(UIViewController *)childController
{
  UIScrollView *view = nil;
  if ([childController.view isKindOfClass:[UIScrollView class]]) {
    view = (id)childController.view;
  } else if ([childController isKindOfClass:[UICollectionViewController class]]) {
    view = [(id)childController collectionView];
  }
  return view;
}

#pragma mark CRUD

- (BOOL)addChildViewController:(UIViewController *)childController animated:(BOOL)animated focused:(BOOL)focused next:(BOOL)isNext
{
  //-- Guards.
  NSAssert(childController, @"Avoid passing in nothing for child-controller.");
  if (!childController) {
    return NO;
  }
  if (self.flags & FlagIsPerforming) {
    if (self.shouldDebug) DLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  NSInteger siblingModifier = isNext ? 1 : -1;
  UIViewController *currentViewController = nil;
  if (self.orderedChildViewControllers.count) {
    currentViewController = self.orderedChildViewControllers[self.currentChildIndex];
  }
  UIScrollView *currentScrollView = nil;
  if (self.shouldResetScrollViews && focused) {
    currentScrollView = [self scrollViewForChildViewController:currentViewController];
  }
  //-- State.
  self.flags |= FlagIsPerforming;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsPerforming;
    if (focused) {
      [self delegateDidTransitionToViewController:childController animated:animated];
      [self updateChildViewControllerTilingIfNeeded];
    }
    if (isNext && focused) {
      //-- Setup once.
      if ([childController respondsToSelector:@selector(nextNavigationItemIdentifier)]
          && [(id)childController nextNavigationItemIdentifier].length
          ) {
        [self pushViewControllerWithIdentifier:[(id)childController nextNavigationItemIdentifier] animated:NO focused:NO];
      }
      if ([childController respondsToSelector:@selector(previousNavigationItemIdentifier)]
          && [(id)childController previousNavigationItemIdentifier].length
          ) {
        UIViewController *siblingViewController = [self.storyboard instantiateViewControllerWithIdentifier:[(id)childController previousNavigationItemIdentifier]];
        BOOL shouldRemove = self.previousViewController && siblingViewController.class != self.previousViewController.class;
        NSUInteger existingSiblingIndex = [self indexOfChildViewController:[(id)childController previousNavigationItemIdentifier] lenient:YES];
        if (shouldRemove) {
          [self handleRemoveChildViewController:self.previousViewController];
        }
        if (existingSiblingIndex == NSNotFound
            || !(existingSiblingIndex < self.currentChildIndex)
            ) {
          //-- TODO: Also: Untested.
          [self addChildViewController:siblingViewController animated:NO focused:NO next:NO];
        }
      }
    }
  };
  //-- /State.
  //-- Layout.
  CGRect frame = self.containerView.bounds;
  //-- Guard.
  NSAssert(!CGRectEqualToRect(frame, CGRectZero), @"No layout yet for container-view.");
  if (CGRectEqualToRect(frame, CGRectZero)) {
    return NO;
  }
  UAFNavigationDirection direction = self.navigationDirection;
  if (direction == UAFNavigationDirectionHorizontal) {
    frame.origin.x += siblingModifier * frame.size.width;
  } else if (direction == UAFNavigationDirectionVertical) {
    frame.origin.y += siblingModifier * frame.size.height;
  }
  [self delegateWillAddViewController:childController];
  childController.view.frame = frame;
  void (^finishLayout)(void) = !focused ? nil
  : ^{
    CGRect frame = self.containerView.bounds;
    childController.view.frame = frame;
    if (direction == UAFNavigationDirectionHorizontal) {
      frame.origin.x -= siblingModifier * frame.size.width;
    } else if (direction == UAFNavigationDirectionVertical) {
      frame.origin.y -= siblingModifier * frame.size.height;
    }
    if (currentViewController) {
      currentViewController.view.frame = frame;
    }
  };
  CGPoint targetContentOffset;
  if (currentScrollView) {
    BOOL isHorizontal = self.baseNavigationDirection == UAFNavigationDirectionHorizontal;
    targetContentOffset = CGPointMake(isHorizontal ? currentScrollView.contentSize.width - currentScrollView.width : 0.0f,
                                      isHorizontal ? 0.0f : currentScrollView.contentSize.height - currentScrollView.height);
  }
  //-- /Layout.
  //-- Add.
  if (focused) {
    [self cleanChildViewControllersWithNextSiblingExemption:NO];
  }
  BOOL shouldSkipAdding = self.pagingEnabled && [self hasChildViewController:childController];
  if (!shouldSkipAdding) {
    [self addChildViewController:childController];
    if (isNext) {
      [self.orderedChildViewControllers addObject:childController];
    } else {
      [self.orderedChildViewControllers insertObject:childController atIndex:0];
    }
    if (self.shouldDebug) DLog(@"%@", self.orderedChildViewControllers);
    childController.view.clipsToBounds = YES;
    if ([childController respondsToSelector:@selector(setCustomNavigationController:)]) {
      [(id)childController setCustomNavigationController:self];
    }
    //-- TODO: Finally: Detect more scroll-views.
    if ([childController isKindOfClass:[UICollectionViewController class]]) {
      UIScrollView *scrollView = [(UICollectionViewController *)childController collectionView];
      [scrollView.panGestureRecognizer addTarget:self action:@selector(handlePan:)];
    }
    if ([childController respondsToSelector:@selector(customNavigationControllerSubviewsToSupportInteractiveNavigation:)]) {
      NSArray *subviews = [(id)childController customNavigationControllerSubviewsToSupportInteractiveNavigation:self];
      if (subviews) {
        for (UIView *view in subviews) {
          if ([view isKindOfClass:[UIScrollView class]]) {
            [[(UIScrollView *)view panGestureRecognizer] addTarget:self action:@selector(handlePan:)];
          }
        }
      }
    }
    [self.containerView addSubview:childController.view];
    [childController didMoveToParentViewController:self];
  }
  //-- /Add.
  if (focused) {
    [self delegateWillTransitionToViewController:childController maybe:NO animated:animated];
  }
  if (animated) {
    if (currentScrollView) {
      [currentScrollView setContentOffset:targetContentOffset animated:YES];
      [UIView animateWithDuration:self.navigationDuration delay:0.6f options:UIViewAnimationOptionCurveEaseInOut
                       animations:finishLayout completion:tearDown];
    } else {
      [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                       animations:finishLayout completion:tearDown];
    }
  } else {
    if (finishLayout) {
      finishLayout();
    }
    tearDown(YES);
  }
  if (currentViewController && focused) {
    self.currentChildIndex += siblingModifier;
  }
  return YES;
}

- (BOOL)cleanChildViewControllersWithNextSiblingExemption:(BOOL)exemptNext
{
  if (!self.orderedChildViewControllers.count || self.flags & FlagIsResetting) {
    return NO;
  }
  if (self.shouldDebug) DLog(@"Visible index: %d", self.currentChildIndex);
  for (NSInteger index = self.orderedChildViewControllers.count - 1; index >= 0; index--) {
    UIViewController *viewController = self.orderedChildViewControllers[index];
    BOOL exempt           = (!self.pagingEnabled && exemptNext
                             && viewController == self.nextViewController
                             && !self.shouldRemoveNextChildViewController);
    BOOL isOfSharedRoot   = index <= self.currentChildIndex;
    BOOL isWithinTileset  = index <= self.currentChildIndex + 1 && index >= self.currentChildIndex - 1;
    BOOL isTilesetReady   = self.orderedChildViewControllers.count <= 2;
    if (exempt
        || (!self.pagingEnabled && (isOfSharedRoot))
        || (self.pagingEnabled && (isWithinTileset || isTilesetReady))
        ) {
      continue;
    }
    [self handleRemoveChildViewController:viewController];
  }
  return YES;
}

- (BOOL)handleRemoveChildViewController:(UIViewController *)childController
{
  NSAssert(childController, @"Avoid passing in nothing for child-controller.");
  if (!childController) {
    return NO;
  }
  [childController willMoveToParentViewController:nil];
  [childController.view removeFromSuperview];
  [childController removeFromParentViewController];
  [childController didMoveToParentViewController:nil];
  NSUInteger index = [self.orderedChildViewControllers indexOfObject:childController]; //-- Save index beforehand.
  [self.orderedChildViewControllers removeObject:childController];
  UIScrollView *scrollView = [self scrollViewForChildViewController:childController];
  if (scrollView) {
    [scrollView.panGestureRecognizer removeTarget:self action:NULL];
  }
  if (index < self.currentChildIndex && self.currentChildIndex > 0) {
    self.currentChildIndex--;
  }
  if (self.shouldDebug) DLog(@"Cleared index: %d", index);
  childController = nil;
  return YES;
}

- (BOOL)updateChildViewControllerTilingIfNeeded
{
  if (!self.pagingEnabled || !self.pagingDelegate) {
    return NO;
  }
  [self cleanChildViewControllersWithNextSiblingExemption:NO];
  BOOL didUpdate = NO;
  UIViewController *nextViewController = [self.pagingDelegate customNavigationController:self viewControllerAfterViewController:self.visibleViewController];
  UIViewController *previousViewController = [self.pagingDelegate customNavigationController:self viewControllerBeforeViewController:self.visibleViewController];
  if (nextViewController && self.currentChildIndex == self.orderedChildViewControllers.count - 1) {
    didUpdate = [self pushViewController:nextViewController animated:NO focused:NO];
  }
  if (previousViewController && self.currentChildIndex == 0) {
    didUpdate = [self addChildViewController:previousViewController animated:NO focused:NO next:NO];
    if (didUpdate) {
      self.currentChildIndex++;
    }
  }
  if (didUpdate) {
    NSAssert(self.orderedChildViewControllers.count == 3
             || (!(previousViewController && nextViewController) && self.orderedChildViewControllers.count == 2),
             @"Tiling had errors. %@", self.orderedChildViewControllers);
  }
  return didUpdate;
}

- (BOOL)togglePresentedIfNeeded:(PresentationFlag)presented forChildViewController:(UIViewController *)childController ;
{
  if (!self.shouldUpdatePresentationFlags) {
    return NO;
  }
  BOOL didUpdate = NO;
  BOOL isBeingPresented = presented == PresentationFlagBeingPresented;
  BOOL isBeingDismissed = presented == PresentationFlagBeingDismissed;
  if (presented == PresentationFlagNone) {
    isBeingPresented = isBeingDismissed = NO;
  }
  if ([childController respondsToSelector:@selector(setCustomIsBeingPresented:)]) {
    didUpdate = YES;
    [(id)childController setCustomIsBeingPresented:isBeingPresented];
    if ([childController respondsToSelector:@selector(setCustomIsBeingDismissed:)]) {
      [(id)childController setCustomIsBeingDismissed:isBeingDismissed];
    }
  }
  return didUpdate;
}

#pragma mark Interactivity

- (void)handlePan:(UIPanGestureRecognizer *)gesture
{
  //-- TODO: Finally: Consider how to split this up.
  BOOL isHorizontal = self.baseNavigationDirection == UAFNavigationDirectionHorizontal;
  BOOL shouldCancel = NO;
  CGPoint translation = [gesture translationInView:gesture.view];
  CGPoint velocity    = [gesture velocityInView:gesture.view];
  CGFloat translationValue = isHorizontal ? translation.x : translation.y;
  CGFloat velocityValue    = isHorizontal ? velocity.x : velocity.y;
  UIViewController *destinationViewController = (translationValue < 0) ? self.nextViewController : self.previousViewController;
  //-- Start.
  if (gesture.state == UIGestureRecognizerStateBegan) {
    self.flags |= FlagCanHandlePan;
    //-- Identify as needed.
    self.previousView = self.previousViewController ? self.previousViewController.view : nil;
    self.nextView = self.nextViewController ? self.nextViewController.view : nil;
    self.currentView = self.visibleViewController.view;
  }
  //-- /Start.
  //-- Guards.
  if (self.flags & FlagIsPerforming) {
    return;
  }
  //-- Check delegates.
  if (gesture.state == UIGestureRecognizerStateBegan
      && ![self delegateShouldNavigateToViewController:destinationViewController]
      ) {
    self.flags &= ~FlagCanHandlePan;
    return;
  }
  //-- Only handle supported directions and passing gestures.
  if (!(self.flags & FlagCanHandlePan)) {
    return;
  } else if ((isHorizontal && ABS(velocity.x) < ABS(velocity.y))
             || (!isHorizontal && ABS(velocity.y) < ABS(velocity.x))
             ) {
    if (self.shouldDebug) DLog(@"Can't handle gesture (%@).", NSStringFromClass(self.class));
    self.flags &= ~FlagCanHandlePan;
    shouldCancel = YES;
  }
  //-- Only continue if `bounces` option is on when at a boundary.
  if (!self.bounces) {
    BOOL isNextBoundary     = translationValue < 0 && !self.nextView;
    BOOL isPreviousBoundary = translationValue > 0 && !self.previousView;
    if (isNextBoundary || isPreviousBoundary) {
      return;
    }
  }
  //-- Scrolling conflict resolution.
  //-- TODO: Also: Try alternative with `requireGestureRecognizerToFail:`.
  //-- TODO: Finally: Handle `nextView`.
  //-- TODO: Firstly: Optimize.
  if ([gesture.view isKindOfClass:[UIScrollView class]]) {
    UIScrollView *scrollView = (id)gesture.view;
    if (scrollView.contentSize.height > scrollView.height) {
      if (self.previousView) {
        CGPoint velocity = [gesture velocityInView:gesture.view];
        if (self.shouldDebug) DLog(@"%f", [gesture velocityInView:gesture.view].y);
        BOOL shouldDismiss = ((isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y) <= 0.0f
                              && (isHorizontal ? velocity.x : velocity.y) > 0.0f); //-- NOTE: Refactor with `velocityValue` as needed.
        if (!shouldDismiss && !(self.flags & FlagIsStealingPan)) {
          return;
        }
        void (^togglePanStealing)(BOOL) = ^(BOOL on) {
          if (on) {
            self.flags |= FlagIsStealingPan;
          } else {
            self.flags &= ~FlagIsStealingPan;
          }
          if (isHorizontal) {
            scrollView.showsHorizontalScrollIndicator = !on; //-- TODO: Finally: Don't be assumptive about previous value.
          } else {
            scrollView.showsVerticalScrollIndicator = !on;
          }
        };
        if (gesture.state == UIGestureRecognizerStateBegan) {
          togglePanStealing(YES);
        }
        if (!(self.flags & FlagIsStealingPan)) {
          return;
        } else if (self.flags & FlagIsStealingPan && gesture.state != UIGestureRecognizerStateEnded) {
          scrollView.contentOffset = CGPointZero; //-- TODO: Also: Account for content-insets?
        } else if (gesture.state == UIGestureRecognizerStateEnded) {
          togglePanStealing(NO);
        }
      } else {
        //-- TODO: Also: Handle `nextView`.
        return;
      }
    }
  }
  //-- /Guards.
  //-- Complete start.
  if (gesture.state == UIGestureRecognizerStateBegan && self.shouldDelegatePossibleAppearanceChanges) {
    [self delegateWillTransitionToViewController:destinationViewController maybe:YES animated:YES];
  }
  //-- /Complete start.
  //-- Update.
  CGAffineTransform transform =
  CGAffineTransformMakeTranslation(isHorizontal ? translation.x : 0.0f,
                                   isHorizontal ? 0.0f : translation.y);
  //-- Set transforms.
  self.previousView.transform = self.currentView.transform = self.nextView.transform = transform;
  //-- /Update.
  //-- Finalize.
  if (gesture.state == UIGestureRecognizerStateEnded
      || gesture.state == UIGestureRecognizerStateCancelled
      || gesture.state == UIGestureRecognizerStateFailed
      || shouldCancel
      ) {
    //-- Layout.
    CGPoint finalCenter = self.currentView.center;
    CGPoint currentCenter = CGPointMake(isHorizontal ? (finalCenter.x + translation.x) : finalCenter.x,
                                        isHorizontal ? finalCenter.y : (finalCenter.y + translation.y));
    CGFloat currentSide   = isHorizontal ? self.currentView.width : self.currentView.height;
    CGFloat containerSide = isHorizontal ? self.containerView.width : self.containerView.height;
    CGPoint (^makeStartCenter)(UIView *) = ^(UIView *view) {
      return CGPointMake(isHorizontal ? (view.center.x + translation.x) : view.center.x,
                         isHorizontal ? view.center.y : (view.center.y + translation.y));
    };
    CGPoint (^makeFinalOffsetForCurrentView)(NSInteger) = ^(NSInteger direction) {
      return CGPointMake(isHorizontal ? (finalCenter.x - direction * self.currentView.width) : finalCenter.x,
                         isHorizontal ? finalCenter.y : (finalCenter.y - direction * self.currentView.height));
    };
    NSTimeInterval (^makeFinalFinishDuration)(NSTimeInterval) = ^(NSTimeInterval duration) {
      return MIN(MAX(duration, self.finishTransitionDurationMinimum), self.baseNavigationDuration);
    };
    void (^resetTransforms)(void) = ^{
      self.previousView.transform = self.currentView.transform = self.nextView.transform = CGAffineTransformIdentity;
    };
    //-- /Layout.
    NSTimeInterval finishDuration = self.baseNavigationDuration;
    BOOL finishedPanToNext      = !shouldCancel && (self.nextView && translationValue + (velocityValue / 2.0f) < -containerSide / 2.0f);
    BOOL finishedPanToPrevious  = !shouldCancel && (self.previousView && translationValue + (velocityValue / 2.0f) > containerSide / 2.0f);
    void (^handleDidShow)(BOOL) = nil;
    //-- Finish. Animate if needed.
    if (finishedPanToNext || finishedPanToPrevious) {
      //-- Reset transforms.
      resetTransforms();
      finishDuration *= (currentSide / 2.0f) / ABS((translationValue + (velocityValue / 2.0f)) / self.finishTransitionDurationFactor);
      finishDuration = makeFinalFinishDuration(finishDuration);
      //-- Callbacks.
      destinationViewController = self.orderedChildViewControllers[self.currentChildIndex + (finishedPanToNext ? 1 : -1)];
      //-- TODO: Also: Defect where blank screen shows for a moment.
      [self delegateWillTransitionToViewController:destinationViewController maybe:NO animated:YES];
      handleDidShow = ^(BOOL finished) {
        [self delegateDidTransitionToViewController:destinationViewController animated:YES];
        //-- Extra.
        if (![self updateChildViewControllerTilingIfNeeded]) {
          [self cleanChildViewControllersWithNextSiblingExemption:finishedPanToPrevious];
        }
      };
    }
    UIViewAnimationOptions easingOptions = (ABS(translationValue) > 300.0f && (finishedPanToNext || finishedPanToPrevious))
    ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseInOut;
    if (finishedPanToNext) {
      //-- Layout and animate from midway.
      CGPoint previousOffset = makeFinalOffsetForCurrentView(1);
      CGPoint nextCenter = makeStartCenter(self.nextView);
      self.currentView.center = currentCenter;
      self.nextView.center = nextCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = previousOffset;
        self.nextView.center = finalCenter;
      };
      self.currentChildIndex++;
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:finishLayout completion:handleDidShow];
    } else if (finishedPanToPrevious) {
      //-- Layout and animate from midway.
      CGPoint nextOffset = makeFinalOffsetForCurrentView(-1);
      CGPoint previousCenter = makeStartCenter(self.previousView);
      self.currentView.center = currentCenter;
      self.previousView.center = previousCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = nextOffset;
        self.previousView.center = finalCenter;
      };
      self.currentChildIndex--;
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:finishLayout completion:handleDidShow];
    } else {
      //-- Just update animated.
      finishDuration *= ABS((translationValue + (velocityValue / 2.0f)) / (currentSide / 2.0f) / self.finishTransitionDurationFactor);
      finishDuration = makeFinalFinishDuration(finishDuration);
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:resetTransforms completion:handleDidShow];
      [self delegateWillTransitionToViewController:self.visibleViewController maybe:YES animated:YES];
    }
    //-- /Finish.
    if (self.shouldDebug) {
      DLog(@"%f", velocityValue);
      DLog(@"%f", translationValue);
      DLog(@"%f", finishDuration);
    }
  }
}

#pragma mark Delegation Handlers

- (BOOL)delegateWillAddViewController:(UIViewController *)viewController
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  SEL selector = @selector(customNavigationController:willAddViewController:);
  if ([self.delegate respondsToSelector:selector]) {
    [self.delegate customNavigationController:self willAddViewController:viewController];
  }
  if (self.visibleViewController && [self.visibleViewController respondsToSelector:selector]) {
    [(id)self.visibleViewController customNavigationController:self willAddViewController:viewController];
  }
  return YES;
}
- (BOOL)delegateWillTransitionToViewController:(UIViewController *)viewController maybe:(BOOL)maybe animated:(BOOL)animated
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  BOOL shouldDelegate = !maybe || self.shouldDelegatePossibleAppearanceChanges;
  BOOL dismissed = [self.orderedChildViewControllers indexOfObject:viewController] < self.currentChildIndex;
  SEL showSelector = @selector(customNavigationController:willShowViewController:animated:dismissed:);
  SEL hideSelector = @selector(customNavigationController:willHideViewController:animated:dismissed:);
  UIViewController *sourceViewController = self.visibleViewController;
  if (!maybe) {
    [self togglePresentedIfNeeded:PresentationFlagBeingPresented forChildViewController:viewController];
    if (sourceViewController) {
      [self togglePresentedIfNeeded:PresentationFlagBeingDismissed forChildViewController:sourceViewController];
    }
  }
  if (shouldDelegate && [self.delegate respondsToSelector:showSelector]) {
    [self.delegate customNavigationController:self willShowViewController:viewController animated:animated dismissed:dismissed];
  }
  if (sourceViewController) {
    if (shouldDelegate && [self.delegate respondsToSelector:hideSelector]) {
      [self.delegate customNavigationController:self willHideViewController:viewController animated:animated dismissed:dismissed];
    }
    if (!maybe) {
      if ([sourceViewController respondsToSelector:showSelector]) {
        [(id)sourceViewController customNavigationController:self willShowViewController:viewController animated:animated dismissed:dismissed];
      }
      if ([viewController respondsToSelector:hideSelector]) {
        [(id)viewController customNavigationController:self willHideViewController:sourceViewController animated:animated dismissed:dismissed];
      }
      [sourceViewController viewWillDisappear:animated];
    }
  }
  if (!maybe) {
    [viewController viewWillAppear:animated];
  }
  return YES;
}

- (BOOL)delegateDidTransitionToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  if (!(self.flags & FlagCanDelegate)) {
    return NO;
  }
  BOOL dismissed = [self.orderedChildViewControllers indexOfObject:viewController] < self.currentChildIndex;
  SEL showSelector = @selector(customNavigationController:didShowViewController:animated:dismissed:);
  SEL hideSelector = @selector(customNavigationController:didHideViewController:animated:dismissed:);
  UIViewController *sourceViewController = nil;
  if (self.currentChildIndexBuffer < self.orderedChildViewControllers.count) {
    //-- Check if source child-controller's been removed.
    sourceViewController = self.orderedChildViewControllers[self.currentChildIndexBuffer];
  }
  [self togglePresentedIfNeeded:PresentationFlagNone forChildViewController:viewController];
  if (sourceViewController) {
    [self togglePresentedIfNeeded:PresentationFlagNone forChildViewController:sourceViewController];
  }
  if ([self.delegate respondsToSelector:showSelector]) {
    [self.delegate customNavigationController:self didShowViewController:viewController animated:animated dismissed:dismissed];
  }
  if (sourceViewController) {
    [self togglePresentedIfNeeded:PresentationFlagNone forChildViewController:sourceViewController];
    if ([self.delegate respondsToSelector:hideSelector]) {
      [self.delegate customNavigationController:self didHideViewController:viewController animated:animated dismissed:dismissed];
    }
    if ([sourceViewController respondsToSelector:showSelector]) {
      [(id)sourceViewController customNavigationController:self didShowViewController:viewController animated:animated dismissed:dismissed];
    }
    if ([viewController respondsToSelector:hideSelector]) {
      [(id)viewController customNavigationController:self didHideViewController:sourceViewController animated:animated dismissed:dismissed];
    }
    [sourceViewController viewDidDisappear:animated];
  }
  [viewController viewDidAppear:animated];
  return YES;
}

- (BOOL)delegateShouldNavigateToViewController:(UIViewController *)viewController
{
  BOOL shouldNavigate = YES;
  SEL selector = @selector(customNavigationController:shouldNavigateToViewController:);
  if ([self.visibleViewController respondsToSelector:selector]) {
    shouldNavigate = [(id)self.visibleViewController customNavigationController:self shouldNavigateToViewController:viewController];
  }
  if ([self.delegate respondsToSelector:selector]) {
    shouldNavigate = [self.delegate customNavigationController:self shouldNavigateToViewController:viewController];
  }
  return shouldNavigate;
}

#pragma mark - UIGestureRecognizerDelegate

//-- NOTE: Subclassing the gesture-recognizer can allow setting recognizer priority / prevention.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  //-- Prevent just the scroll-view scenario.
  BOOL shouldRecognize = !([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]
                           && ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]
                               || otherGestureRecognizer.view == self.currentView));
  return shouldRecognize;
}

@end
