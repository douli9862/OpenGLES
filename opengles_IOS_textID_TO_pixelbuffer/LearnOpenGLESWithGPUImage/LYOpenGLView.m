//
//  ViewController.m
//  LearnOpenGLESWithGPUImage
//
//

#import "LYOpenGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <GLKit/GLKit.h>

// Uniform index.
enum
{
	UNIFORM_Y,
	UNIFORM_UV,
    UNIFORM_BGRA,
	UNIFORM_COLOR_CONVERSION_MATRIX,
	NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
	ATTRIB_VERTEX,
	ATTRIB_TEXCOORD,
	NUM_ATTRIBUTES
};

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
		1.164,  1.164, 1.164,
		  0.0, -0.392, 2.017,
		1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
		1.164,  1.164, 1.164,
		  0.0, -0.213, 2.112,
		1.793, -0.533,   0.0,
};

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
const GLfloat kColorConversion601FullRange[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};


@interface LYOpenGLView ()
{
	// The pixel dimensions of the CAEAGLLayer.
	GLint _backingWidth;
	GLint _backingHeight;

	EAGLContext *_context;
	//CVOpenGLESTextureRef _lumaTexture;
	CVOpenGLESTextureRef _chromaTexture;
	//CVOpenGLESTextureCacheRef _videoTextureCache;
	
	GLuint _frameBufferHandle;
	GLuint _colorBufferHandle;
	
	const GLfloat *_preferredConversion;
    
    //add by zhixin
    GLuint                  movieFramebuffer;
    GLuint                  movieRenderbuffer;
    CVPixelBufferRef        renderTarget;
    CVOpenGLESTextureRef    renderTexture;
}

@property GLuint program;

- (void)setupBuffers;
- (void)cleanUpTextures;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation LYOpenGLView

@synthesize videoTextureCache = _videoTextureCache;

@synthesize  lumaTexture = _lumaTexture;

+ (Class)layerClass
{
	return [CAEAGLLayer class];
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super initWithCoder:aDecoder]))
	{
		self.contentScaleFactor = [[UIScreen mainScreen] scale];

		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

		eaglLayer.opaque = TRUE;
		eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
										  kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};

		_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

		if (!_context || ![EAGLContext setCurrentContext:_context] || ![self loadShaders]) {
			return nil;
		}
		
		_preferredConversion = kColorConversion709;
	}
	return self;
}

# pragma mark - OpenGL setup

-(void)makeCurrentContext
{
    [EAGLContext setCurrentContext:_context];
}

-(EAGLContext *)getCurrentContext {
    return _context;
}

- (void)setupGL
{
	[EAGLContext setCurrentContext:_context];
	[self setupBuffers];
	[self loadShaders];
	
	glUseProgram(self.program);
	
	//glUniform1i(uniforms[UNIFORM_Y], 0);
	//glUniform1i(uniforms[UNIFORM_UV], 1);
    
    //glUniform1i(uniforms[UNIFORM_BGRA], 3);
	
	//glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
	
	// Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
	if (!_videoTextureCache) {
		CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
		if (err != noErr) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
			return;
		}
	}
}

#pragma mark - Utilities

- (void)setupBuffers
{
	glDisable(GL_DEPTH_TEST);
	
	glEnableVertexAttribArray(ATTRIB_VERTEX);
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
	
	glEnableVertexAttribArray(ATTRIB_TEXCOORD);
	glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
	
	glGenFramebuffers(1, &_frameBufferHandle);
	glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
	
	glGenRenderbuffers(1, &_colorBufferHandle);
	glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
	
	[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);

	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	}
}

- (void)cleanUpTextures
{
	if (_lumaTexture) {
		CFRelease(_lumaTexture);
		_lumaTexture = NULL;
	}
	
	if (_chromaTexture) {
		CFRelease(_chromaTexture);
		_chromaTexture = NULL;
	}
	
	// Periodic texture cache flush every frame
	CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
}

- (void)dealloc
{
	[self cleanUpTextures];
	
	if(_videoTextureCache) {
		CFRelease(_videoTextureCache);
	}
}

- (void)setFilterFBO;
{
    [self makeCurrentContext];
    if (!movieFramebuffer) {
        [self createDataFBO];
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, movieFramebuffer);
    
    glViewport(0, 0, _backingWidth, _backingWidth);
}

