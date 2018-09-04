//
//  YBAVPlayerAdapter.m
//  YouboraAVPlayerAdapter
//
//  Created by Joan on 13/04/2017.
//  Copyright © 2017 NPAW. All rights reserved.
//

#import "YBAVPlayerAdapter.h"
#import <TargetConditionals.h>

// Constants
#define MACRO_NAME(f) #f
#define MACRO_VALUE(f) MACRO_NAME(f)

#define PLUGIN_VERSION_DEF MACRO_VALUE(YOUBORAADAPTER_VERSION)
#define PLUGIN_NAME_DEF "AVPlayer"

#if TARGET_OS_TV==1
    #define PLUGIN_PLATFORM_DEF "tvOS"
#else
    #define PLUGIN_PLATFORM_DEF "iOS"
#endif

#define PLUGIN_NAME @PLUGIN_NAME_DEF "-" PLUGIN_PLATFORM_DEF
#define PLUGIN_VERSION @PLUGIN_VERSION_DEF "-" PLUGIN_NAME_DEF "-" PLUGIN_PLATFORM_DEF

#define MONITOR_INTERVAL 800

// For AVPlayer
@import AVFoundation;

@interface YBAVPlayerAdapter()

/// Time observer for join time
@property (nonatomic, strong) id joinTimePeriodicTimeObserver;

/// Time observer for seeks
@property (nonatomic, strong) id seekDetectionPeriodicTimeObserver;

/// Last playhead observed. It is used for seek detection
@property (nonatomic, assign) double lastPlayhead;

/// Calculated bitrate
@property (nonatomic, assign) double bitrate;

/// Throughput
@property (nonatomic, assign) long long throughput;

/// Rendition
@property (nonatomic, strong) NSString * rendition;

/// Error codes for known fatal errors
@property (nonatomic, strong) NSArray * fatalErrors;

@property (nonatomic, assign) double lastRenditionBitrate;

@end

@implementation YBAVPlayerAdapter

// Observation context
static void * const observationContext = (void *) &observationContext;
//Just to skip false seeks (such as de first one)
bool firstSeek;

