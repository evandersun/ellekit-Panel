// ekpaneld — the root half of ellekit-panel.
//
// The app runs as mobile and cannot write /basebin (root:wheel 0755, and the
// jailbreak's sandbox denies it). This daemon runs as root from launchd, with
// the bootstrap's entitlements, watches a file the app owns, and creates or
// removes the marker Dopamine's systemhook checks before it injects anything.

#import "ekpanel.h"
#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <stdarg.h>

static NSString *markerPath(void) {
    return EKPanelSafeModePath() ?: @EKPANEL_SAFE_MODE_PATH;
}

static BOOL markerEnabled(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0;
}

// Appends one timestamped line to the log, when logging is on.
static void EKLog(NSString *format, ...) {
    if (!EKPanelLoggingEnabled()) return;

    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *path = EKPanelLogPath();
    if (path == nil) return;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [fmt stringFromDate:[NSDate date]], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    int fd = open(path.fileSystemRepresentation, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, data.bytes, data.length);
    close(fd);
}

static unsigned long long fileSize(NSString *path) {
    struct stat st;
    if (path == nil || stat(path.fileSystemRepresentation, &st) != 0) return 0;
    return (unsigned long long)st.st_size;
}

// The per-process memory addends, as a plain dictionary.
static NSDictionary *jetsamTable(void) {
    NSString *p = EKPanelBootstrapPath(@EKPANEL_JETSAM_PATH);
    if (p == nil) return @{};
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
    return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}

static void EKWriteResult(NSString *state, NSString *message);

// Choicy's per-app settings, read from the file its dylib itself reads.
static NSString *choicyPath(void) {
    return EKPanelBootstrapPath(@EKPANEL_CHOICY_PATH) ?: @EKPANEL_CHOICY_PATH;
}

static NSDictionary *choicyDocument(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:choicyPath()];
    return [d isKindOfClass:[NSDictionary class]] ? d : @{};
}

static NSDictionary *choicySettings(void) {
    NSDictionary *s = choicyDocument()[@"appSettings"];
    return [s isKindOfClass:[NSDictionary class]] ? s : @{};
}

// Writes the per-app table back, leaving Choicy's other keys alone.
static int applyChoicy(NSDictionary *incoming) {
    NSString *p = choicyPath();
    NSMutableDictionary *document = [choicyDocument() mutableCopy];
    if (document == nil) document = [NSMutableDictionary dictionary];

    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    for (id key in incoming) {
        if (![key isKindOfClass:[NSString class]]) continue;
        id entry = incoming[key];
        if ([entry isKindOfClass:[NSDictionary class]]) clean[key] = entry;
    }
    document[@"appSettings"] = clean;
    if (document[@"preferenceVersion"] == nil) document[@"preferenceVersion"] = @1;

    if (![document writeToFile:p atomically:YES]) {
        EKWriteResult(@"error", [NSString stringWithFormat:
            @"Could not write %@ (errno %d).", p, errno]);
        return 1;
    }
    chmod(p.fileSystemRepresentation, 0644);

    NSUInteger off = 0;
    for (NSDictionary *e in clean.allValues) {
        if ([e[@"tweakInjectionDisabled"] boolValue]) off++;
    }
    EKLog(@"choicy: saved %lu app entr%@, %lu with tweaks off",
          (unsigned long)clean.count, clean.count == 1 ? @"y" : @"ies", (unsigned long)off);
    EKWriteResult(markerEnabled(markerPath()) ? @"enabled" : @"disabled",
                  @"Per-app settings saved. They apply the next time each app starts.");
    return 0;
}

