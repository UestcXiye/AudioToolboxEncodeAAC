//
//  ViewController.m
//  AudioToolboxEncodeAAC
//
//  Created by 刘文晨 on 2024/7/2.
//

#import "ViewController.h"
#import "AACEncoder.h"

@interface ViewController () <AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic, strong) AVCaptureSession *mCaptureSession; // 负责输入和输出设备之间的数据传递
@property (nonatomic, strong) AVCaptureDeviceInput *mCaptureAudioDeviceInput; // 负责从 AVCaptureDevice 获得输入数据
@property (nonatomic, strong) AVCaptureAudioDataOutput *mCaptureAudioOutput;

@property (nonatomic , strong) AACEncoder *mAudioEncoder;

@end

@implementation ViewController
{
    dispatch_queue_t mCaptureQueue;
    dispatch_queue_t mEncodeQueue;
    NSFileHandle *audioFileHandle;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = UIColor.whiteColor;
    
    self.mLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 300, 100)];
    self.mLabel.textColor = UIColor.blackColor;
    self.mLabel.text = @"使用 Audio Unit 录音并编码成 AAC";
    self.mLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.mButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
    [self.mButton setTitle:@"start" forState:UIControlStateNormal];
    [self.mButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    self.mButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.mButton addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.mLabel];
    [self.view addSubview:self.mButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.mLabel.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:100],
        [self.mLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        
        [self.mButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.mButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
    
    self.mAudioEncoder = [[AACEncoder alloc] init];
}

- (void)onClick:(UIButton *)sender
{
    if (!self.mCaptureSession || !self.mCaptureSession.running)
    {
        [sender setTitle:@"stop" forState:UIControlStateNormal];
        [self startCapture];
    }
    else
    {
        [sender setTitle:@"start" forState:UIControlStateNormal];
        [self stopCapture];
        
    }
}

- (void)startCapture
{
    self.mCaptureSession = [[AVCaptureSession alloc] init];
    
    mCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    mEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        
    AVCaptureDevice *audioDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] lastObject];
    self.mCaptureAudioDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:nil];
    if ([self.mCaptureSession canAddInput:self.mCaptureAudioDeviceInput])
    {
        [self.mCaptureSession addInput:self.mCaptureAudioDeviceInput];
    }
    self.mCaptureAudioOutput = [[AVCaptureAudioDataOutput alloc] init];
    
    if ([self.mCaptureSession canAddOutput:self.mCaptureAudioOutput])
    {
        [self.mCaptureSession addOutput:self.mCaptureAudioOutput];
    }
    [self.mCaptureAudioOutput setSampleBufferDelegate:self queue:mCaptureQueue];
       
    NSString *audioFilePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingString:@"/record.aac"];
    [[NSFileManager defaultManager] removeItemAtPath:audioFilePath error:nil];
    [[NSFileManager defaultManager] createFileAtPath:audioFilePath contents:nil attributes:nil];
    audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:audioFilePath];
    
    [self.mCaptureSession startRunning];
}

- (void)stopCapture
{
    [self.mCaptureSession stopRunning];
    [audioFileHandle closeFile];
    audioFileHandle = NULL;
}

#pragma mark - AVCaptureAudioDataOutputSampleBufferDelegate Method

- (void)captureOutput:(AVCaptureOutput *)output
        didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        fromConnection:(AVCaptureConnection *)connection
{
    dispatch_sync(mEncodeQueue, ^{
        [self.mAudioEncoder encodeSampleBuffer:sampleBuffer completionBlock:^(NSData *encodedData, NSError *error)
         {
            [self->audioFileHandle writeData:encodedData];
        }];
    });
}

@end
