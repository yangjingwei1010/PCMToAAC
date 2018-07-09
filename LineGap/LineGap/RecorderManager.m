//
//  Recorder.m
//  SpeechComment
//
//  Created by 杨静伟 on 2018/5/10.
//  Copyright © 2018年 firstleap. All rights reserved.
//

//audioQueue录音文件

#define kPath_Tmp NSTemporaryDirectory()
#define kPath_DownloadTmp kPath_Tmp

#define kNumberAudioQueueBuffers 3
#define kBufferDurationSeconds 0.1f
#define kRecoderPCMMaxBuffSize 2048

#define kXDXRecoderAudioBytesPerPacket      2
#define kXDXRecoderAACFramesPerPacket       1024
#define kXDXRecoderPCMTotalPacket           512
#define kXDXRecoderPCMFramesPerPacket       1
#define kXDXRecoderConverterEncodeBitRate   32000
#define kXDXAudioSampleRate                 16000

#import "RecorderManager.h"
#import <AVFoundation/AVFoundation.h>

static const int bitsPerChannel = 16; // 采样深度
static uint8_t pcm_buffer[kRecoderPCMMaxBuffSize * 2];
static int pcm_buffer_size = 0;

@interface RecorderManager() {
  AudioQueueBufferRef _audioBuffers[kNumberAudioQueueBuffers];
  AudioFileID                     _mRecordFile;
}
@property (nonatomic, assign) AudioConverterRef encodeConvertRef;   ///< convert param
@property (nonatomic, assign) AudioQueueRef audioQueue;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign, readonly) AudioStreamBasicDescription recordFormat;
@property (nonatomic, assign, readonly) AudioStreamBasicDescription targetDes;
@property (nonatomic, strong) NSMutableData *data1;
@property (nonatomic, strong) NSFileHandle *audioFileHandle;

@property (nonatomic, strong) NSString *filename;
@property (nonatomic, strong) NSString *path;

@end

@implementation RecorderManager

// 单例
+ (instancetype)sharedRecorder {
  static RecorderManager *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[RecorderManager alloc] init];
  });
  return instance;
}
// 开始录音
- (BOOL)startRecording {
  self.data1 = [NSMutableData data];
  
  memset(pcm_buffer, 0, pcm_buffer_size);
  pcm_buffer_size = 0;
  
  _filename = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"aac"];
  _path = [kPath_DownloadTmp stringByAppendingPathComponent:_filename];
  NSLog(@"_path:%@",_path);
  
  // 有就移除掉
  NSError *error;
  [[NSFileManager defaultManager] removeItemAtPath:self.path error:&error];
  NSLog(@"error:%@",error);
  // 移除之后再创建
  [[NSFileManager defaultManager] createFileAtPath:self.path contents:nil attributes:nil];
  // 创建文件句柄
  self.audioFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.path];
  // 设置录音格式
  [self setupAudioFormat:kAudioFormatLinearPCM SampleRate:kXDXAudioSampleRate];
  
  OSStatus status          = 0;
  UInt32   size            = sizeof(_recordFormat);
  // 编码器转码设置
  NSString *err = [self convertBasicSetting];
  // 这个if语句用来检测是否初始化本例对象成功,如果不成功重启三次,三次后如果失败可以进行其他处理
  if (err != nil) {
    NSString *error = nil;
    for (int i = 0; i < 3; i++) {
      usleep(100*1000);
      error = [self convertBasicSetting];
      if (error == nil) break;
    }
    return NO;
  }
  
  // 新建一个队列,第二个参数注册回调函数，第三个防止内存泄露
  OSStatus inputError = AudioQueueNewInput(&_recordFormat, inputBufferHandler, (__bridge void *)(self), NULL, NULL, 0, &_audioQueue);
  if (inputError) {
    return NO;
  }
  // 获取队列属性
  status = AudioQueueGetProperty(_audioQueue, kAudioQueueProperty_StreamDescription, &_recordFormat, &size);
  // 设置三个音频队列缓冲区
  for (int i = 0; i < kNumberAudioQueueBuffers; ++i) {
    AudioQueueAllocateBuffer(_audioQueue, kXDXRecoderPCMTotalPacket*kXDXRecoderAudioBytesPerPacket*_recordFormat.mChannelsPerFrame, &_audioBuffers[i]);
    AudioQueueEnqueueBuffer(_audioQueue, _audioBuffers[i], 0, NULL);
  }
  UInt32 enabledLevelMeter = true;
  OSStatus setError = AudioQueueSetProperty(_audioQueue, kAudioQueueProperty_EnableLevelMetering, &enabledLevelMeter, sizeof(UInt32));
  
  if (setError) {
    return NO;
  }
  // start recording
  OSStatus startError = AudioQueueStart(_audioQueue, NULL);
  if (startError) {
    return NO;
  }
  
  _isRecording = YES;
  
  return YES;
}

