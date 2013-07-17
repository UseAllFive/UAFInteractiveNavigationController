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

@property (nonatomic) NSUInteger currentChildIndex;
@property (nonatomic) Flag flags;

@property (strong, nonatomic, readwrite) UIView *containerView;

@property (strong, nonatomic) NSMutableArray *orderedChildViewControllers;

@property (nonatomic, readonly, getter = fetchNavigationDirection) UAFNavigationDirection navigationDirection;
@property (nonatomic, readonly, getter = fetchNavigationDuration) NSTimeInterval navigationDuration;
@property (nonatomic, readonly, getter = shouldDelegatePossibleAppearanceChanges) BOOL shouldDelegatePossibleAppearanceChanges;

- (BOOL)hasChildViewController:(id)clue;
- (NSUInteger)indexOfChildViewController:(id)clue lenient:(BOOL)lenient;
- (UIViewController *)viewControllerForClue:(id)clue;

/** @name CRUD */

- (BOOL)addChildViewController:(UIViewController *)childController animated:(BOOL)animated focused:(BOOL)focused next:(BOOL)isNext;

- (BOOL)cleanChildViewControllers;
- (BOOL)handleRemoveChildViewController:(UIViewController *)childController; //-- Named to avoid conflict with private API.

- (BOOL)updateChildViewControllerTilingIfNeeded;

- (BOOL)togglePresentedIfNeeded:(PresentationFlag)presented forChildViewController:(UIViewController *)childController ;

/** @name Interactivity */

@property (strong, nonatomic, readwrite) UIPanGestureRecognizer *panGestureRecognizer;

@property (strong, nonatomic) UIView *previousView;
@property (strong, nonatomic) UIView *currentView;
@property (strong, nonatomic) UIView *nextView;

- (void)handlePan:(UIPanGestureRecognizer *)gesture;

/** @name Delegation Handlers */

@property (nonatomic) NSUInteger currentChildIndexBuffer;

