//
//  XJRecordEngine.m
//  RingDiyClient
//
//  Created by wxj on 14/11/24.
//  Copyright (c) 2014年 tt. All rights reserved.
//

#import "XJRecordEngine.h"
#import <AVFoundation/AVFoundation.h>

#define kBufferDurationSeconds .5
#define kNumberRecordBuffers	3

// 静音检查时间间隔
#define POWER_CHECK_TIME_SPACE 0.1
// 当录音的能量值低于QUIET_VOLUMN_LIMIT_VALUE，则认为是静音
#define QUIET_VOLUMN_LIMIT_VALUE 0.06

@interface XJRecordEngine ()
{
    AudioQueueRef _audioQueue;
    AudioQueueBufferRef	_audioBuffers[kNumberRecordBuffers];
    
    NSTimer *_startPointCheckTimer;
    NSTimer *_endPointCheckTimer;
    NSTimer *_recordPowerCheckTimer;
}

@property (nonatomic, assign) AudioFileID cacheFileId;
@property (nonatomic, assign) NSInteger recordPacketCount;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) XJRecordEngineStatus status;

@end

@implementation XJRecordEngine

#pragma mark callback

static void MyRecordInputBufferHandler(void *								inUserData,
                                       AudioQueueRef						inAQ,
                                       AudioQueueBufferRef					inBuffer,
                                       const AudioTimeStamp *				inStartTime,
                                       UInt32								inNumPackets,
                                       const AudioStreamPacketDescription*	inPacketDesc)
{
    __weak XJRecordEngine *recordEngine = (__bridge XJRecordEngine *)inUserData;
    [recordEngine handleRecordInputBuffer:inBuffer inStartTime:inStartTime inNumPackets:inNumPackets inPacketDesc:inPacketDesc];
    
}

- (void)handleRecordInputBuffer:(AudioQueueBufferRef)inBuffer
                    inStartTime:(const AudioTimeStamp *)inStartTime
                   inNumPackets:(UInt32)inNumPackets
                   inPacketDesc:(const AudioStreamPacketDescription*)inPacketDesc
{
    NSLog(@"handleRecordInputBuffer");
    OSStatus err = 0;
    // 写入文件
    if (_cacheFileId) {
        err = AudioFileWritePackets(_cacheFileId, FALSE, inBuffer->mAudioDataByteSize, inPacketDesc, self.recordPacketCount, &inNumPackets, inBuffer->mAudioData);
        // 写入文件出错
        if (err) {
            return;
        }
        self.recordPacketCount += inNumPackets;
    }
    // 回调录音数据
    if ([_delegate respondsToSelector:@selector(recordEngine:didGetRecordData:length:)]) {
        [_delegate recordEngine:self didGetRecordData:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
    }
    if (self.status == XJRecordEngineInRecrodingStatus) {
        err = AudioQueueEnqueueBuffer(_audioQueue, inBuffer, 0, NULL);
        if (err) {
            NSLog(@"AudioQueueEnqueueBuffer failed");
            return;
        }
    }
}

#pragma mark tool

// 当前是否是静音状态
- (BOOL)isCurrentQuiteAuido
{
    return [self power] < QUIET_VOLUMN_LIMIT_VALUE;
}

#pragma mark 初始化

- (void)setUpParameters
{
    _sampleRate = 16000;
    _channelsPerFrame = 1;
    _bitesPerChannel = 16;
    
    _vadBeginPointTimeLength = MAXFLOAT;
    _vadEndPointTimeLength = MAXFLOAT;
}

- (id)initWithCachePath:(NSString *)cachePath
{
    if (self = [super init]) {
        _cachePath = cachePath;
        [self setUpParameters];
    }
    return self;
}

+ (instancetype)recordEngine
{
    return [[self class] recordEngineWithCachePath:nil];
}

+ (instancetype)recordEngineWithCachePath:(NSString *)cachePath
{
    return [[[self class] alloc] initWithCachePath:cachePath];
}

#pragma mark -

- (void)setSampleRate:(NSInteger)sampleRate
{
    _sampleRate = sampleRate;
}

- (void)setBitesPerChannel:(NSInteger)bitesPerChannel
{
    _bitesPerChannel = bitesPerChannel;
}

- (void)setChannelsPerFrame:(NSInteger)channelsPerFrame
{
    _channelsPerFrame = channelsPerFrame;
}

- (void)setVadBeginPointTimeLength:(NSTimeInterval)length
{
    _vadBeginPointTimeLength = length;
}

- (void)setVadEndPointTimeLength:(NSTimeInterval)length
{
    _vadEndPointTimeLength = length;
}

#pragma mark 端点检测逻辑

// 前端点检查
- (void)onStartPointCheck
{
    if ([_delegate respondsToSelector:@selector(recordEngineDidCheckStartPointOfVAD:)]) {
        [_delegate recordEngineDidCheckStartPointOfVAD:self];
    }
}

// 开启前端点静音检测
- (void)startStartPointCheckTimer
{
    [_startPointCheckTimer invalidate];
    _startPointCheckTimer = [NSTimer scheduledTimerWithTimeInterval:_vadBeginPointTimeLength target:self selector:@selector(onStartPointCheck) userInfo:nil repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:_startPointCheckTimer forMode:NSRunLoopCommonModes];
}

// 关闭前端点静音检测
- (void)stopStartPointCheckTimer
{
    [_startPointCheckTimer invalidate];
    _startPointCheckTimer = nil;
}

// 后端点检查
- (void)onEndPointCheck
{
    if ([_delegate respondsToSelector:@selector(recordEngineDidCheckEndPointOfVAD:)]) {
        [_delegate recordEngineDidCheckEndPointOfVAD:self];
    }
}

// 开启后端点静音检测
- (void)startEndPointCheckTimer
{
    [_endPointCheckTimer invalidate];
    _endPointCheckTimer = [NSTimer scheduledTimerWithTimeInterval:_vadEndPointTimeLength target:self selector:@selector(onEndPointCheck) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_endPointCheckTimer forMode:NSRunLoopCommonModes];
}

// 关闭后端点静音检测
- (void)stopEndPointCheckTimer
{
    [_endPointCheckTimer invalidate];
    _endPointCheckTimer = nil;
}

#pragma mark 录音能量检测

- (void)startPowerCheckTimer
{
    [_recordPowerCheckTimer invalidate];
    _recordPowerCheckTimer = [NSTimer scheduledTimerWithTimeInterval:POWER_CHECK_TIME_SPACE target:self selector:@selector(onPowerCheck) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_recordPowerCheckTimer forMode:NSRunLoopCommonModes];
}

- (void)stopRowerCheckTimer
{
    [_recordPowerCheckTimer invalidate];
    _recordPowerCheckTimer = nil;
}

- (void)onPowerCheck
{
//    NSLog(@"onPowerCheck");
    // 录音有音量，那么则停止前端静音检查
    if (![self isCurrentQuiteAuido]) {
        [self stopStartPointCheckTimer];
    }
    // 没有录音
    else {
        // 当前正在进行起端点静音检查
        if (![_startPointCheckTimer isValid]) {
            // 开启后端点静音检查
            if ([self isCurrentQuiteAuido]) {
                if (![_endPointCheckTimer isValid]) {
                    NSLog(@"onPowerCheck end");
                    [self startEndPointCheckTimer];
                }
            } else {
                [self stopEndPointCheckTimer];
            }
        }
    }
}

#pragma mark tool

- (void)setUpAudioSessionForRecord
{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    // 开始属性设置为record，会导致录音或者播放其中一个无法正常工作，
    // 使用playrecord属性后，修复了这个问题
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:NULL];
}