// 停止录音
- (void)stopRecording {
  if (_isRecording) {
    
    _isRecording = NO;
    
    AudioQueueStop(_audioQueue, true);
    AudioQueueDispose(_audioQueue, true);
  }
  if (self.delegate && [self.delegate respondsToSelector:@selector(audioTool:filePath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate audioTool:self filePath:self.path];
    });
  }
  
  NSError *readingError = nil;
  NSData *fileData = [NSData dataWithContentsOfFile:self.path options:NSDataReadingMapped error:&readingError];
  NSLog(@"%@,音频大小：%lu",self.path,(unsigned long)fileData.length);
  
  //关闭文件句柄
  [self.audioFileHandle closeFile];
  self.audioFileHandle = nil;
}

// 设置录音格式
- (void)setupAudioFormat:(UInt32) inFormatID SampleRate:(int) sampeleRate {
  
  memset(&_recordFormat, 0, sizeof(_recordFormat));
  // 采样率的意思是每秒需要采集的帧数
  _recordFormat.mSampleRate = sampeleRate;
  // 声道数（单声道）
  _recordFormat.mChannelsPerFrame = 1;
  
  _recordFormat.mFormatID = inFormatID;
  if (inFormatID == kAudioFormatLinearPCM) {
    
    _recordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    // 每个声道中的每个采样点用8bit数据量化
    _recordFormat.mBitsPerChannel = bitsPerChannel;
    // 每帧的字节数(2个字节)
    _recordFormat.mBytesPerFrame = (_recordFormat.mBitsPerChannel / 8) * _recordFormat.mChannelsPerFrame;
    _recordFormat.mBytesPerPacket = (_recordFormat.mBitsPerChannel / 8) * _recordFormat.mChannelsPerFrame;
    // 一个数据包放一帧数据
    _recordFormat.mFramesPerPacket = kXDXRecoderPCMFramesPerPacket;
  }
  
}

// 转码器基本信息设置
- (NSString *)convertBasicSetting {
  // 此处目标格式其他参数均为默认，系统会自动计算，否则无法进入encodeConverterComplexInputDataProc回调
  AudioStreamBasicDescription sourceDes = _recordFormat;
  AudioStreamBasicDescription targetDes;
  // 设置目标格式及基本信息
  memset(&targetDes, 0, sizeof(targetDes));
  targetDes.mFormatID                   = kAudioFormatMPEG4AAC;
  targetDes.mSampleRate                 = kXDXAudioSampleRate;
  targetDes.mChannelsPerFrame           = _recordFormat.mChannelsPerFrame;
  // 采集的为AAC需要将targetDes.mFramesPerPacket设置为1024，AAC软编码需要喂给转换器1024个样点才开始编码，这与回调函数中inNumPackets有关，不可随意更改
  targetDes.mFramesPerPacket            = kXDXRecoderAACFramesPerPacket;
  
  OSStatus status     = 0;
  UInt32 targetSize   = sizeof(targetDes);
  status              = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &targetSize, &targetDes);
  
  memset(&_targetDes, 0, sizeof(_targetDes));
  // 赋给全局变量
  memcpy(&_targetDes, &targetDes, targetSize);
  
  // 选择软件编码
  AudioClassDescription audioClassDes;
  status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                      sizeof(targetDes.mFormatID),
                                      &targetDes.mFormatID,
                                      &targetSize);
  // 计算编码器容量
  UInt32 numEncoders = targetSize / sizeof(AudioClassDescription);
  // 用数组存放编码器内容
  AudioClassDescription audioClassArr[numEncoders];
  // 将编码器属性赋给数组
  AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                         sizeof(targetDes.mFormatID),
                         &targetDes.mFormatID,
                         &targetSize,
                         audioClassArr);
  // 遍历数组，设置软编
  for (int i = 0; i < numEncoders; i++) {
    if (audioClassArr[i].mSubType == kAudioFormatMPEG4AAC && audioClassArr[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer) {
      memcpy(&audioClassDes, &audioClassArr[i], sizeof(AudioClassDescription));
      break;
    }
  }
  // 防止内存泄露
  if (_encodeConvertRef == NULL) {
    // 新建一个编码对象，设置原，目标格式
    status = AudioConverterNewSpecific(&sourceDes, &targetDes, 1,
                                       &audioClassDes, &_encodeConvertRef);
    
    if (status != noErr) {
      return @"Error : New convertRef failed \n";
    }
  }
  // 获取原始格式大小
  targetSize      = sizeof(sourceDes);
  status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentInputStreamDescription, &targetSize, &sourceDes);
  // 获取目标格式大小
  targetSize      = sizeof(targetDes);
  status          = AudioConverterGetProperty(_encodeConvertRef, kAudioConverterCurrentOutputStreamDescription, &targetSize, &targetDes);
  
  // 设置码率，需要和采样率对应
  UInt32 bitRate  = kXDXRecoderConverterEncodeBitRate;
  targetSize      = sizeof(bitRate);
  //作用：设置码率，需要注意，AAC并不是随便的码率都可以支持。比如如果PCM采样率是44100KHz，那么码率可以设置64000bps，如果是16K，可以设置为32000bps。
  status          = AudioConverterSetProperty(_encodeConvertRef,
                                              kAudioConverterEncodeBitRate,
                                              targetSize, &bitRate);
  if (status != noErr) {
    return @"Error : Set covert property bit rate failed";
  }
  
  return nil;
}