- (void)createDataFBO
{
    glActiveTexture(GL_TEXTURE2);
    glGenFramebuffers(1, &movieFramebuffer);
    
    NSLog(@"createDataFBO movieFramebuffer:%d\n", movieFramebuffer);
    GLenum err =  glGetError();
    if(err != 0) {
        NSLog(@"err:%d\n", err);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, movieFramebuffer);
    
    NSDictionary* pixelBufferOptions = @{ (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                          (NSString*) kCVPixelBufferWidthKey : @(_backingWidth),
                                          (NSString*) kCVPixelBufferHeightKey : @(_backingHeight),
                                          (NSString*) kCVPixelBufferOpenGLESCompatibilityKey : @YES,
                                          (NSString*) kCVPixelBufferIOSurfacePropertiesKey : @{}};
    
    CVPixelBufferCreate(kCFAllocatorDefault, _backingWidth, _backingHeight, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)pixelBufferOptions, &renderTarget);
    
    // http://allmybrain.com/2011/12/08/rendering-to-a-texture-with-ios-5-texture-cache-api/
    
//CVPixelBufferPoolCreatePixelBuffer(NULL, [assetWriterPixelBufferInput pixelBufferPool], &renderTarget);
    
    /* AVAssetWriter will use BT.601 conversion matrix for RGB to YCbCr conversion
     * regardless of the kCVImageBufferYCbCrMatrixKey value.
     * Tagging the resulting video file as BT.601, is the best option right now.
     * Creating a proper BT.709 video is not possible at the moment.
     */
    CVBufferSetAttachment(renderTarget, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(renderTarget, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(renderTarget, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    
    CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                 _videoTextureCache,
                                                 renderTarget,
                                                 NULL, // texture attributes
                                                 GL_TEXTURE_2D,
                                                 GL_RGBA, // opengl format
                                                 _backingWidth,
                                                 _backingHeight,
                                                 GL_BGRA, // native iOS format
                                                 GL_UNSIGNED_BYTE,
                                                 0,
                                                 &renderTexture);
    
    glBindTexture(CVOpenGLESTextureGetTarget(renderTexture), CVOpenGLESTextureGetName(renderTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(renderTexture), 0);

    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSLog(@"status:%u\n", status);
}

#pragma mark - OpenGLES drawing


#if __TEXTID__
- (void)displayPixelBuffer:(GLuint)texID
{
    CVReturn err;
    [self setFilterFBO];
      
    //glActiveTexture(GL_TEXTURE0);
    
    glActiveTexture(GL_TEXTURE3);
        
       
    //GLuint texID = CVOpenGLESTextureGetName(textureRef);
    glBindTexture(GL_TEXTURE_2D, texID);
    
    glUniform1i(uniforms[UNIFORM_BGRA], 3); //add by zhixin
    
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);


    // Set the view port to the entire view.
    glViewport(0, 0, _backingWidth, _backingHeight);
    
    //glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
    glClearColor(0.1f, 1.0f, 0.5f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    
    // Use shader program.
    glUseProgram(self.program);
    
    static const GLfloat quadVertexData[] = {
        -1.0f, -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, 1.0f, 1.0f,
    };
    
    // 更新顶点数据
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    GLfloat quadTextureData[] =  { // 正常坐标
        0, 0,
        1, 0,
        0, 1,
        1, 1
    };
    
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glFinish();
    
    NSLog(@"1111\n");
}

#else
- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	CVReturn err;
    [self setFilterFBO];
    
	if (pixelBuffer != NULL) {
        CVPixelBufferLockBaseAddress(pixelBuffer,
                                     kCVPixelBufferLock_ReadOnly);
        
		int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
		int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
		
		if (!_videoTextureCache) {
			NSLog(@"No video texture cache");
			return;
		}
        if ([EAGLContext currentContext] != _context) {
            [EAGLContext setCurrentContext:_context]; // 非常重要的一行代码
        }
		[self cleanUpTextures];
		
    
		glActiveTexture(GL_TEXTURE0);
        
        OSType type = CVPixelBufferGetPixelFormatType(pixelBuffer);
        if(kCVPixelFormatType_32BGRA == type) {
            err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                         _videoTextureCache,
                                                         pixelBuffer,
                                                         NULL,
                                                         GL_TEXTURE_2D,
                                                         GL_RGBA,
                                                         frameWidth,
                                                         frameHeight,
                                                         GL_BGRA,
                                                         GL_UNSIGNED_BYTE,
                                                         0,
                                                         &_lumaTexture);
            if (err) {
                NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
            }
            
            glBindTexture(GL_TEXTURE_2D,
                          CVOpenGLESTextureGetName(_lumaTexture));
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            
            
        } else if(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == type ) {
            //[self drawNV21:pixelBuffer forWidth:frameWidth forHeight:frameHeight];
        }
		
        CVPixelBufferUnlockBaseAddress(pixelBuffer,
                                       kCVPixelBufferLock_ReadOnly);
        
		//glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
		
		// Set the view port to the entire view.
		glViewport(0, 0, _backingWidth, _backingHeight);
	}
	
	glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	 
	// Use shader program.
	glUseProgram(self.program);
	
    static const GLfloat quadVertexData[] = {
        -1.0f, -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, 1.0f, 1.0f,
    };

	
	// 更新顶点数据
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
	glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    GLfloat quadTextureData[] =  { // 正常坐标
        0, 0,
        1, 0,
        0, 1,
        1, 1
    };
	
	glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
	glEnableVertexAttribArray(ATTRIB_TEXCOORD);
	
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);


    
	//glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glFinish();
    
//    if ([EAGLContext currentContext] == _context) {
//        [_context presentRenderbuffer:GL_RENDERBUFFER];
//    }
    NSLog(@"1111\n");
}
#endif

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
	GLuint vertShader, fragShader;
	NSURL *vertShaderURL, *fragShaderURL;
	
	
	self.program = glCreateProgram();
	
	// Create and compile the vertex shader.
	vertShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"vsh"];
	if (![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL]) {
		NSLog(@"Failed to compile vertex shader");
		return NO;
	}
	
	// Create and compile fragment shader.
	fragShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"fsh"];
	if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL]) {
		NSLog(@"Failed to compile fragment shader");
		return NO;
	}
	
	// Attach vertex shader to program.
	glAttachShader(self.program, vertShader);
	
	// Attach fragment shader to program.
	glAttachShader(self.program, fragShader);
	
	// Bind attribute locations. This needs to be done prior to linking.
	glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
	//glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
    //inputTextureCoordinate
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "inputTextureCoordinate");
	
	// Link the program.
	if (![self linkProgram:self.program]) {
		NSLog(@"Failed to link program: %d", self.program);
		
		if (vertShader) {
			glDeleteShader(vertShader);
			vertShader = 0;
		}
		if (fragShader) {
			glDeleteShader(fragShader);
			fragShader = 0;
		}
		if (self.program) {
			glDeleteProgram(self.program);
			self.program = 0;
		}
		
		return NO;
	}
	
	// Get uniform locations.
	//uniforms[UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
	//uniforms[UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    //inputImageTexture
    uniforms[UNIFORM_BGRA] = glGetUniformLocation(self.program, "inputImageTexture");
    
	//uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
	
	// Release vertex and fragment shaders.
	if (vertShader) {
		glDetachShader(self.program, vertShader);
		glDeleteShader(vertShader);
	}
	if (fragShader) {
		glDetachShader(self.program, fragShader);
		glDeleteShader(fragShader);
	}
	
	return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
		NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
	GLint status;
	const GLchar *source;
	source = (GLchar *)[sourceString UTF8String];
	
	*shader = glCreateShader(type);
	glShaderSource(*shader, 1, &source, NULL);
	glCompileShader(*shader);
	
#if defined(DEBUG)
	GLint logLength;
	glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetShaderInfoLog(*shader, logLength, &logLength, log);
		NSLog(@"Shader compile log:\n%s", log);
		free(log);
	}
#endif
	
	glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	if (status == 0) {
		glDeleteShader(*shader);
		return NO;
	}
	
	return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
	GLint status;
	glLinkProgram(prog);
	
#if defined(DEBUG)
	GLint logLength;
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program link log:\n%s", log);
		free(log);
	}
#endif
	
	glGetProgramiv(prog, GL_LINK_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
	GLint logLength, status;
	
	glValidateProgram(prog);
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program validate log:\n%s", log);
		free(log);
	}
	
	glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}



@end