- (struct AudioStreamBasicDescription)getParametersForRecord
{
    struct AudioStreamBasicDescription recordFormat;
    memset(&recordFormat, 0, sizeof(recordFormat));
    UInt32 size = sizeof(recordFormat.mSampleRate);
    OSStatus status = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareSampleRate,
                                              &size,
                                              &recordFormat.mSampleRate);
    size = sizeof(recordFormat.mChannelsPerFrame);
    status = AudioSessionGetProperty(kAudioSessionProperty_CurrentHardwareInputNumberChannels,
                                     &size,
                                     &recordFormat.mChannelsPerFrame);
    recordFormat.mSampleRate = _sampleRate;
    recordFormat.mChannelsPerFrame = _channelsPerFrame;
    recordFormat.mFormatID = kAudioFormatLinearPCM;
    recordFormat.mBitsPerChannel = _bitesPerChannel;
    recordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    recordFormat.mBitsPerChannel = _bitesPerChannel;
    recordFormat.mBytesPerPacket = recordFormat.mBytesPerFrame = (recordFormat.mBitsPerChannel / 8) * recordFormat.mChannelsPerFrame;
    recordFormat.mFramesPerPacket = 1;
    return recordFormat;
}

// 获取存放录音数据的buffer大小
- (int)computeRecordBufferSizeWithDescription:(struct AudioStreamBasicDescription *)format seconds:(float)seconds audioQueue:(AudioQueueRef)audioQueue
{
    int packets, frames, bytes = 0;
    OSStatus err = 0;
    frames = (int)ceil(seconds * format->mSampleRate);
    
    if (format->mBytesPerFrame > 0) {
        bytes = frames * format->mBytesPerFrame;
    }
    else {
        UInt32 maxPacketSize;
        if (format->mBytesPerPacket > 0)
            maxPacketSize = format->mBytesPerPacket;	// constant packet size
        else {
            UInt32 propertySize = sizeof(maxPacketSize);
            err = AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &propertySize);
            if (err) {
                return 0;
            }
        }
        if (format->mFramesPerPacket > 0)
            packets = frames / format->mFramesPerPacket;
        else
            packets = frames;	// worst-case scenario: 1 frame in a packet
        if (packets == 0)		// sanity check
            packets = 1;
        bytes = packets * maxPacketSize;
    }
    return bytes;
}

