// Shared definitions for ellekit-panel: the app and the root daemon.
#ifndef EKPANEL_H
#define EKPANEL_H

#import <Foundation/Foundation.h>

// The marker Dopamine's systemhook checks before injecting any tweak.
// Logical (jbroot-relative) path; resolve with EKPanelSafeModePath().
#define EKPANEL_SAFE_MODE_PATH "/basebin/.safe_mode"

// A file the app may write (it runs as mobile) and the root daemon reads.
// Logical path under the bootstrap; the app resolves it the same way.
#define EKPANEL_REQUEST_PATH "/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.request.plist"

// Allowed actions in a request.
#define EKPANEL_ACTION_ENABLE  "enable"   // create .safe_mode
#define EKPANEL_ACTION_DISABLE "disable"  // remove .safe_mode
#define EKPANEL_ACTION_STATUS  "status"   // read only
#define EKPANEL_ACTION_RESPRING "respring" // restart SpringBoard

// The bootstrap root as the kernel spells it, or nil when it cannot be
// found. Never persisted: roothide renames the jbroot at every jailbreak.
NSString *EKPanelBootstrapRoot(void);

// A bootstrap path (/basebin/.safe_mode) made absolute for this process.
NSString *EKPanelBootstrapPath(NSString *path);

// The resolved path of the injection marker, or nil.
NSString *EKPanelSafeModePath(void);

#endif /* EKPANEL_H */
