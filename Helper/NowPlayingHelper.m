// Liest "Jetzt läuft" über das private MediaRemote-Framework.
// Seit macOS 15.4 erlaubt Apple das nur noch Apple-eigenen Prozessen – deshalb wird
// diese Bibliothek von /usr/bin/perl geladen (siehe nowplaying.pl) und gibt JSON-Zeilen aus.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(int, NSDictionary *);
typedef void (*SeekFn)(double);

static CFBundleRef mr;
static NSString *lastLine;
static NSUInteger lastArtHash;
static NSUInteger emitGeneration;

static void *fn(const char *name) {
    if (!mr) {
        NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
        mr = CFBundleCreate(NULL, (__bridge CFURLRef)url);
    }
    return CFBundleGetFunctionPointerForName(mr, (__bridge CFStringRef)[NSString stringWithUTF8String:name]);
}

static void emit(void) {
    GetInfoFn getInfo = fn("MRMediaRemoteGetNowPlayingInfo");
    GetPIDFn getPID = fn("MRMediaRemoteGetNowPlayingApplicationPID");
    GetPlayingFn getPlaying = fn("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    dispatch_queue_t q = dispatch_get_main_queue();

    getPID(q, ^(int pid) {
        getPlaying(q, ^(BOOL playing) {
            getInfo(q, ^(NSDictionary *info) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"pid"] = @(pid);
                out[@"playing"] = @(playing);
                NSRunningApplication *app = pid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;
                if (app.bundleIdentifier) out[@"bundleID"] = app.bundleIdentifier;
                if (app.bundleURL.path) out[@"appPath"] = app.bundleURL.path;
                NSDictionary *keys = @{
                    @"kMRMediaRemoteNowPlayingInfoTitle": @"title",
                    @"kMRMediaRemoteNowPlayingInfoArtist": @"artist",
                    @"kMRMediaRemoteNowPlayingInfoAlbum": @"album",
                    @"kMRMediaRemoteNowPlayingInfoDuration": @"duration",
                    @"kMRMediaRemoteNowPlayingInfoElapsedTime": @"elapsed",
                    @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @"rate",
                };
                for (NSString *k in keys) {
                    id v = info[k];
                    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) out[keys[k]] = v;
                }
                NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([ts isKindOfClass:NSDate.class]) out[@"timestamp"] = @(ts.timeIntervalSince1970);
                // Cover nur mitschicken, wenn es sich geändert hat (ist ~200 KB gross)
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSUInteger artHash = [art isKindOfClass:NSData.class] ? art.length ^ art.hash : 0;

                NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
                BOOL artChanged = artHash != 0 && artHash != lastArtHash;
                if (!line || ([line isEqualToString:lastLine] && !artChanged)) return;
                lastLine = line;
                if (artChanged) {
                    lastArtHash = artHash;
                    out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                    json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                    line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
                }
                printf("%s\n", line.UTF8String);
                fflush(stdout);
            });
        });
    });
}

/// Mehrere Benachrichtigungen kurz hintereinander → nur einmal abfragen.
/// (Players melden oft 3–4 Änderungen auf einmal, teils mit kurz falschem Zustand.)
static void scheduleEmit(void) {
    NSUInteger generation = ++emitGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == emitGeneration) emit();
    });
}

/// Läuft endlos und gibt bei jeder Änderung eine JSON-Zeile aus
void nodge_stream(void) {
    RegisterFn reg = fn("MRMediaRemoteRegisterForNowPlayingNotifications");
    reg(dispatch_get_main_queue());
    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    ];
    for (NSString *name in names) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *n) { scheduleEmit(); }];
    }
    // Sicherheitsnetz, falls eine Benachrichtigung ausbleibt (Änderungen kommen sonst sofort)
    NSTimer *safety = [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *t) { emit(); }];
    safety.tolerance = 5;
    emit();
    // Beenden, sobald Nodge weg ist (stdin geschlossen)
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(src, ^{
        char buf[64];
        if (read(0, buf, sizeof buf) <= 0) exit(0);
    });
    dispatch_resume(src);
    CFRunLoopRun();
}

/// Steuerbefehl senden bzw. mit NODGE_MR_SEEK=<Sekunden> spulen (0 play, 1 pause, 4 nächster, 5 vorheriger).
/// Hinweis: 2 (play/pause umschalten) wird von neueren macOS-Versionen ignoriert,
/// und ohne leeres Options-Dictionary kommen Befehle nicht an.
void nodge_send(void) {
    const char *cmd = getenv("NODGE_MR_COMMAND");
    const char *seek = getenv("NODGE_MR_SEEK");
    SendFn send = fn("MRMediaRemoteSendCommand");
    SeekFn setElapsed = fn("MRMediaRemoteSetElapsedTime");
    if (seek && setElapsed) setElapsed(atof(seek));      // an Position (Sekunden) springen
    else if (cmd && send) send(atoi(cmd), @{});
    // Der Befehl wird asynchron zugestellt – kurz warten, bevor der Prozess endet
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.4, false);
}
