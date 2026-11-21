// Per-app tweak control, backed by the settings of the installed Choicy
// (com.opa334.choicys, MIT licence). This screen only edits the table; the
// dylib Choicy already injects is what enforces it.

#import <UIKit/UIKit.h>

@interface EKChoicyController : UITableViewController

// `settings` is Choicy's appSettings dictionary; `onSave` receives the whole
// dictionary whenever the user changes something.
- (instancetype)initWithSettings:(NSDictionary *)settings
                          onSave:(void (^)(NSDictionary *settings))onSave;
@end
