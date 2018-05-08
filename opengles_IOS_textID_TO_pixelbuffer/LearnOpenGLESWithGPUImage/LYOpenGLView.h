//
//  ViewController.m
//
//

#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface LYOpenGLView : UIView {
    CVOpenGLESTextureCacheRef videoTextureCache;
    CVOpenGLESTextureRef lumaTexture;
}

#define __TEXTID__  1

@property (nonatomic , assign) BOOL isFullYUVRange;

@property (nonatomic, readonly) CVOpenGLESTextureCacheRef videoTextureCache;

@property (nonatomic, readonly)CVOpenGLESTextureRef lumaTexture;
//CVOpenGLESTextureCacheRef _videoTextureCache;

//CVOpenGLESTextureRef _lumaTexture;

//@property (nonatomic , assign) BOOL isFullYUVRange;

- (void)setupGL;
//- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)displayPixelBuffer:(GLuint)texID;
//- (void)displayPixelBuffer:(CVOpenGLESTextureRef ) textureRef;


-(void)makeCurrentContext;
-(EAGLContext *)getCurrentContext;

@end