- (BOOL)delegateWillAddViewController:(UIViewController *)viewController;
- (BOOL)delegateWillTransitionToViewController:(UIViewController *)viewController maybe:(BOOL)maybe animated:(BOOL)animated;
- (BOOL)delegateDidTransitionToViewController:(UIViewController *)viewController animated:(BOOL)animated;
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
    keyPathsToObserve = @[ @"currentChildIndex" ];
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

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  id previousValue = change[NSKeyValueChangeOldKey];
  id value = change[NSKeyValueChangeNewKey];
  if ([value isEqual:previousValue]) {
    return;
  }
  if (object == self) {
    if ([keyPath isEqualToString:@"currentChildIndex"]) {
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
- (BOOL)popViewControllerAnimated:(BOOL)animated focused:(BOOL)focused
{
  //-- Guards.
  if (self.flags & FlagIsPerforming || self.currentChildIndex == 0) {
    if (self.shouldDebug) DLog(@"Guarded.");
    return NO;
  }
  //-- /Guards.
  UIViewController *currentViewController = self.orderedChildViewControllers[self.currentChildIndex];
  self.currentChildIndex--;
  UIViewController *viewController = self.orderedChildViewControllers[self.currentChildIndex];
  //-- State.
  self.flags |= FlagIsPerforming;
  void (^tearDown)(BOOL) = ^(BOOL finished) {
    self.flags &= ~FlagIsPerforming;
    BOOL shouldRemove = YES;
    if ([viewController respondsToSelector:@selector(nextNavigationItemIdentifier)]
        && [(id)viewController nextNavigationItemIdentifier].length
        ) {
      //-- Don't remove VC if it's specified as a sibling item.
      shouldRemove = currentViewController.class != [[self.storyboard instantiateViewControllerWithIdentifier:
                                                      [(id)viewController nextNavigationItemIdentifier]] class];
    }
    if (shouldRemove) {
      if (self.shouldDebug) DLog(@"Removing...");
      [self handleRemoveChildViewController:currentViewController];
    }
    if (focused) {
      [self delegateDidTransitionToViewController:viewController animated:animated];
      [self updateChildViewControllerTilingIfNeeded];
    }
  };
  //-- /State.
  //-- Layout.
  UAFNavigationDirection direction = self.navigationDirection;
  void (^layout)(void) = ^{
    CGRect frame = self.containerView.bounds;
    viewController.view.frame = frame;
    if (direction == UAFNavigationDirectionHorizontal) {
      frame.origin.x += frame.size.width;
    } else if (direction == UAFNavigationDirectionVertical) {
      frame.origin.y += frame.size.height;
    }
    currentViewController.view.frame = frame;
  };
  //-- /Layout.
  if (focused) {
    [self delegateWillTransitionToViewController:viewController maybe:NO animated:animated];
  }
  if (animated) {
    [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                     animations:layout completion:tearDown];
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
  UIViewController *currentViewController = nil;
  if (self.orderedChildViewControllers.count) {
    currentViewController = self.orderedChildViewControllers[self.currentChildIndex];
  }
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
  //-- /Layout.
  //-- Add.
  if (focused) {
    [self cleanChildViewControllers];
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
    [self.containerView addSubview:childController.view];
    [childController didMoveToParentViewController:self];
  }
  //-- /Add.
  if (focused) {
    [self delegateWillTransitionToViewController:childController maybe:NO animated:animated];
  }
  if (animated) {
    [UIView animateWithDuration:self.navigationDuration delay:0.0f options:UIViewAnimationOptionCurveEaseInOut
                     animations:finishLayout completion:tearDown];
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

- (BOOL)cleanChildViewControllers
{
  if (!self.orderedChildViewControllers.count || self.flags & FlagIsResetting) {
    return NO;
  }
  if (self.shouldDebug) DLog(@"Visible index: %d", self.currentChildIndex);
  for (NSInteger index = self.orderedChildViewControllers.count - 1; index >= 0; index--) {
    BOOL isOfSharedRoot   = index <= self.currentChildIndex;
    BOOL isWithinTileset  = index <= self.currentChildIndex + 1 && index >= self.currentChildIndex - 1;
    BOOL isTilesetReady   = self.orderedChildViewControllers.count <= 2;
    if ((!self.pagingEnabled && isOfSharedRoot)
        || (self.pagingEnabled && (isWithinTileset || isTilesetReady))
        ) {
      continue;
    }
    [self handleRemoveChildViewController:self.orderedChildViewControllers[index]];
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
  if ([childController isKindOfClass:[UICollectionViewController class]]) {
    [[(UICollectionViewController *)childController collectionView].panGestureRecognizer removeTarget:self action:NULL];
  }
  if (index < self.currentChildIndex && self.currentChildIndex > 0) {
    self.currentChildIndex--;
  }
  if (self.shouldDebug) DLog(@"Cleared index: %d", index);
  return YES;
}

- (BOOL)updateChildViewControllerTilingIfNeeded
{
  if (!self.pagingEnabled || !self.pagingDelegate) {
    return NO;
  }
  [self cleanChildViewControllers];
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
  UIViewController *destinationViewController = nil;
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
  //-- Scrolling conflict resolution.
  //-- TODO: Also: Try alternative with `requireGestureRecognizerToFail:`.
  //-- TODO: Finally: Handle `nextView`.
  if ([gesture.view isKindOfClass:[UIScrollView class]]) {
    if (self.previousView) {
      UIScrollView *scrollView = (id)gesture.view;
      CGPoint velocity = [gesture velocityInView:gesture.view];
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
      if (self.shouldDebug) DLog(@"%f", [gesture velocityInView:gesture.view].y);
      BOOL shouldDismiss = ((isHorizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y) <= 0.0f
                            && (isHorizontal ? velocity.x : velocity.y) > 0.0f); //-- NOTE: Refactor with `velocityValue` as needed.
      if (!shouldDismiss && !(self.flags & FlagIsStealingPan)) {
        return;
      } else if (gesture.state == UIGestureRecognizerStateBegan) {
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
      return;
    }
  }
  //-- Only handle supported directions.
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
  //-- Check delegates.
  destinationViewController = (translationValue < 0) ? self.nextViewController : self.previousViewController;
  if (![self delegateShouldNavigateToViewController:destinationViewController]) {
    return;
  }
  //-- /Guards.
  if (gesture.state == UIGestureRecognizerStateBegan && self.shouldDelegatePossibleAppearanceChanges) {
    [self delegateWillTransitionToViewController:destinationViewController maybe:YES animated:YES];
  }
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
    CGPoint initialCenter = self.currentView.center;
    CGPoint currentCenter = CGPointMake(isHorizontal ? (initialCenter.x + translation.x) : initialCenter.x,
                                        isHorizontal ? initialCenter.y : (initialCenter.y + translation.y));
    CGFloat currentSide   = isHorizontal ? self.currentView.width : self.currentView.height;
    CGFloat containerSide = isHorizontal ? self.containerView.width : self.containerView.height;
    CGPoint (^makeFinalCenter)(UIView *) = ^(UIView *view) {
      return CGPointMake(isHorizontal ? (view.center.x + translation.x) : view.center.x,
                         isHorizontal ? view.center.y : (view.center.y + translation.y));
    };
    CGPoint (^makeFinalOffsetForCurrentView)(NSInteger) = ^(NSInteger direction) {
      return CGPointMake(isHorizontal ? (initialCenter.x - direction * self.currentView.width) : initialCenter.x,
                         isHorizontal ? initialCenter.y : (initialCenter.y - direction * self.currentView.height));
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
      [self delegateWillTransitionToViewController:destinationViewController maybe:NO animated:YES];
      handleDidShow = ^(BOOL finished) {
        [self delegateDidTransitionToViewController:destinationViewController animated:YES];
        //-- Extra.
        [self updateChildViewControllerTilingIfNeeded];
      };
    }
    UIViewAnimationOptions easingOptions = (ABS(translationValue) > 300.0f && (finishedPanToNext || finishedPanToPrevious))
    ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseInOut;
    if (finishedPanToNext) {
      //-- Layout and animate from midway.
      CGPoint previousOffset = makeFinalOffsetForCurrentView(1);
      CGPoint nextCenter = makeFinalCenter(self.nextView);
      self.currentView.center = currentCenter;
      self.nextView.center = nextCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = previousOffset;
        self.nextView.center = initialCenter;
      };
      self.currentChildIndex++;
      [UIView animateWithDuration:finishDuration delay:0.0f options:easingOptions
                       animations:finishLayout completion:handleDidShow];
    } else if (finishedPanToPrevious) {
      //-- Layout and animate from midway.
      CGPoint nextOffset = makeFinalOffsetForCurrentView(-1);
      CGPoint previousCenter = makeFinalCenter(self.previousView);
      self.currentView.center = currentCenter;
      self.previousView.center = previousCenter;
      void (^finishLayout)(void) = ^{
        self.currentView.center = nextOffset;
        self.previousView.center = initialCenter;
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
  return !([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]
           && [otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]);
}

@end
