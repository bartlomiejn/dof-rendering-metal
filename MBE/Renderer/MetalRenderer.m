//
//  MetalRenderer.m
//  MBE
//
//  Created by Bartłomiej Nowak on 15/11/2017.
//  Copyright © 2017 Bartłomiej Nowak. All rights reserved.
//
//  Includes code taken from Metal By Example book repository at: https://github.com/metal-by-example/sample-code
//

#import "MetalRenderer.h"
#import "MathFunctions.h"
#import "OBJMesh.h"
#import "ShaderTypes.h"
#import "RenderStateProvider.h"
#import <simd/simd.h>
@import Metal;
@import QuartzCore.CAMetalLayer;

typedef uint16_t MetalIndex;
const MTLIndexType MetalIndexType = MTLIndexTypeUInt16;
static const NSInteger inFlightBufferCount = 3;

typedef struct __attribute((packed)) {
    vector_float4 position;
    vector_float4 color;
} MetalVertex;

typedef struct __attribute((packed)) {
    matrix_float4x4 modelMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 projectionMatrix;
} RenderObjectUniforms;

@interface MetalRenderer ()
@property (strong) id<MTLDevice> device;
@property (strong) OBJMesh *mesh;
@property (strong) NSMutableArray<id<MTLBuffer>> *uniformBuffers;
@property (strong) id<MTLCommandQueue> commandQueue;
@property (strong, nonatomic) RenderStateProvider *renderStateProvider;
@property (strong) id<MTLTexture> renderObjectsTexture;
@property (strong) id<MTLTexture> depthTexture;
@property (strong) id<MTLDepthStencilState> depthStencilState;
@property (strong) dispatch_semaphore_t displaySemaphore;
@property (assign) NSInteger bufferIndex;
@property (assign) float rotationX, rotationY, rotationZ, time;
@end

@implementation MetalRenderer

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _device = device;
        _displaySemaphore = dispatch_semaphore_create(inFlightBufferCount);
        _commandQueue = [_device newCommandQueue];
        _renderStateProvider = [[RenderStateProvider alloc] initWithDevice:_device];
        
        int teapotCount = 2;
        _uniformBuffers = [[NSMutableArray alloc] init];
        for (int i = 0; i < teapotCount; i++) {
            id<MTLBuffer> uniformBuffer = [_device newBufferWithLength:sizeof(RenderObjectUniforms) * inFlightBufferCount
                                                               options:MTLResourceOptionCPUCacheModeDefault];
            uniformBuffer.label = @"Uniforms";
            [_uniformBuffers addObject:uniformBuffer];
        }
    }
    return self;
}

- (void)setupMeshFromOBJGroup:(OBJGroup*)group {
    _mesh = [[OBJMesh alloc] initWithGroup:group device:_device];
}

#pragma mark - MetalViewDelegate

- (void)drawInView:(MetalView *)view {
    dispatch_semaphore_wait(self.displaySemaphore, DISPATCH_TIME_FOREVER);
    
    [self updateUniformsForView:view duration:view.frameDuration];
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        self.bufferIndex = (self.bufferIndex + 1) % inFlightBufferCount;
        dispatch_semaphore_signal(self.displaySemaphore);
    }];
    
    id<MTLCaptureScope> scope = [[MTLCaptureManager sharedCaptureManager] newCaptureScopeWithDevice:self.device];
    scope.label = @"Capture Scope";
    [scope beginScope];
    
    [self renderObjectsInView:view withCommandBuffer:commandBuffer];
    [self applyBloomInView:view withCommandBuffer:commandBuffer];
    [commandBuffer presentDrawable:view.currentDrawable];
    
    [scope endScope];
    
    [commandBuffer commit];
}

- (void)renderObjectsInView:(MetalView *)view withCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *descriptor = [self renderObjectsPassDescriptorForView:view];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    [encoder setRenderPipelineState:_renderStateProvider.renderObjectsPipelineState];
    [encoder setDepthStencilState:_renderStateProvider.depthStencilState];
    [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [encoder setCullMode:MTLCullModeBack];
    [encoder setVertexBuffer:self.mesh.vertexBuffer offset:0 atIndex:0];
    const NSUInteger uniformBufferOffset = sizeof(RenderObjectUniforms) * self.bufferIndex;
    for (int i = 0; i < self.uniformBuffers.count; i++) {
        [encoder setVertexBuffer:self.uniformBuffers[i] offset:uniformBufferOffset atIndex:1];
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                            indexCount:[self.mesh.indexBuffer length] / sizeof(MetalIndex)
                             indexType:MetalIndexType
                           indexBuffer:self.mesh.indexBuffer
                     indexBufferOffset:0];
    }
    [encoder endEncoding];
}

- (void)applyBloomInView:(MetalView *)view withCommandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    MTLRenderPassDescriptor *descriptor = [self applyBloomPassDescriptorForView:view];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    [encoder setRenderPipelineState:_renderStateProvider.applyBloomPipelineState];
    [encoder setFragmentTexture:self.renderObjectsTexture atIndex:0];
    [encoder setFragmentTexture:self.depthTexture atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
}

