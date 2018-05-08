//
//  ViewController.m
//  LearnOpenGLESWithGPUImage

#import "ViewController.h"
#import "LYOpenGLView.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/ALAssetsLibrary.h>

@interface ViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic , strong) UILabel  *mLabel;
@property (nonatomic , strong) AVCaptureSession *mCaptureSession; //负责输入和输出设备之间的数据传递
@property (nonatomic , strong) AVCaptureDeviceInput *mCaptureDeviceInput;//负责从AVCaptureDevice获得输入数据
@property (nonatomic , strong) AVCaptureVideoDataOutput *mCaptureDeviceOutput; //

// OpenGL ES
@property (nonatomic , strong)  LYOpenGLView *mGLView;

@end


@implementation ViewController
{
    dispatch_queue_t mProcessQueue;
    
    dispatch_queue_t mDrawQueue;
    
    EAGLContext *_context;
    
    CVOpenGLESTextureCacheRef _videoTextureCache;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.mGLView = (LYOpenGLView *)self.view;
    [self.mGLView setupGL];
    
    self.mCaptureSession = [[AVCaptureSession alloc] init];
    self.mCaptureSession.sessionPreset = AVCaptureSessionPreset640x480;
    
    mProcessQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    
    mDrawQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    AVCaptureDevice *inputCamera = nil;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *device in devices)
    {
        if ([device position] == AVCaptureDevicePositionFront)
        {
            inputCamera = device;
        }
    }
    
    self.mCaptureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:inputCamera error:nil];
    
    if ([self.mCaptureSession canAddInput:self.mCaptureDeviceInput]) {
        [self.mCaptureSession addInput:self.mCaptureDeviceInput];
    }

    
    self.mCaptureDeviceOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.mCaptureDeviceOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    self.mGLView.isFullYUVRange = YES;
    [self.mCaptureDeviceOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:/*kCVPixelFormatType_420YpCbCr8BiPlanarFullRange*/kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    [self.mCaptureDeviceOutput setSampleBufferDelegate:self queue:mProcessQueue];
    if ([self.mCaptureSession canAddOutput:self.mCaptureDeviceOutput]) {
        [self.mCaptureSession addOutput:self.mCaptureDeviceOutput];
    }
    
    AVCaptureConnection *connection = [self.mCaptureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    
    
    [self.mCaptureSession startRunning];
    

    self.mLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 100, 100)];
    self.mLabel.textColor = [UIColor redColor];
    [self.view addSubview:self.mLabel];
}



- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    static long frameID = 0;
    ++frameID;
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    if(nil == _context) {
        EAGLSharegroup  *sharegroup_ = [[self.mGLView getCurrentContext] sharegroup];
        
        _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup: sharegroup_];
        
        if (!_videoTextureCache) {
            CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
            if (err != noErr) {
                NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
                return;
            }
        }
    }

    
#if __TEXTID__
    
    CVPixelBufferLockBaseAddress(pixelBuffer,
                                 kCVPixelBufferLock_ReadOnly);
    
    int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
    int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
    
    
    glActiveTexture(GL_TEXTURE3);
    GLenum error = glGetError();
    CVOpenGLESTextureCacheRef texCacheRef = _videoTextureCache;
    CVOpenGLESTextureRef texRef ;//= [self.mGLView lumaTexture];
    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                texCacheRef,
                                                                pixelBuffer,
                                                                NULL,
                                                                GL_TEXTURE_2D,
                                                                GL_RGBA,
                                                                frameWidth,
                                                                frameHeight,
                                                                GL_BGRA,
                                                                GL_UNSIGNED_BYTE,
                                                                0,
                                                                &texRef);
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer,
                                   kCVPixelBufferLock_ReadOnly);
    
    GLuint luminanceTexture = CVOpenGLESTextureGetName(texRef);
//    [self.mGLView displayPixelBuffer:luminanceTexture];
//    CFRelease(texRef);
#else
    
#endif
    
    dispatch_sync(mDrawQueue, ^{
        

        [self.mGLView displayPixelBuffer:luminanceTexture];
        CFRelease(texRef);

        
       // [self.mGLView displayPixelBuffer:pixelBuffer];
        
    });
    
    //CVPixelBufferRelease(pixelBuffer);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.mLabel.text = [NSString stringWithFormat:@"%ld", frameID];
    });
}


#pragma mark - Simple Editor

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end
