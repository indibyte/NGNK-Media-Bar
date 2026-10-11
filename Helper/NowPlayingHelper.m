// Runs inside /usr/bin/perl (see NowPlaying.swift). Since macOS 15.4, MediaRemote only returns Now Playing
// info to Apple-signed processes, so the app loads this into perl and talks to it over pipes:
//   stdout: one JSON line per change: {"title", "artist", "playing", "pid", "art" (base64, optional)}
//   stdin:  one MediaRemote command number per line (2 play/pause, 4 next, 5 previous)
// Exits when stdin closes, i.e. when the app quits.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (^InfoBlock)(CFDictionaryRef);
typedef void (^PIDBlock)(int);
typedef void (^BoolBlock)(Boolean);

static void (*getInfo)(dispatch_queue_t, InfoBlock);
static void (*getPID)(dispatch_queue_t, PIDBlock);
static void (*getIsPlaying)(dispatch_queue_t, BoolBlock);
static Boolean (*sendCommand)(uint32_t, CFDictionaryRef);

static NSDictionary *snapshot(void) {
    dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block int pid = 0;
    __block Boolean playing = false;
    __block NSDictionary *info = nil;
    getPID(q, ^(int p) { pid = p; dispatch_semaphore_signal(done); });
    getIsPlaying(q, ^(Boolean b) { playing = b; dispatch_semaphore_signal(done); });
    getInfo(q, ^(CFDictionaryRef d) { info = [(__bridge NSDictionary *)d copy]; dispatch_semaphore_signal(done); });
    for (int i = 0; i < 3; i++)
        if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC))) return nil;

    NSString *k = @"kMRMediaRemoteNowPlayingInfo";
    NSMutableDictionary *out = [@{@"title": info[[k stringByAppendingString:@"Title"]] ?: @"",
                                  @"artist": info[[k stringByAppendingString:@"Artist"]] ?: @"",
                                  @"playing": @(playing), @"pid": @(pid)} mutableCopy];
    NSData *art = info[[k stringByAppendingString:@"ArtworkData"]];
    if ([art isKindOfClass:NSData.class] && art.length) out[@"art"] = [art base64EncodedStringWithOptions:0];
    return out;
}

__attribute__((visibility("default"))) void run(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getPID = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    getIsPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    if (!getInfo || !getPID || !getIsPlaying || !sendCommand) exit(1);

    [NSThread detachNewThreadWithBlock:^{
        char line[32];
        while (fgets(line, sizeof line, stdin)) sendCommand((uint32_t)atoi(line), NULL);
        exit(0);
    }];

    NSData *last = nil;
    for (;;) {
        @autoreleasepool {
            NSDictionary *s = snapshot();
            NSData *json = s ? [NSJSONSerialization dataWithJSONObject:s options:0 error:nil] : nil;
            if (json && ![json isEqualToData:last]) {
                last = json;
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            }
        }
        sleep(1);
    }
}
