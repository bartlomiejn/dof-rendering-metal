//
//  AppDelegate.m
//  DoFRendering
//
//  Created by Bartłomiej Nowak on 03/11/2017.
//  Copyright © 2017 Bartłomiej Nowak. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewportViewController.h"
#import "MetalRenderer.h"
#import "DrawObjectsPassEncoder.h"
#import "CircleOfConfusionPassEncoder.h"
#import "PreFilterPassEncoder.h"
#import "BokehPassEncoder.h"
#import "PostFilterPassEncoder.h"
#import "ComposePassEncoder.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

-(BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [self viewControllerWithDevice:device
                                                           renderer:[self metalRendererForDevice:device]];
    [self.window makeKeyAndVisible];
    return true;
}

-(ViewportViewController*)viewControllerWithDevice:(id<MTLDevice>)device renderer:(MetalRenderer*)renderer
{
    ViewportViewController *controller = [[ViewportViewController alloc] initWithDevice:device renderer:renderer];
    controller.presenter = [[ViewportPresenter alloc] initWithMeshLoader:[[OBJMeshLoader alloc] initWithDevice:device]
                                                   transformationBuilder:[[ModelTransformationBuilder alloc] init]];
    controller.presenter.view = controller;
    return controller;
}

-(MetalRenderer*)metalRendererForDevice:(id<MTLDevice>)device
{
    DrawObjectsPassEncoder* drawObjectsEncoder = [[DrawObjectsPassEncoder alloc] initWithDevice:device];
    CircleOfConfusionPassEncoder* cocEncoder = [[CircleOfConfusionPassEncoder alloc] initWithDevice:device];
    PreFilterPassEncoder* preFilterEncoder = [[PreFilterPassEncoder alloc] initWithDevice:device];
    BokehPassEncoder* bokehEncoder = [[BokehPassEncoder alloc] initWithDevice:device];
    PostFilterPassEncoder* postFilterEncoder = [[PostFilterPassEncoder alloc] initWithDevice:device];
    ComposePassEncoder* composeEncoder = [[ComposePassEncoder alloc] initWithDevice:device];
    MetalRenderer* renderer = [[MetalRenderer alloc] initWithDevice:device
                                                 drawObjectsEncoder:drawObjectsEncoder
                                                         cocEncoder:cocEncoder
                                                   preFilterEncoder:preFilterEncoder
                                                       bokehEncoder:bokehEncoder
                                                  postFilterEncoder:postFilterEncoder
                                                     composeEncoder:composeEncoder];
    renderer.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    return renderer;
}

@end