- (void)registerListeners {
    [super registerListeners];
    
    self.fatalErrors = @[@-1100 , @-11853, @-1005, @-11819, @-11800, @-1008];
    
    @try {
        [self resetValues];
        [self monitorPlayheadWithBuffers:true seeks:false andInterval:MONITOR_INTERVAL]; // [buffer, seek, interval] in this case we monitor buffers, but not seeks every 800 milliseconds
        [self.monitor stop];
        
        AVPlayer * avplayer = self.player;
        
        // Observers for AVPlayer
        [avplayer addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:observationContext];
        [avplayer addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:observationContext];
        
        // Observers for currentItem
        if (avplayer.currentItem != nil) {
            
            // Check if we need to send start
            //Commented since it could be fired without having set the plugin therefore making posible to change flags without sending /start request
            /*if (avplayer.rate != 0.0) {
                [self fireStart];
            }*/
            
            [self prepareForNewViewWithPlayerItem:avplayer.currentItem];
        }
        
        // Notifications
        NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
        
        // Notification when the playback ends successfully
        [nc addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        
        // Notification accesslog - we use this to get the bitrate
        //[nc addObserver:self selector:@selector(accessLogEntry:) name:AVPlayerItemNewAccessLogEntryNotification object:nil];
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) unregisterListeners {
    
    @try {
        AVPlayer * avplayer = self.player;
        
        // Remove observers and notifications
        [avplayer removeObserver:self forKeyPath:@"rate" context:observationContext];
        [avplayer removeObserver:self forKeyPath:@"currentItem" context:observationContext];
        
        if (avplayer.currentItem != nil) {
            [self removeObserversForAVPlayerItem:avplayer.currentItem];
        }
        
        NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
        
        // Remove all notifications
        [nc removeObserver:self];
        
        // This will send /stop if necessary, stop timers and set the player to nil
        [super unregisterListeners];
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) prepareForNewViewWithPlayerItem:(AVPlayerItem *) playerItem {
    @try {
        [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:observationContext];
        [playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:observationContext];
        [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld  context:observationContext];
        //[playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld  context:observationContext];
        
        __weak typeof(self) weakSelf = self;
        
        // Set up observer for jointime - this is the first time the playhead is greater than 0
        
        // If the observer is non nil, it's been already set previously. This can happen in the following case:
        // - Player is created with a non-valid playeritem (here the join listener will be set, but it won't have fired yet)
        // - PlayerItem status is failed
        // - A new PlayerItem is created and replaced in the Player (here is where we don't want to add the time observer)
        if (self.joinTimePeriodicTimeObserver == nil) {
            [self setupJoinCheck];
        }
        
        // Observer for seek
        static double intervalSeek = 2.0;
        
        self.seekDetectionPeriodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(intervalSeek, NSEC_PER_SEC) queue:0 usingBlock:^(CMTime time) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                double currentPlayhead = CMTimeGetSeconds(time);
                
                if (strongSelf.lastPlayhead != 0) {
                    double distance = ABS(strongSelf.lastPlayhead - currentPlayhead);
                    if (distance > intervalSeek * 2) {
                        // Distance is very big -> seeking
                        [YBLog debug:@"Seek with distance: %f", distance];
                        [strongSelf fireSeekBegin:true];
                    } else {
                        // Healthy
                        [strongSelf fireSeekEnd];
                        //[strongSelf fireBufferEnd];
                    }
                }
                strongSelf.lastPlayhead = currentPlayhead;
            }
        }];
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) removeObserversForAVPlayerItem:(AVPlayerItem *) playerItem {
    @try {
        // Check class type to avoid doing anything if it's NSNull
        if (playerItem != nil && [playerItem isKindOfClass:[AVPlayerItem class]]) {
            [playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:observationContext];
            [playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:observationContext];
            [playerItem removeObserver:self forKeyPath:@"status" context:observationContext];
            //[playerItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:observationContext];
        }
        
        if (self.joinTimePeriodicTimeObserver) {
            [self.player removeTimeObserver:self.joinTimePeriodicTimeObserver];
            self.joinTimePeriodicTimeObserver = nil;
        }
        
        if (self.seekDetectionPeriodicTimeObserver) {
            [self.player removeTimeObserver:self.seekDetectionPeriodicTimeObserver];
            self.seekDetectionPeriodicTimeObserver = nil;
        }
        
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    @try {
        if (context == observationContext) {
            AVPlayer * player = self.player;
            
            // AVPlayer properties
            if ([keyPath isEqualToString:@"rate"]) {
                NSNumber * newRate = (NSNumber *) [change objectForKey:NSKeyValueChangeNewKey];
                NSNumber * oldRate = (NSNumber *) [change objectForKey:NSKeyValueChangeOldKey];
                [YBLog debug:@"AVPlayer's rate has changed, old: %@, new: %@", oldRate, newRate];
                
                // We have to check that currentItem is not nil
                // If the player is sent a "play" message, but has no currentItem loaded
                // it will still set the rate to 0
                if (player.currentItem != nil) {
                    if ([newRate isEqualToNumber:@0]) {
                        if([self.getPlayhead intValue] == [self.getDuration intValue]){
                            [YBLog notice:@"paused at the video end, sending stop"];
                            [self fireStop];
                            [self resetValues];
                        }
                        [self firePause];
                    } else {
                        if (self.flags.started) {
                            [self fireResume]; // Resume
                        } else {
                            if([[self getPlayhead] intValue] != [[self getDuration] intValue] ||
                                    (self.plugin != nil && self.plugin.options != nil && [self.plugin.options.contentIsLive isEqual:@YES])){
                                [self fireStart]; // Start
                                if (self.joinTimePeriodicTimeObserver == nil) {
                                    [self setupJoinCheck];
                                }
                            }
                        }
                    }
                }
            } else if ([keyPath isEqualToString:@"currentItem"]) {
                // Player Item has changed (asset being played)
                id newItem = [change objectForKey:NSKeyValueChangeNewKey];
                id oldItem = [change objectForKey:NSKeyValueChangeOldKey];
                [YBLog debug:@"AVPlayer's currentItem has changed, old: %@, new: %@", oldItem, newItem];
                
                if (oldItem != nil && oldItem != [NSNull null]) {
                    // There was a previous item being played
                    // Remove its observers
                    [self removeObserversForAVPlayerItem:oldItem];
                    // Close that view
                    if(self.supportPlaylists == YES){
                        // Close that view
                        [self fireStop];
                        [self resetValues];
                    }
                }
                if (newItem != nil && newItem != [NSNull null]) {
                    // New item
                    if (player.rate != 0) {
                        // If rate is not 0 (it's playing), send start
                        [self fireStart];
                    }
                    // Prepare for new view, this will set set handlers and listeners
                    [self prepareForNewViewWithPlayerItem:newItem];
                }
            } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) { // AVPlayerItem properties
                bool isEmpty = [((NSValue *)[change objectForKey:NSKeyValueChangeNewKey]) isEqual:@YES];
                if (isEmpty) {
                    [YBLog debug:@"AVPlayer playbackBufferEmpty"];
                    if(!self.flags.paused){
                        //[self fireBufferBegin];
                    }
                }
            } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
                bool isLikely = [((NSValue *)[change objectForKey:NSKeyValueChangeNewKey]) isEqual:@YES];
                if (isLikely) {
                    [YBLog debug:@"AVPlayer playbackLikelyToKeepUp"];
                    if (self.flags.joined) {
                        if(firstSeek){
                            [self fireSeekEnd];
                            //[self fireBufferEnd];
                        }
                        firstSeek = true;
                    }
                }
            } else if ([keyPath isEqualToString:@"status"]) {
                NSInteger newStatus = ((NSNumber *)[change objectForKey:NSKeyValueChangeNewKey]).integerValue;
                
                if (newStatus == AVPlayerItemStatusFailed) { // If failed
                    // It can be either the status of the player or the status from its currentItem
                    // because both of them are subscribed
                    NSError * error;
                    if (object == player) {
                        [YBLog error:@"Detected error from AVPlayer"];
                        error = player.error;
                    } else if (object == player.currentItem) {
                        [YBLog error:@"Detected error from AVPlayer's currentItem"];
                        error = player.currentItem.error;
                    }
                    
                    if([self.fatalErrors containsObject:[NSNumber numberWithInteger:error.code]]){
                        [self fireFatalErrorWithMessage:error.localizedDescription code:[NSString stringWithFormat:@"%ld",(long)error.code] andMetadata:nil];
                        //TODO Add this to adapter
                        if(self.plugin != nil && !self.flags.started){
                            [self.plugin fireStop];
                        }
                    }else{
                        [self sendError:error];
                    }
                }
            }
        }
        
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) setupJoinCheck {
    
    __weak typeof(self) weakSelf = self;
    
    CMTime interval = CMTimeMakeWithSeconds(.1, NSEC_PER_SEC); // 100ms
    self.joinTimePeriodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:interval queue:0 usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            if (ABS(CMTimeGetSeconds(time)) > 0.1) {
                if (!self.flags.started) {
                    // Send start if it hasn't been sent yet
                    // this happens when the startMonitoring is called once the video already started
                    firstSeek = true;
                    [strongSelf fireStart];
                }
                
                [YBLog debug:@"YBPluginAVPlayer detected join time at: %f", CMTimeGetSeconds(time)];
                [strongSelf fireJoin];
                
                if (self.flags.joined) {
                    [strongSelf.player removeTimeObserver:strongSelf.joinTimePeriodicTimeObserver];
                    strongSelf.joinTimePeriodicTimeObserver = nil;
                    [YBLog debug:@"Join sent, removed time observer"];
                }
                
            }
        }
    }];

}

