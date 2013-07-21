//
//  UAFInteractiveNavigationController.h
//  RhymesGesturalNavigationControllerProof
//
//  Created by Peng Wang on 6/7/13.
//  Copyright (c) 2013 Everynone. All rights reserved.
//

#import <UIKit/UIKit.h>

//-- TODO: Finally: Check for leaks.
//-- TODO: Finally: Update project info.
//-- TODO: Eventually: Prepare for publishing.
//-- TODO: Finally: Document.

#import <UAFToolkit/Utility.h>
#import <UAFToolkit/UIKit.h>
#import <UAFToolkit/Navigation.h>
#import <UAFToolkit/UAFViewController.h>
#import <UAFToolkit/UAFInertialViewController.h>

/**
 `UAFInteractiveNavigationController` mirrors `UINavigationController` behavior,
 but combines it with the scroll-and-snap transition behavior of
 `UIPageViewController`. It is meant for apps not using the custom
 view-controller transitions iOS7.
 
 Some requirements: it implements the interfaces found in the
 [`UAFToolkit`](https://github.com/UseAllFive/UAFToolkit) library. It inherits
 from the latter's boilerplate view-controller class as well, to make itself
 nest-able. It also makes use of the utilities and ui-related extensions from
 the latter. So, it doesn't require all of UAFToolkit, just some 'modules'. When
 adding the navigation-controller and if using the
 view-controller-identifier-based API, the navigation-controller must share the
 same storyboard with the child-controller.
 
 This component is a full implementation of `UAFNavigationController`, including
 the paging mode. Defaults:
 
 - `baseNavigationDirection` - `UAFNavigationDirectionHorizontal`
 - `baseNavigationDuration` - `0.8f`
 - `bounces` - `YES`
 - `pagingEnabled` - `NO`
 
 ## Imperative (Programmatic) Navigation
 
 The controller can perform imperative navigation operations like pushing and
 popping, which are not interactive. Once started, they cannot be cancelled. The
 controller can also pop to non-immediate siblings and reset its entire
 child-controller stack.
 
 ## Interactive Navigation
 
 Interactive navigation refers to being able to pan and navigate between child
 view-controllers, much like `UIPageViewController`'s scroll-and-snap navigation
 and `UIScrollView`'s behavior when `pagingEnabled`. Navigation follows gesture,
 so it can be cancelled.
 
 ## Implementation Highlights
 
 - <addChildViewController:animated:focused:next:>
 - <popViewControllerAnimated:focused:>
 - <popToViewController:animated:>
 - <setViewControllers:animated:focused:>
 - <cleanChildViewControllers>
 - <handleRemoveChildViewController:>
 - <updateChildViewControllerTilingIfNeeded>
 - <handlePan:>
 
 @note 'Other Methods' and 'Extension Methods' list entirely private API whose
 documentation is mainly for development.
 */
@interface UAFInteractiveNavigationController : UAFViewController

<UAFNavigationController, UAFInertialViewController,
UIGestureRecognizerDelegate>

/** @name Public API */

/** 
 The containing view for this container-view-controller.
 
 It stretches to fit the view and is intended to fill the screen. Its children
 are intended to fill its bounds.
 */
@property (strong, nonatomic, readonly) UIView *containerView;
/**
 The gesture recognizer for the interactive navigation. 
 
 This is exposed mainly because it's useful for referencing recognizer
 properties like `state`.
 */
@property (strong, nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;

/**
 Inversely affects duration for the finish transition. Default is `2.0f`.
 
 When the interactive navigation will 'complete' or 'revert', the animation
 duration is calculated based on the translation and velocity in relation to the
 total required distance. That quotient is then dampened by this factor.
 */
@property (nonatomic) CGFloat finishTransitionDurationFactor;
/**
 Exactly as it says. Default is `0.4f` seconds.
 
 See <finishTransitionDurationFactor> for context. When doing a finish
 transition, the duration resulting from <finishTransitionDurationFactor>'s
 dampening is then checked against this minimum.
 */
@property (nonatomic) NSTimeInterval finishTransitionDurationMinimum;

/**
 Will scroll scrollable child-controllers appropriately before performing any
 animated navigation.
 
 When pushing from a scrolling controller, the latter scrolls to its bottom
 edge. When popping from a scrolling controller, the latter scrolls to its top
 edge.
 */
@property (nonatomic) BOOL shouldResetScrollViews;

@end