// 语音处理回调方法
void inputBufferHandler(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, const AudioTimeStamp *inStartTime, UInt32 inNumPackets, const AudioStreamPacketDescription *inPacketDesc) {
  
  if (inNumPackets > 0) {
    RecorderManager *recorder = [RecorderManager sharedRecorder];
    UInt32 stateSize = sizeof(AudioQueueLevelMeterState);
    AudioQueueLevelMeterState *state = malloc(stateSize);
    AudioQueueGetProperty(recorder.audioQueue, kAudioQueueProperty_CurrentLevelMeter, state, &stateSize);
    float power = state[0].mPeakPower;
    free(state);
    // 音量回调：
    float peakPowerForChannel = (powf(10, (0.05 * power))-1.0) * 700;
    float volume = MIN(100, (peakPowerForChannel));
    if (recorder.delegate && [recorder.delegate respondsToSelector:@selector(audioTool:volume:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [recorder.delegate audioTool:recorder volume:volume];
      });
      
    }
    
    int pcmSize = inBuffer->mAudioDataByteSize;
    char *pcmData = (char *)inBuffer->mAudioData;
    NSData *pcmBackData = [[NSData alloc] initWithBytes:pcmData length:pcmSize];
    [recorder.data1 appendData:pcmBackData];
    NSLog(@"data1:%lu",(unsigned long)recorder.data1.length);
    // 音频数据回调
    if (recorder.delegate && [recorder.delegate respondsToSelector:@selector(audioTool:RecorderDidReceivedPcmData:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [recorder.delegate audioTool:recorder RecorderDidReceivedPcmData:pcmBackData];
      });
      
    }
    
    // PCM -> AAC
    // 由于PCM转成AAC的转换器每次需要有1024个采样点（每一帧2个字节）才能完成一次转换，所以每次需要2048大小的数据，这里定义的pcm_buffer用来累加每次存储的bufferData
    memcpy(pcm_buffer+pcm_buffer_size, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    pcm_buffer_size = pcm_buffer_size + inBuffer->mAudioDataByteSize;
    
    if(pcm_buffer_size >= kRecoderPCMMaxBuffSize){
      AudioBufferList *bufferList = convertPCMToAAC(recorder);
      
      // 因为采样不可能每次都精准的采集到1024个样点，所以如果大于2048大小就先填满2048，剩下的跟着下一次采集一起送给转换器
      memcpy(pcm_buffer, pcm_buffer + kRecoderPCMMaxBuffSize, pcm_buffer_size - kRecoderPCMMaxBuffSize);
      pcm_buffer_size = pcm_buffer_size - kRecoderPCMMaxBuffSize;
      
      NSData *data = [NSData data];
      NSData *rawAAC = [NSData dataWithBytes:bufferList->mBuffers[0].mData length:bufferList->mBuffers[0].mDataByteSize];
      NSData *adtsHeader = [recorder adtsDataForPacketLength:rawAAC.length];
      NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
      [fullData appendData:rawAAC];
      data = fullData;
//      [recorder.data1 appendData:data];
//
      [recorder.audioFileHandle seekToEndOfFile];
      [recorder.audioFileHandle writeData:data];
//
      // free memory
      if(bufferList) {
        free(bufferList->mBuffers[0].mData);
        free(bufferList);
      }
    }
    
    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
  }
}
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
  int adtsLength = 7;
  char *packet = (char *)malloc(sizeof(char) * adtsLength);
  // Variables Recycled by addADTStoPacket
  int profile = 2;  //AAC LC
  //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
  int freqIdx = 8;  //0: 96000 Hz,1: 88200 Hz,2: 64000 Hz,3: 48000 Hz,4: 44100 Hz,5: 32000 Hz,6: 24000 Hz,7: 22050 Hz,8: 16000 Hz,9: 12000 Hz,10: 11025 Hz,11: 8000 Hz,12: 7350 Hz
  int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
  NSUInteger fullLength = adtsLength + packetLength;
  // fill in ADTS data
  packet[0] = (char)0xFF; // 11111111     = syncword
  packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
  packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
  packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
  packet[4] = (char)((fullLength&0x7FF) >> 3);
  packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
  packet[6] = (char)0xFC;
  NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
  return data;
}
// PCM -> AAC
AudioBufferList* convertPCMToAAC (RecorderManager *recoder) {
  
  UInt32   maxPacketSize    = 0;
  UInt32   size             = sizeof(maxPacketSize);
  OSStatus status;
  
  status = AudioConverterGetProperty(recoder.encodeConvertRef,
                                     kAudioConverterPropertyMaximumOutputPacketSize,
                                     &size,
                                     &maxPacketSize);
  
  AudioBufferList *bufferList             = (AudioBufferList *)malloc(sizeof(AudioBufferList));
  bufferList->mNumberBuffers              = 1;
  bufferList->mBuffers[0].mNumberChannels = recoder.targetDes.mChannelsPerFrame;
  bufferList->mBuffers[0].mData           = malloc(maxPacketSize);
  bufferList->mBuffers[0].mDataByteSize   = kRecoderPCMMaxBuffSize;
  AudioStreamPacketDescription outputPacketDescriptions;
  
  // inNumPackets设置为1表示编码产生1帧数据即返回, 在输入表示输出数据的最大容纳能力 在转换器的输出格式上，在转换完成时表示多少个包被写入
  UInt32 inNumPackets = 1;
  // inNumPackets设置为1表示编码产生1024帧数据即返回, 在此处由于编码器特性,必须给编码器1024帧数据才能完成一次转换,也就是刚刚在采集数据回调中存储的pcm_buffer
  status = AudioConverterFillComplexBuffer(recoder.encodeConvertRef,
                                           encodeConverterComplexInputDataProc,
                                           pcm_buffer,
                                           &inNumPackets,
                                           bufferList,
                                           &outputPacketDescriptions);
  
  if(status != noErr){
    free(bufferList->mBuffers[0].mData);
    free(bufferList);
    return NULL;
  }
  
  return bufferList;
}
#pragma mark - convert
OSStatus encodeConverterComplexInputDataProc(AudioConverterRef              inAudioConverter,
                                             UInt32                         *ioNumberDataPackets,
                                             AudioBufferList                *ioData,
                                             AudioStreamPacketDescription   **outDataPacketDescription,
                                             void                           *inUserData) {
  RecorderManager *recorder = [RecorderManager sharedRecorder];
  ioData->mBuffers[0].mData           = inUserData;
  ioData->mBuffers[0].mNumberChannels = recorder.targetDes.mChannelsPerFrame;
  ioData->mBuffers[0].mDataByteSize   = kXDXRecoderAACFramesPerPacket * kXDXRecoderAudioBytesPerPacket * recorder.targetDes.mChannelsPerFrame;
  
  return 0;
}

@end
