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

static void EKWriteResult(NSString *state, NSString *message, NSString *marker) {
    NSString *path = EKPanelBootstrapPath(@EKPANEL_RESULT_PATH);
    if (path == nil) path = @EKPANEL_RESULT_PATH;
    NSDictionary *d = @{
        @EKPANEL_RESULT_STATE : state ?: @"error",
        @EKPANEL_RESULT_MESSAGE : message ?: @"",
        @EKPANEL_RESULT_MARKER : marker ?: @"",
        @EKPANEL_RESULT_TIME : @([[NSDate date] timeIntervalSince1970]),
    };
    [d writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0644);
}

static NSString *markerPath(void) {
    return EKPanelSafeModePath() ?: @EKPANEL_SAFE_MODE_PATH;
}

static BOOL markerEnabled(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0;
}

// The pid of the process whose name matches `name`, or -1.
// MAXCOMLEN truncates names in kinfo_proc, so compare up to that length.
static pid_t EKFindProcess(const char *name) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) return -1;

    struct kinfo_proc *procs = malloc(size);
    if (procs == NULL) return -1;
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) {
        free(procs);
        return -1;
    }

    pid_t found = -1;
    size_t count = size / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        if (strncmp(procs[i].kp_proc.p_comm, name, MAXCOMLEN) == 0) {
            found = procs[i].kp_proc.p_pid;
            break;
        }
    }
    free(procs);
    return found;
}

static int applyAction(NSString *action) {
    NSString *p = markerPath();

    if ([action isEqualToString:@EKPANEL_ACTION_ENABLE]) {
        if (markerEnabled(p)) {
            EKWriteResult(@"enabled", @"Injection is already off.", p);
            return 0;
        }
        int fd = open(p.fileSystemRepresentation, O_CREAT | O_WRONLY, 0644);
        if (fd < 0) {
            EKWriteResult(@"error", [NSString stringWithFormat:
                @"Could not create %@ (errno %d).", p, errno], p);
            return 1;
        }
        close(fd);
        EKWriteResult(@"enabled", @"Injection turned off. Restart SpringBoard to apply.", p);
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_DISABLE]) {
        if (!markerEnabled(p)) {
            EKWriteResult(@"disabled", @"Injection is already on.", p);
            return 0;
        }
        if (unlink(p.fileSystemRepresentation) != 0) {
            EKWriteResult(@"error", [NSString stringWithFormat:
                @"Could not remove %@ (errno %d).", p, errno], p);
            return 1;
        }
        EKWriteResult(@"disabled", @"Injection turned on. Restart SpringBoard to apply.", p);
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_RESPRING]) {
        BOOL on = markerEnabled(p);
        // launchd respawns SpringBoard, and the marker decides what it gets.
        // SIGTERM lets it shut down cleanly; SIGKILL would look like a crash to
        // the jailbreak's watchdog hook and to iOS's crash reporting.
        pid_t sb = EKFindProcess("SpringBoard");
        if (sb <= 0) {
            EKWriteResult(@"error", @"SpringBoard is not running.", p);
            return 1;
        }
        EKWriteResult(on ? @"enabled" : @"disabled",
                      on ? @"Restarting SpringBoard with injection off."
                         : @"Restarting SpringBoard.", p);
        if (kill(sb, SIGTERM) != 0) {
            EKWriteResult(@"error", [NSString stringWithFormat:
                @"Could not signal SpringBoard (errno %d).", errno], p);
            return 1;
        }
        return 0;
    }

    if ([action isEqualToString:@EKPANEL_ACTION_STATUS]) {
        BOOL on = markerEnabled(p);
        EKWriteResult(on ? @"enabled" : @"disabled",
                      on ? @"Injection is off." : @"Injection is on.", p);
        return 0;
    }

    EKWriteResult(@"error", [NSString stringWithFormat:
        @"Unknown action: %@", action ?: @"(none)"], p);
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
        EKWriteResult(@"error", @"The request had no action.", markerPath());
        return YES;
    }
    applyAction(action);
    return YES;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // One-shot mode: used by the package's postinst and for testing.
        if (argc > 2 && strcmp(argv[1], "--apply") == 0) {
            return applyAction(@(argv[2]));
        }
        if (argc > 1 && strcmp(argv[1], "--status") == 0) {
            return applyAction(@EKPANEL_ACTION_STATUS);
        }
        if (argc > 1) {
            fprintf(stderr, "usage: ekpaneld [--apply enable|disable|respring|status]"
                            " [--status]\n");
            return 2;
        }

        signal(SIGPIPE, SIG_IGN);
        EKWriteResult(markerEnabled(markerPath()) ? @"enabled" : @"disabled",
                      @"Helper started.", markerPath());
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