- (void)frameAdjustedForView:(MetalView *)view {
    [self setupRenderObjectsTextureForView:view];
    [self setupDepthTextureForView:view];
}

- (void)updateUniformsForView:(MetalView *)view duration:(NSTimeInterval)duration {
    self.time += duration;
    self.rotationX += duration * (M_PI / 2);
    self.rotationY += duration * (M_PI / 3);
    self.rotationZ = 0;
    
    const NSUInteger uniformBufferOffset = sizeof(RenderObjectUniforms) * self.bufferIndex;
    
    for (int i = 0; i < _uniformBuffers.count; i++) {
        RenderObjectUniforms uniforms;
        uniforms.modelMatrix = [self modelMatrixForTeapotIndex:i];
        uniforms.viewMatrix = [self viewMatrix];
        uniforms.projectionMatrix = [self projectionMatrixForView:view];
        memcpy([self.uniformBuffers[i] contents] + uniformBufferOffset, &uniforms, sizeof(uniforms));
    }
}

- (matrix_float4x4)modelMatrixForTeapotIndex:(int)index {
    const vector_float3 translation = { index*1, index*1.4, -index*6 };
    const matrix_float4x4 transMatrix = matrix_float4x4_translation(translation);
    const vector_float3 xAxis = { 1, 0, 0 };
    const vector_float3 yAxis = { 0, 1, 0 };
    const vector_float3 zAxis = { 0, 0, 1 };
    const matrix_float4x4 xRot = matrix_float4x4_rotation(xAxis, self.rotationX);
    const matrix_float4x4 yRot = matrix_float4x4_rotation(yAxis, self.rotationY);
    const matrix_float4x4 zRot = matrix_float4x4_rotation(zAxis, self.rotationZ);
    const matrix_float4x4 rotMatrix = matrix_multiply(matrix_multiply(xRot, yRot), zRot);
    float scaleFactor = sinf(5 * self.time) * 0.5 + 3;
    const matrix_float4x4 scaleMatrix = matrix_float4x4_uniform_scale(scaleFactor);
    const matrix_float4x4 modelMatrix = matrix_multiply(matrix_multiply(transMatrix, rotMatrix), scaleMatrix);
    return modelMatrix;
}

- (matrix_float4x4)viewMatrix {
    const vector_float3 cameraTranslation = { 0, 0, -5 };
    const matrix_float4x4 viewMatrix = matrix_float4x4_translation(cameraTranslation);
    return viewMatrix;
}

- (matrix_float4x4)projectionMatrixForView:(MetalView *)view {
    const CGSize drawableSize = view.metalLayer.drawableSize;
    const float aspect = drawableSize.width / drawableSize.height;
    const float fov = (2 * M_PI) / 5;
    const float near = 1;
    const float far = 100;
    const matrix_float4x4 projectionMatrix = matrix_float4x4_perspective(aspect, fov, near, far);
    return projectionMatrix;
}

- (MTLRenderPassDescriptor *)renderObjectsPassDescriptorForView:(MetalView*)view {
    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = self.renderObjectsTexture;
    passDescriptor.colorAttachments[0].clearColor = view.clearColor;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.depthAttachment.texture = self.depthTexture;
    passDescriptor.depthAttachment.clearDepth = 1.0;
    passDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
    passDescriptor.depthAttachment.storeAction = MTLStoreActionStore;
    passDescriptor.renderTargetWidth = view.metalLayer.drawableSize.width;
    passDescriptor.renderTargetHeight = view.metalLayer.drawableSize.height;
    return passDescriptor;
}

- (MTLRenderPassDescriptor *)applyBloomPassDescriptorForView:(MetalView*)view {
    MTLRenderPassDescriptor *passDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    passDescriptor.colorAttachments[0].texture = [view.currentDrawable texture];
    passDescriptor.colorAttachments[0].clearColor = view.clearColor;
    passDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    passDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad;
    passDescriptor.renderTargetWidth = view.metalLayer.drawableSize.width;
    passDescriptor.renderTargetHeight = view.metalLayer.drawableSize.height;
    return passDescriptor;
}

- (void)setupRenderObjectsTextureForView:(MetalView *)view {
    CGSize drawableSize = view.metalLayer.drawableSize;
    
    if (self.renderObjectsTexture.width != drawableSize.width
        || self.renderObjectsTexture.height != drawableSize.height) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                        width:drawableSize.width
                                                                                       height:drawableSize.height
                                                                                    mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget & MTLTextureUsageShaderRead;
        self.renderObjectsTexture = [self.device newTextureWithDescriptor:desc];
    }
}

- (void)setupDepthTextureForView:(MetalView *)view {
    CGSize drawableSize = view.metalLayer.drawableSize;
    
    if (self.depthTexture.width != drawableSize.width || self.depthTexture.height != drawableSize.height) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                        width:drawableSize.width
                                                                                       height:drawableSize.height
                                                                                    mipmapped:NO];
        desc.usage = MTLTextureUsageRenderTarget & MTLTextureUsageShaderRead;
        self.depthTexture = [self.device newTextureWithDescriptor:desc];
    }
}

@end