- (void) itemDidFinishPlaying:(NSNotification *) notification {
    @try {
        if (notification.object == self.player.currentItem) {
            [YBLog notice:@"itemDidFinishPlaying, stopping"];
            [self fireStop];
            [self resetValues];
        }
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) sendError:(NSError *) error {
    @try {
        if (error != nil) {
            NSInteger code = error.code;
            NSString * desc = error.description;
            NSString * message = error.localizedDescription;
            [YBLog notice:@"Reporting error code: %d", code];
            [self fireErrorWithMessage:message code:@(code).stringValue andMetadata:desc];
            [self resetValues];
        }
    } @catch (NSException *exception) {
        [YBLog logException:exception];
    }
}

- (void) resetValues {
    self.lastPlayhead = 0;
    self.bitrate = -1;
    self.throughput = -1;
    self.supportPlaylists = YES;
    self.rendition = [super getRendition];
    self.lastRenditionBitrate = -1;
}

#pragma mark - Overridden get methods
- (NSNumber *)getPlayhead {
    double playhead = CMTimeGetSeconds(self.player.currentTime);
    return [NSNumber numberWithDouble:playhead];
}

- (NSNumber *)getPlayrate {
    return @(self.player.rate);
}

- (NSNumber *) getDuration {
    AVPlayerItem * item = self.player.currentItem;
    
    // Get default value
    NSNumber * duration = [super getDuration];
    
    if (item != nil) {
        AVURLAsset * asset = (AVURLAsset *) item.asset;
        if (asset != nil) {
            if ([asset statusOfValueForKey:@"duration" error:nil] == AVKeyValueStatusLoaded) {
                duration = @(CMTimeGetSeconds(asset.duration));
            }
        }
    }
    
    return duration;
}

- (NSNumber *)getBitrate {
    
    AVPlayerItemAccessLogEvent * logEvent = self.player.currentItem.accessLog.events.lastObject;
    
    if (logEvent) {
        
        double br;
        
        if (logEvent.segmentsDownloadedDuration > 0) {
            br = logEvent.indicatedBitrate;
        } else {
            br = (logEvent.numberOfBytesTransferred * 8) / logEvent.segmentsDownloadedDuration;
        }
        
        return @(round(br));
    }
    
    return [super getBitrate];
}

- (NSNumber *)getThroughput {
    
    AVPlayerItemAccessLogEvent * logEvent = self.player.currentItem.accessLog.events.lastObject;
    
    if (logEvent && logEvent.observedBitrate > 0) {
        return @(round(logEvent.observedBitrate));
    }
    
    return [super getThroughput];
}

- (NSString *)getRendition {
    
    // We build rendition only if we have bitrate, but it is different from the indicated bitrate
    // For non-manifest streams these two values are equal and we want to avoid sending rendition
    // in those cases
    AVPlayerItemAccessLogEvent * logEvent = self.player.currentItem.accessLog.events.lastObject;

    NSString * rendition = [super getRendition];
    
    if (logEvent) {
        NSNumber * bitrate = [self getBitrate];
        if (logEvent.indicatedBitrate > 0 && bitrate != [super getBitrate]) {
            if (self.lastRenditionBitrate != logEvent.indicatedBitrate) {
                self.lastRenditionBitrate = logEvent.indicatedBitrate;
                rendition = [YBYouboraUtils buildRenditionStringWithWidth:0 height:0 andBitrate:logEvent.indicatedBitrate];
            }
        }
    }
    
    return rendition;
}

- (NSString *)getResource {
    
    AVPlayerItem * item = self.player.currentItem;
    
    NSString * res = nil;
    
    if (item != nil) {
        AVURLAsset * asset = (AVURLAsset *) item.asset;
        if (asset != nil) {
            res = asset.URL.absoluteString;
        }
    }
    return res != nil? res : [super getResource];
}

- (NSString *)getPlayerName {
    return PLUGIN_NAME;
}

- (NSString *)getPlayerVersion {
    return @PLUGIN_NAME_DEF;
}

- (NSString *)getVersion {
    return PLUGIN_VERSION;
}

//Static method as a workaround for swift
+ (YBAVPlayerAdapter*) instantiateWithPlayer:(AVPlayer*) player{
    return [[YBAVPlayerAdapter alloc] initWithPlayer:player];
}

@end