#pragma mark -

- (void)start
{
    OSStatus status = 0;
    // 当前正在录音
    if (self.status == XJRecordEngineInRecrodingStatus) {
        return;
    }
    // 当前暂停了录音
    if (self.status == XJRecordEnginePauseStatus) {
        // 恢复录音
        [self setUpAudioSessionForRecord];
        status = AudioQueueStart(_audioQueue, NULL);
        if (status != noErr) {
            self.status = XJRecordEngineFailStatus;
        } else {
            self.status = XJRecordEngineInRecrodingStatus;
        }
        return;
    }
    // 录音的准备
    [self setUpAudioSessionForRecord];
    // 设置录音的相关参数
    _recordFormate = [self getParametersForRecord];
    // 初始化audioqueue
    status = AudioQueueNewInput(
                                &_recordFormate,
                                MyRecordInputBufferHandler,
                                (__bridge void *)(self) ,
                                NULL, NULL ,
                                0 , &_audioQueue);
    if (status) {
        // 处理错误
        AudioQueueDispose(_audioQueue, true);
        _audioQueue = nil;
        self.status = XJRecordEngineFailStatus;
        return;
    }
    // 如果需要缓存到本地的话，执行下面的逻辑
    if (_cachePath) {
        CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)_cachePath, NULL);
        status = AudioFileCreateWithURL(url, kAudioFileCAFType, &_recordFormate, kAudioFileFlags_EraseFile,
                                        &_cacheFileId);
    }
    
    // 初始化缓存
    int bufferByteSize = [self computeRecordBufferSizeWithDescription:&_recordFormate seconds:kBufferDurationSeconds audioQueue:_audioQueue];
    if (bufferByteSize <= 0) {
        bufferByteSize = 4096;
    }
    for (NSInteger i = 0; i < kNumberRecordBuffers; ++i) {
        status = AudioQueueAllocateBuffer(_audioQueue, bufferByteSize, &_audioBuffers[i]);
        if (status) {
            // 处理错误
            self.status = XJRecordEngineFailStatus;
            goto statusError_first;
        }
        status = AudioQueueEnqueueBuffer(_audioQueue, _audioBuffers[i], 0, NULL);
        if (status) {
            // 处理错误
            self.status = XJRecordEngineFailStatus;
            goto statusError_first;
        }
    }
    status = AudioQueueStart(_audioQueue, NULL);
    if (status == noErr) {
        self.status = XJRecordEngineInRecrodingStatus;
        UInt32 trueValue = true;
        AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableLevelMetering, &trueValue, sizeof(UInt32));
        // 开启前端点静音检查
        [self startStartPointCheckTimer];
        [self startPowerCheckTimer];
        return;
    }
statusError_second:
    AudioQueueStop(_audioQueue, true);
statusError_first:
    AudioQueueDispose(_audioQueue, true);
    _audioQueue = nil;
    // 关闭文件
    if (_cacheFileId) {
        AudioFileClose(_cacheFileId);
        _cacheFileId = NULL;
    }
}

- (void)stop
{
    if (self.status == XJRecordEngineInRecrodingStatus || self.status == XJRecordEnginePauseStatus) {
        [self stopStartPointCheckTimer];
        [self stopEndPointCheckTimer];
        [self stopRowerCheckTimer];
        self.isRunning = NO;
        // 停止录音器
        if (_audioQueue) {
            AudioQueueStop(_audioQueue, true);
            AudioQueueDispose(_audioQueue, true);
            _audioQueue = NULL;
        }
        // 关闭录音缓存文件
        if (_cacheFileId) {
            AudioFileClose(_cacheFileId);
            _cacheFileId = NULL;
        }
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    }
}

- (void)pause
{
    if (self.status == XJRecordEngineInRecrodingStatus) {
        OSStatus status = 0;
        status = AudioQueuePause(_audioQueue);
        if (status != noErr) {
            self.status = XJRecordEngineFailStatus;
        } else {
            self.status = XJRecordEnginePauseStatus;
        }
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    }
}

- (CGFloat)power
{
    if (!_audioQueue) {
        return 0;
    }
    // 当前没有在录音
    if (self.status != XJRecordEngineInRecrodingStatus) {
        return 0;
    }
    AudioQueueLevelMeterState meterData;
    UInt32 propertSize = sizeof(AudioQueueLevelMeterState);
    AudioQueueGetProperty(_audioQueue, (AudioQueuePropertyID) kAudioQueueProperty_CurrentLevelMeter, &meterData, &propertSize);
    return meterData.mAveragePower;
}

@end