static void EKWriteResult(NSString *state, NSString *message) {
    NSString *path = EKPanelBootstrapPath(@EKPANEL_RESULT_PATH);
    if (path == nil) path = @EKPANEL_RESULT_PATH;
    NSString *marker = markerPath();
    NSDictionary *d = @{
        @EKPANEL_RESULT_STATE : state ?: @"error",
        @EKPANEL_RESULT_MESSAGE : message ?: @"",
        @EKPANEL_RESULT_MARKER : marker ?: @"",
        @EKPANEL_RESULT_TIME : @([[NSDate date] timeIntervalSince1970]),
        @EKPANEL_RESULT_LOGGING : @(EKPanelLoggingEnabled()),
        @EKPANEL_RESULT_LOGSIZE : @(fileSize(EKPanelLogPath())),
        @EKPANEL_RESULT_JETSAM : jetsamTable(),
        @EKPANEL_RESULT_CHOICY : choicySettings(),
    };
    [d writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0644);
}

// Writes the addend table, dropping entries that are not a number.
static int applyJetsam(NSDictionary *incoming) {
    NSString *p = EKPanelBootstrapPath(@EKPANEL_JETSAM_PATH);
    if (p == nil) {
        EKWriteResult(@"error", @"Cannot resolve the jetsam file path.");
        return 1;
    }

    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    for (id key in incoming) {
        if (![key isKindOfClass:[NSString class]]) continue;
        id value = incoming[key];
        if ([value isKindOfClass:[NSNumber class]]) {
            clean[key] = @([value longLongValue]);
        }
    }

    if (clean.count == 0) {
        unlink(p.fileSystemRepresentation);
        EKLog(@"jetsam: table cleared");
        EKWriteResult(markerEnabled(markerPath()) ? @"enabled" : @"disabled",
                      @"Jetsam table cleared.");
        return 0;
    }

    if (![clean writeToFile:p atomically:YES]) {
        EKWriteResult(@"error", [NSString stringWithFormat:
            @"Could not write %@ (errno %d).", p, errno]);
        return 1;
    }
    chmod(p.fileSystemRepresentation, 0644);

    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in [clean.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"%@ %+lldMB", key,
                          [clean[key] longLongValue]]];
    }
    EKLog(@"jetsam: saved %@", [parts componentsJoinedByString:@", "]);
    EKWriteResult(markerEnabled(markerPath()) ? @"enabled" : @"disabled",
                  @"Jetsam table saved. It applies to processes started from now on.");
    return 0;
}

