//
//  MetalViewDelegate.h
//  DoFRendering
//
//  Created by Bartłomiej Nowak on 10/11/2018.
//  Copyright © 2018 Bartłomiej Nowak. All rights reserved.
//

#ifndef MetalViewDelegate_h
#define MetalViewDelegate_h

@import Foundation;
#import "MetalView.h"

@protocol MetalViewDelegate <NSObject>
-(void)drawToDrawable:(id<CAMetalDrawable>)drawable ofSize:(CGSize)drawableSize frameDuration:(float)frameDuration;
-(void)frameAdjustedForView:(MetalView*)view;
@end

#endif /* MetalViewDelegate_h */
