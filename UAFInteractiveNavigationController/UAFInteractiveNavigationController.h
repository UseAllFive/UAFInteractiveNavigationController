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
#import <UAFToolkit/Boilerplate.h>
#import <UAFToolkit/UI.h>

/**
 TODO: Document.
 */
@interface UAFInteractiveNavigationController : UAFViewController

<UAFNavigationController, UAFInertialViewController,
UIGestureRecognizerDelegate>

@property (strong, nonatomic, readonly) UIView *containerView;
@property (strong, nonatomic, readonly) UIPanGestureRecognizer *panGestureRecognizer;

@property (nonatomic) NSTimeInterval finishTransitionDurationFactor;
@property (nonatomic) NSTimeInterval finishTransitionDurationMinimum;

@property (nonatomic) BOOL shouldResetScrollViews;

@end
