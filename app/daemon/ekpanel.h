#ifndef EKPANELD_H
#define EKPANELD_H

#import "EKPanel.h"

// Where the daemon keeps its result for the app to read.
#define EKPANEL_RESULT_PATH \
    "/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.result.plist"

// Keys of the result plist.
#define EKPANEL_RESULT_STATE    "state"     // "enabled" | "disabled" | "error"
#define EKPANEL_RESULT_MESSAGE  "message"   // human readable
#define EKPANEL_RESULT_MARKER   "markerPath"
#define EKPANEL_RESULT_TIME     "time"
#define EKPANEL_RESULT_LOGGING  "logging"   // @YES when the log is on
#define EKPANEL_RESULT_LOGSIZE  "logSize"   // bytes
#define EKPANEL_RESULT_JETSAM   "jetsam"    // { process path : megabytes }

#endif /* EKPANELD_H */
