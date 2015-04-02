//
//  XJRecordEngine.h
//  RingDiyClient
//
//  Created by wxj on 14/11/24.
//  Copyright (c) 2014年 tt. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>

typedef NS_ENUM(NSUInteger, XJRecordEngineStatus)
{
    XJRecordEngineInitStatus,
    XJRecordEngineInRecrodingStatus,
    XJRecordEnginePauseStatus,
    XJRecordEngineFinishStatus,
    XJRecordEngineFailStatus,
};

@interface XJRecordEngine : NSObject
{
@private
    NSInteger _sampleRate;        // 输出文件的采样率
    NSInteger _bitesPerChannel;
    NSInteger _channelsPerFrame;
    
@private
    // 录音数据保存的文件路径
    NSString *_cachePath;
    
@private
    // 前端点超静音检测时间长度，默认无限长
    NSTimeInterval _vadBeginPointTimeLength;
    // 前端点超静音检测时间长度，默认为无限长
    NSTimeInterval _vadEndPointTimeLength;
    
@private
    struct AudioStreamBasicDescription _recordFormate;
}

@property (nonatomic, weak) id delegate;
@property (nonatomic, readonly) XJRecordEngineStatus status;

#pragma mark 初始化

+ (instancetype)recordEngine;
+ (instancetype)recordEngineWithCachePath:(NSString *)cachePath;

#pragma mark 属性设置

- (void)setSampleRate:(NSInteger)sampleRate;
- (void)setBitesPerChannel:(NSInteger)bitesPerChannel;
- (void)setChannelsPerFrame:(NSInteger)channelsPerFrame;

- (void)setVadBeginPointTimeLength:(NSTimeInterval)length;
- (void)setVadEndPointTimeLength:(NSTimeInterval)length;

#pragma mark -

- (void)start;
- (void)pause;
- (void)stop;
- (CGFloat)power;

@end

@protocol XJRecordEngineDelegate <NSObject>

@optional

// 获取录音数据缓存的文件
- (NSString *)recordEngineGetCachePath:(XJRecordEngine *)recordEngine;
// 在录音的过程中，得到的录音数据
- (void)recordEngine:(XJRecordEngine *)recordEngine didGetRecordData:(void *)data length:(UInt32)length;


// 静音检查
@optional

// 前端点经验检查到时间点了
- (void)recordEngineDidCheckStartPointOfVAD:(XJRecordEngine *)recordEngine;
// 后端点经验检查到时间点了
- (void)recordEngineDidCheckEndPointOfVAD:(XJRecordEngine *)recordEngine;

@end
