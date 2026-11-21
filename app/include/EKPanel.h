// Shared definitions for ellekit-panel: the app and the root daemon.
#ifndef EKPANEL_H
#define EKPANEL_H

#import <Foundation/Foundation.h>

// The marker the jailbreak's systemhook checks before injecting any tweak.
// Logical (jbroot-relative) path; resolve with EKPanelBootstrapPath().
#define EKPANEL_SAFE_MODE_PATH  "/basebin/.safe_mode"

// The one file the app and the daemon exchange instructions through.
#define EKPANEL_REQUEST_PATH \
    "/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.request.plist"

// Written by the app when logging is on; the daemon appends to the log
// while it exists, so either side can turn logging off.
#define EKPANEL_LOG_FLAG_PATH \
    "/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.logging"

// Where the daemon keeps the log.
#define EKPANEL_LOG_PATH  "/var/log/extensionloader.log"

// Choicy keeps its per-app tweak settings here; its injected dylib reads
// this file directly, so writing it is enough.
#define EKPANEL_CHOICY_PATH \
    "/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"

// Per-process memory addends the injection layer reads at spawn time.
#define EKPANEL_JETSAM_PATH \
    "/var/mobile/Library/RootHide/cn.zqbb.jetsam.addend.plist"

// Actions in a request.
#define EKPANEL_ACTION_ENABLE   "enable"    // create the marker
#define EKPANEL_ACTION_DISABLE  "disable"   // remove the marker
#define EKPANEL_ACTION_STATUS   "status"    // read everything
#define EKPANEL_ACTION_RESPRING "respring"  // restart SpringBoard
#define EKPANEL_ACTION_JETSAM   "jetsam"    // write the addend table
#define EKPANEL_ACTION_CHOICY   "choicy"    // write Choicy per-app settings
#define EKPANEL_ACTION_TRIMLOG  "trimlog"   // empty the log
#define EKPANEL_ACTION_LOGON    "logon"     // logging turned on
#define EKPANEL_ACTION_LOGOFF   "logoff"    // logging turned off

// The bootstrap root as the kernel spells it, or nil when it cannot be
// found. Never persisted: roothide renames the jbroot at every jailbreak.
NSString *EKPanelBootstrapRoot(void);

// A bootstrap path (/basebin/.safe_mode) made absolute for this process.
NSString *EKPanelBootstrapPath(NSString *path);

// The resolved path of the injection marker, or nil.
NSString *EKPanelSafeModePath(void);

// YES when the user turned logging on.
BOOL EKPanelLoggingEnabled(void);

// Turn logging on or off; the app and the daemon both call this.
BOOL EKPanelSetLogging(BOOL on);

// The log's path, resolved.
NSString *EKPanelLogPath(void);

#endif /* EKPANEL_H */
