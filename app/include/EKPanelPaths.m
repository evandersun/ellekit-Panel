#import "EKPanel.h"
#import <dlfcn.h>
#import <sys/stat.h>
#import <limits.h>

// roothide keeps the bootstrap under a randomly named .jbroot- directory.
// A binary inside it finds it from its own image path; one outside it (the
// app, which lives in its own container) has to follow /var/jb instead.
static NSString *EKPanelRootFromImage(void) {
    static const char anchor = 0;
    Dl_info info;
    if (dladdr(&anchor, &info) == 0 || info.dli_fname == NULL) return nil;
    NSArray<NSString *> *parts =
        [@(info.dli_fname) componentsSeparatedByString:@"/"];
    for (NSUInteger i = 0; i < parts.count; i++) {
        if ([parts[i] hasPrefix:@".jbroot-"]) {
            return [[parts subarrayWithRange:NSMakeRange(0, i + 1)]
                componentsJoinedByString:@"/"];
        }
    }
    return nil;
}

// /var/jb is a symbolic link to the bootstrap root on roothide; the kernel
// path behind it is the one our own code can open.
static NSString *EKPanelRootFromVarJb(void) {
    char buf[PATH_MAX];
    ssize_t n = readlink("/var/jb", buf, sizeof(buf) - 1);
    if (n <= 0) return nil;
    buf[n] = '\0';
    NSString *target = @(buf);
    if (![target isAbsolutePath]) {
        target = [[@"/var/jb" stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:target];
    }
    return [target stringByStandardizingPath];
}

NSString *EKPanelBootstrapRoot(void) {
#ifdef APELIN_BOOTSTRAP_ROOTHIDE
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *found = EKPanelRootFromImage();
        if (found == nil) found = EKPanelRootFromVarJb();
        // Only accept a root that exists and holds the jailbreak.
        if (found != nil) {
            NSString *probe = [found stringByAppendingPathComponent:@"basebin"];
            struct stat st;
            if (stat(probe.fileSystemRepresentation, &st) != 0) found = nil;
        }
        root = found;
    });
    return root;
#else
    return @"/var/jb";
#endif
}

NSString *EKPanelBootstrapPath(NSString *path) {
    NSString *root = EKPanelBootstrapRoot();
    return root == nil ? nil : [root stringByAppendingString:path];
}

NSString *EKPanelSafeModePath(void) {
    return EKPanelBootstrapPath(@EKPANEL_SAFE_MODE_PATH);
}
