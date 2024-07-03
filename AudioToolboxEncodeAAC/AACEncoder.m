//
//  AACEncoder.m
//  AudioToolboxEncodeAAC
//
//  Created by 刘文晨 on 2024/7/2.
//

#import "AACEncoder.h"

@interface AACEncoder()

@property (nonatomic) AudioConverterRef audioConverter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) NSUInteger aacBufferSize;
@property (nonatomic) char *pcmBuffer;
@property (nonatomic) size_t pcmBufferSize;

@end

@implementation AACEncoder

- (instancetype)init
{
    if (self = [super init])
    {
        _encoderQueue = dispatch_queue_create("AAC Encoder Queue", DISPATCH_QUEUE_SERIAL);
        _callbackQueue = dispatch_queue_create("AAC Encoder Callback Queue", DISPATCH_QUEUE_SERIAL);
        _audioConverter = NULL;
        _pcmBufferSize = 0;
        _pcmBuffer = NULL;
        _aacBufferSize = 1024;
        _aacBuffer = malloc(_aacBufferSize * sizeof(uint8_t));
        memset(_aacBuffer, 0, _aacBufferSize);
    }
    return self;
}

/**
 *  设置编码参数
 *
 *  @param sampleBuffer 音频
 */
- (void)setupEncoderFromSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    // input format
    AudioStreamBasicDescription inputFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
    // output format
    AudioStreamBasicDescription outputFormat = {0}; // 初始化输出流的结构体描述为 0，很重要
    outputFormat.mSampleRate = inputFormat.mSampleRate; // 音频流在正常播放情况下的采样率，如果是压缩的格式，这个属性表示解压缩后的采样率，不能为 0
    outputFormat.mFormatID = kAudioFormatMPEG4AAC; // 设置编码格式
    outputFormat.mFormatFlags = kMPEG4Object_AAC_LC; // 无损编码 ，0 表示没有
    outputFormat.mBytesPerPacket = 0; // 每一个 packet 的音频数据大小。如果是动态大小的格式，需要用 AudioStreamPacketDescription 来确定每个 packet 的大小
    outputFormat.mFramesPerPacket = 1024; // 每个 packet 的帧数。如果是未压缩的音频数据，值是 1。动态码率格式，这个值是一个较大的固定数字，比如说 AAC 为 1024。如果是动态大小帧数（比如 Ogg 格式），设置为 0
    outputFormat.mBytesPerFrame = 0; // 每帧的大小。如果是压缩格式，设置为 0
    outputFormat.mChannelsPerFrame = 1; // 声道数
    outputFormat.mBitsPerChannel = 0; // 压缩格式设置为 0
    outputFormat.mReserved = 0; // 8 字节对齐，填 0
    AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                                               fromManufacturer:kAppleSoftwareAudioCodecManufacturer]; // 软编码
    // 创建转换器
    OSStatus status = AudioConverterNewSpecific(&inputFormat, &outputFormat, 1, description, &_audioConverter);
    if (status != noErr)
    {
        NSLog(@"setup converter error: %d", (int)status);
    }
}

/**
 *  获取编码器
 *
 *  @param type 编码格式
 *  @param manufacturer 软编码/硬编码
 *
 *  @return AudioClassDescription 指定编码器
 */
- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type
                           fromManufacturer:(UInt32)manufacturer
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus status = noErr;
    
    UInt32 size;
    status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                        sizeof(encoderSpecifier),
                                        &encoderSpecifier,
                                        &size);
    if (status != noErr)
    {
        NSLog(@"failed to get audio format property info: %d", status);
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    status = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (status != noErr)
    {
        NSLog(@"failed to get audio format property: %d", status);
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++)
    {
        if ((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer))
        {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}


/**
 *  A callback function that supplies audio data to convert. This callback is invoked repeatedly as the converter is ready for new input data.
 
 */
OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
                         UInt32 *ioNumberDataPackets,
                         AudioBufferList *ioData,
                         AudioStreamPacketDescription **outDataPacketDescription,
                         void *inUserData)
{
    AACEncoder *encoder = (__bridge AACEncoder *)(inUserData);
    UInt32 requestedPackets = *ioNumberDataPackets;
    
    size_t copiedSamples = [encoder copyPCMSamplesIntoBuffer:ioData];
    if (copiedSamples < requestedPackets)
    {
        // PCM 缓冲区还没满
        *ioNumberDataPackets = 0;
        return -1;
    }
    *ioNumberDataPackets = 1;
    
    return noErr;
}

/**
 *  填充 PCM 到缓冲区
 */
- (size_t)copyPCMSamplesIntoBuffer:(AudioBufferList *)ioData
{
    size_t originalBufferSize = _pcmBufferSize;
    if (!originalBufferSize)
    {
        return 0;
    }
    ioData->mBuffers[0].mData = _pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = (int)_pcmBufferSize;
    _pcmBuffer = nil;
    _pcmBufferSize = 0;
    return originalBufferSize;
}

- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer completionBlock:(void (^)(NSData * encodedData, NSError* error))completionBlock
{
    CFRetain(sampleBuffer);
    dispatch_async(_encoderQueue, ^{
        if (!_audioConverter)
        {
            [self setupEncoderFromSampleBuffer:sampleBuffer];
        }
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRetain(blockBuffer);
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_pcmBufferSize, &_pcmBuffer);
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr)
        {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        memset(_aacBuffer, 0, _aacBufferSize);
        
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = (int)_aacBufferSize;
        outAudioBufferList.mBuffers[0].mData = _aacBuffer;
        AudioStreamPacketDescription *outPacketDescription = NULL;
        UInt32 ioOutputDataPacketSize = 1;
        // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
        // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
        status = AudioConverterFillComplexBuffer(_audioConverter, inInputDataProc, (__bridge void *)(self), &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
        NSData *data = nil;
        if (status == noErr)
        {
            NSData *rawAAC = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
            NSData *adtsHeader = [self adtsDataForPacketLength:rawAAC.length];
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            data = fullData;
        }
        else
        {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        if (completionBlock) 
        {
            dispatch_async(_callbackQueue, ^{
                completionBlock(data, error);
            });
        }
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    });
}

/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw AAC data.
 *
 *  Note the packetLength must count in the ADTS header itself.
 **/
- (NSData*)adtsDataForPacketLength:(NSUInteger)packetLength
{
    int adtsLength = 7; // if have CRC, adtsLength = 9
    char *packet = malloc(sizeof(char) * adtsLength);
    // 固定头部
    int syncword = 0xFFF; // 同步位
    int ID = 1; // 指示使用的 MPEG 版本。值为 0 表示 MPEG-4，值为 1 表示 MPEG-2
    int layer = 0; // 音频流的层级，对 ACC 来说为 0
    int protection_absent = 1; // 不使用 CRC 校验
    int profile = 1; // ACC 规格，LC
    int sample_frequency_index = 4; // 44.1kHz
    int private_bit = 0; // 私有比特，编码时设置为 0，解码时忽略
    int channel_configuration = 1; // MPEG-2 center front speaker
    int original_copy = 0; // 指示编码数据是否被原始产生。编码时设置为 0，解码时忽略
    int home = 0; // 编码时设置为 0，解码时忽略
    // 可变头部
    int copyright_identification_bit = 0; // 编码时设置为 0，解码时忽略
    int copyright_identification_start = 0; // 编码时设置为 0，解码时忽略
    NSUInteger acc_frame_length = adtsLength + packetLength; // 整个 ADTS 帧的长度
    int adts_buffer_fullness = 0x7FF; // 表示码率可变的码流
    int number_of_raw_data_blocks_in_frame = 0; // 该字段表示当前 ADTS 帧中所包含的 AAC 帧的个数减一。为了最大的兼容性通常每个 ADTS frame 包含一个 AAC frame，所以该值一般为 0
    
    packet[0] = (char)(syncword >> 4);
    packet[1] = (char)(((syncword & 0xF) << 4) + (ID << 3) + (layer << 1) + profile);
    packet[2] = (char)((profile << 6) + (sample_frequency_index << 2) + (private_bit << 1) + (channel_configuration >> 2));
    packet[3] = (char)(((channel_configuration & 0x3) << 6) + (original_copy << 5) + (home << 4) + (copyright_identification_bit << 3) + (copyright_identification_start << 2) + (acc_frame_length >> 11));
    packet[4] = (char)((acc_frame_length & 0x7FF) >> 3);
    packet[5] = (char)(((acc_frame_length & 0x7) << 5) + ((adts_buffer_fullness & 0x7C0) >> 6));
    packet[6] = (char)(((adts_buffer_fullness & 0x3F) << 2) + number_of_raw_data_blocks_in_frame);
    
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

- (void) dealloc
{
    AudioConverterDispose(_audioConverter);
    free(_aacBuffer);
}

@end