static int applyAction(NSString *action, NSDictionary *request) {
    NSString *p = markerPath();

    if ([action isEqualToString:@EKPANEL_ACTION_ENABLE]) {
        if (markerEnabled(p)) {
            EKWriteResult(@"enabled", @"Injection is already off.");
            return 0;
        }
        int fd = open(p.fileSystemRepresentation, O_CREAT | O_WRONLY, 0644);
        if (fd < 0) {
            EKWriteResult(@"error", [NSString stringWithFormat:
                @"Could not create %@ (errno %d).", p, errno]);
            return 1;
        }
        close(fd);
        EKLog(@"injection: OFF (marker created at %@)", p);
        EKWriteResult(@"enabled", @"Injection turned off. Restart SpringBoard to apply.");
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_DISABLE]) {
        if (!markerEnabled(p)) {
            EKWriteResult(@"disabled", @"Injection is already on.");
            return 0;
        }
        if (unlink(p.fileSystemRepresentation) != 0) {
            EKWriteResult(@"error", [NSString stringWithFormat:
                @"Could not remove %@ (errno %d).", p, errno]);
            return 1;
        }
        EKLog(@"injection: ON (marker removed)");
        EKWriteResult(@"disabled", @"Injection turned on. Restart SpringBoard to apply.");
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_RESPRING]) {
        BOOL on = markerEnabled(p);
        pid_t pid = 0;
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
        size_t size = 0;
        if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0) {
            struct kinfo_proc *procs = malloc(size);
            if (procs && sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
                size_t count = size / sizeof(struct kinfo_proc);
                for (size_t i = 0; i < count; i++) {
                    if (strncmp(procs[i].kp_proc.p_comm, "SpringBoard", MAXCOMLEN) == 0) {
                        pid = procs[i].kp_proc.p_pid;
                        break;
                    }
                }
            }
            free(procs);
        }
        if (pid <= 0) {
            EKWriteResult(@"error", @"SpringBoard is not running.");
            return 1;
        }
        EKWriteResult(on ? @"enabled" : @"disabled",
                      on ? @"Restarting SpringBoard with injection off."
                         : @"Restarting SpringBoard.");
        EKLog(@"respring: signalling SpringBoard (pid %d, SIGTERM), injection %@",
              pid, on ? @"OFF" : @"ON");
        kill(pid, SIGTERM);
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_CHOICY]) {
        NSDictionary *table = request[@"choicy"];
        if (![table isKindOfClass:[NSDictionary class]]) {
            EKWriteResult(@"error", @"The request had no per-app settings.");
            return 1;
        }
        return applyChoicy(table);
    }

    if ([action isEqualToString:@EKPANEL_ACTION_JETSAM]) {
        NSDictionary *table = request[@"jetsam"];
        if (![table isKindOfClass:[NSDictionary class]]) {
            EKWriteResult(@"error", @"The request had no jetsam table.");
            return 1;
        }
        return applyJetsam(table);
    }

    if ([action isEqualToString:@EKPANEL_ACTION_TRIMLOG]) {
        NSString *log = EKPanelLogPath();
        if (log) unlink(log.fileSystemRepresentation);
        EKLog(@"log cleared");
        EKWriteResult(markerEnabled(p) ? @"enabled" : @"disabled", @"Log cleared.");
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_LOGON]) {
        EKPanelSetLogging(YES);
        EKLog(@"logging: on (%@)", EKPanelLogPath());
        EKWriteResult(markerEnabled(p) ? @"enabled" : @"disabled", @"Logging on.");
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_LOGOFF]) {
        EKLog(@"logging: off");
        EKPanelSetLogging(NO);
        EKWriteResult(markerEnabled(p) ? @"enabled" : @"disabled", @"Logging off.");
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_STATUS]) {
        BOOL on = markerEnabled(p);
        EKWriteResult(on ? @"enabled" : @"disabled",
                      on ? @"Injection is off." : @"Injection is on.");
        return 0;
    }

    EKWriteResult(@"error", [NSString stringWithFormat:
        @"Unknown action: %@", action ?: @"(none)"]);
    return 1;
}

// Applies the request the app wrote, then deletes it so the same instruction
// never runs twice. YES when one was handled.
static BOOL handleRequest(void) {
    NSString *reqPath = EKPanelBootstrapPath(@EKPANEL_REQUEST_PATH);
    if (reqPath == nil) return NO;
    struct stat st;
    if (lstat(reqPath.fileSystemRepresentation, &st) != 0) return NO;

    NSDictionary *req = [NSDictionary dictionaryWithContentsOfFile:reqPath];
    unlink(reqPath.fileSystemRepresentation);

    NSString *action = req[@"action"];
    if (![action isKindOfClass:[NSString class]]) {
        EKWriteResult(@"error", @"The request had no action.");
        return YES;
    }
    applyAction(action, req);
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // One-shot mode: used by the package's postinst and for testing.
        if (argc > 2 && strcmp(argv[1], "--apply") == 0) {
            return applyAction(@(argv[2]), @{});
        }
        if (argc > 1 && strcmp(argv[1], "--status") == 0) {
            return applyAction(@EKPANEL_ACTION_STATUS, @{});
        }
        if (argc > 1) {
            fprintf(stderr, "usage: ekpaneld [--apply enable|disable|respring|status]"
                            " [--status]\n");
            return 2;
        }

        signal(SIGPIPE, SIG_IGN);
        EKLog(@"helper started (injection %@)",
              markerEnabled(markerPath()) ? @"OFF" : @"ON");
        EKWriteResult(markerEnabled(markerPath()) ? @"enabled" : @"disabled",
                      @"Helper started.");
        handleRequest();

        // Poll: watching a file that usually does not exist costs nothing,
        // and the app needs no mach service or entitlement to reach us.
        for (;;) {
            @autoreleasepool {
                handleRequest();
            }
            usleep(300 * 1000);
        }
    }
    return 0;
}
