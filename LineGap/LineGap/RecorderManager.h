//
//  RecorderManager.h
//  SpeechComment
//
//  Created by 杨静伟 on 2018/5/10.
//  Copyright © 2018年 firstleap. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>

@class RecorderManager;

@protocol RecorderMangerDelegate<NSObject>

@optional
// 原始数据pcm回调
- (void)audioTool:(RecorderManager *)manager RecorderDidReceivedPcmData:(NSData *)pcmData;
// 音量回调
- (void)audioTool:(RecorderManager *)manager volume:(NSInteger)volume;
// 转换成aac文件回调
- (void)audioTool:(RecorderManager *)manager filePath:(NSString *)path;
@end

@interface RecorderManager : NSObject

@property (nonatomic , weak) id<RecorderMangerDelegate> delegate;

// 单例
+ (instancetype)sharedRecorder;
// 开始录音
- (BOOL) startRecording;
// 结束录音
- (void) stopRecording;

@end
