#import <AVFoundation/AVFoundation.h>
#import <notify.h>

// PleaseDontStopTheMusic
//
// Default rule (every app except TikTok): when other audio is already playing,
// the "intruder" app is forced to MixWithOthers so it joins the music as a
// *secondary* source. The music app stays primary and keeps its lock-screen /
// Control Center "Now Playing" controls. This is the proven v2.2.0 behaviour and
// is left completely untouched.
//
// Special case — TikTok Live PiP: TikTok Live uses a sample-buffer Picture-in-
// Picture renderer that only advances video frames while its audio session is
// the *primary* (hardware-clock) source. Forcing it to mix freezes the PiP
// video. So TikTok is kept primary, and — only while TikTok is in the
// foreground — it sends a one-shot Darwin notification telling the background
// music app to make ITS OWN session secondary (MixWithOthers) so TikTok's
// primary session does not interrupt it. Net result: PiP video plays and the
// music keeps going.
//
// Important: nothing here ever makes another app *seize* the primary session, so
// it can never re-introduce the "intruder pauses your music" bug. The only app
// that stays primary is TikTok itself.

static BOOL gIsVideoApp    = NO;   // TikTok: kept primary so its PiP clock runs
static BOOL gSessionActive = NO;   // tracks setActive: state (are we playing?)

static NSString *const kBegin = @"com.pdstm.pip.begin";

static BOOL PDSTMShouldMix(AVAudioSession *s) {
    if (gIsVideoApp) return NO;        // TikTok stays primary
    return s.isOtherAudioPlaying;      // everyone else: exactly the v2.2.0 rule
}

static void PDSTMPost(NSString *name) { notify_post(name.UTF8String); }

// Music side: TikTok is foreground and wants the primary session. If we are the
// background app currently playing, make our session secondary (one shot) so we
// keep playing instead of being interrupted. We never seize primary back here —
// that is what previously broke Twitter/YouTube/Dr Driving.
static void PDSTMGoSecondary(void) {
    if (gIsVideoApp) return;
    AVAudioSession *s = [AVAudioSession sharedInstance];
    NSString *cat = s.category;
    BOOL playbackish = [cat isEqualToString:AVAudioSessionCategoryPlayback]
                    || [cat isEqualToString:AVAudioSessionCategoryPlayAndRecord];
    if (!gSessionActive || !playbackish) return;
    if (s.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers) return;
    [s setCategory:cat mode:s.mode
           options:(s.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers) error:nil];
    [s setActive:YES error:nil];
}

static void PDSTMDarwinCallback(CFNotificationCenterRef c, void *obs, CFStringRef name,
                                const void *obj, CFDictionaryRef info) {
    if ([(__bridge NSString *)name isEqualToString:kBegin]) PDSTMGoSecondary();
}

%hook AVAudioSession

- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient])
            return %orig(AVAudioSessionCategoryAmbient, outError);
        if ([category isEqualToString:AVAudioSessionCategoryPlayback])
            return [self setCategory:category mode:AVAudioSessionModeDefault
                             options:AVAudioSessionCategoryOptionMixWithOthers error:outError];
    }
    return %orig;
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, options, outError);
}

- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, mode, policy, options, outError);
}

- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    if (PDSTMShouldMix(self)) {
        if ([category isEqualToString:AVAudioSessionCategorySoloAmbient]) category = AVAudioSessionCategoryAmbient;
        options |= AVAudioSessionCategoryOptionMixWithOthers;
    }
    return %orig(category, options, outError);
}

- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    gSessionActive = active;
    if (gIsVideoApp && active && self.isOtherAudioPlaying) PDSTMPost(kBegin);
    if (active && PDSTMShouldMix(self)
        && !(self.categoryOptions & AVAudioSessionCategoryOptionMixWithOthers)) {
        NSString *cat = self.category;
        if ([cat isEqualToString:AVAudioSessionCategorySoloAmbient]) cat = AVAudioSessionCategoryAmbient;
        [self setCategory:cat mode:self.mode
                  options:self.categoryOptions | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    }
    return %orig;
}

%end

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    NSArray *video = @[ @"com.zhiliaoapp.musically",       // TikTok
                        @"com.zhiliaoapp.musically.go",
                        @"com.ss.iphone.ugc.Ame" ];        // TikTok (other region)
    gIsVideoApp = [video containsObject:bid];

    if (gIsVideoApp) {
        // TikTok only posts (never observes). Tell the background music app to go
        // secondary as TikTok comes to the foreground, before TikTok's Live audio
        // seizes the primary session.
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationDidBecomeActiveNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UIApplicationWillEnterForegroundNotification"
            object:nil queue:nil usingBlock:^(NSNotification *n) { PDSTMPost(kBegin); }];
        PDSTMPost(kBegin);
    } else {
        // Music app only listens; it never seizes primary on its own.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            PDSTMDarwinCallback, (__bridge CFStringRef)kBegin, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

    NSLog(@"[PleaseDontStopTheMusic] loaded (bundle=%@ video=%d)", bid, gIsVideoApp);
}
