#ifndef EKPANELD_H
#define EKPANELD_H

#import "EKPanel.h"

// Where the daemon keeps its result for the app to read.
#define EKPANEL_RESULT_PATH \
    "/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.result.plist"

// Keys of the result plist.
#define EKPANEL_RESULT_STATE     "state"      // "enabled" | "disabled" | "error"
#define EKPANEL_RESULT_MESSAGE   "message"    // human readable
#define EKPANEL_RESULT_MARKER    "markerPath" // absolute path used
#define EKPANEL_RESULT_TIME      "time"       // unix seconds

#endif /* EKPANELD_H */
