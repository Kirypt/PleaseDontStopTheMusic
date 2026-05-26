#import <AVFoundation/AVFoundation.h>

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if ([category isEqualToString:@"AVAudioSessionCategoryPlayback"]
     || [category isEqualToString:@"AVAudioSessionCategorySoloAmbient"]) {
        return %orig(@"AVAudioSessionCategoryAmbient", outError);
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, mode, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    return %orig(category, options | AVAudioSessionCategoryOptionMixWithOthers, outError);
}

%end

%ctor {
    NSLog(@"AudioMix: loaded — Apps can no longer silence your background audio.");
}
