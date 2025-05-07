//
//  FLEXHierarchyViewController.h
//  FLEX
//
//  Created by Tanner Bennett on 1/9/20.
//  Copyright © 2020 FLEX Team. All rights reserved.
//
// 遇到问题联系中文翻译作者：pxx917144686

#import "FLEXNavigationController.h"

@protocol FLEXHierarchyDelegate <NSObject>
- (void)viewHierarchyDidDismiss:(UIView *)selectedView;
@end

@interface FLEXHierarchyViewController : FLEXNavigationController

+ (instancetype)delegate:(id<FLEXHierarchyDelegate>)delegate;
+ (instancetype)delegate:(id<FLEXHierarchyDelegate>)delegate
              viewsAtTap:(NSArray<UIView *> *)viewsAtTap
            selectedView:(UIView *)selectedView;

- (void)toggleHierarchyMode;

@property (nonatomic, readonly) UIView *selectedView;

@end
