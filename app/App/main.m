// ellekit-panel — the app half.
//
// A standalone settings app, in the shape the jailbreak apps use: grouped
// rows for tweak injection, a log file, and jetsam memory addends. It runs as
// mobile and cannot write /basebin, so every change goes through ekpaneld.

#import <UIKit/UIKit.h>
#import "EKPanel.h"
#import "ekpanel.h"

static NSString *const kRequestPath = @EKPANEL_REQUEST_PATH;
static NSString *const kResultPath =
    @"/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.result.plist";

enum { kSectionInjection = 0, kSectionLogging, kSectionJetsam, kSectionCount };

@interface EKPanelController : UITableViewController
@end

@implementation EKPanelController {
    NSDictionary *_status;
    NSMutableDictionary *_jetsam;
    NSArray *_jetsamKeys;
    NSLock *_lock;
    BOOL _busy;
}

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _lock = [[NSLock alloc] init];
        _jetsam = [NSMutableDictionary dictionary];
        _jetsamKeys = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ElleKit";
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(refresh)
        name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - talking to the helper

// One exchange with the helper. Serialised: the request and result files are
// shared, so two overlapping calls would clobber each other.
- (NSDictionary *)sendAction:(NSString *)action payload:(NSDictionary *)payload {
    NSString *req = EKPanelBootstrapPath(kRequestPath);
    NSString *res = EKPanelBootstrapPath(kResultPath);
    if (req == nil || res == nil) return nil;

    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    request[@"action"] = action;
    if (payload) [request addEntriesFromDictionary:payload];

    [_lock lock];
    NSDictionary *answer = nil;
    [[NSFileManager defaultManager] removeItemAtPath:res error:NULL];
    if ([request writeToFile:req atomically:YES]) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while ([deadline timeIntervalSinceNow] > 0) {
            NSDictionary *r = [NSDictionary dictionaryWithContentsOfFile:res];
            if (r[@EKPANEL_RESULT_TIME] != nil) { answer = r; break; }
            [NSThread sleepForTimeInterval:0.05];
        }
    }
    [_lock unlock];
    return answer;
}

- (void)apply:(NSDictionary *)r {
    if (r == nil) return;
    _status = r;
    NSDictionary *table = r[@EKPANEL_RESULT_JETSAM];
    if ([table isKindOfClass:[NSDictionary class]]) {
        _jetsam = [table mutableCopy];
        _jetsamKeys = [table.allKeys sortedArrayUsingSelector:@selector(compare:)];
    } else {
        _jetsam = [NSMutableDictionary dictionary];
        _jetsamKeys = @[];
    }
    [self.tableView reloadData];
}

- (void)refresh {
    if (_busy) return;
    _busy = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *r = [self sendAction:@EKPANEL_ACTION_STATUS payload:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            [self apply:r];
        });
    });
}

- (void)runAction:(NSString *)action payload:(NSDictionary *)payload {
    if (_busy) return;
    _busy = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *r = [self sendAction:action payload:payload];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            [self apply:r];
        });
    });
}

#pragma mark - state

- (BOOL)injectionOn {
    NSString *state = _status[@EKPANEL_RESULT_STATE];
    return ![state isEqualToString:@"enabled"];
}

- (BOOL)loggingOn {
    return [_status[@EKPANEL_RESULT_LOGGING] boolValue];
}

- (NSString *)sizeString {
    unsigned long long n = [_status[@EKPANEL_RESULT_LOGSIZE] unsignedLongLongValue];
    if (n < 1024) return [NSString stringWithFormat:@"%llu B", n];
    if (n < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", n / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", n / (1024.0 * 1024.0)];
}

#pragma mark - table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return kSectionCount; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == kSectionInjection) return @"Tweak injection";
    if (s == kSectionLogging) return @"Log";
    return @"Jetsam memory";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == kSectionInjection) {
        return @"A change applies to processes started from now on. "
                "Restart SpringBoard to apply it to SpringBoard and its apps.";
    }
    if (s == kSectionLogging) {
        return @"While on, the helper records what it does to "
                "/var/log/extensionloader.log.";
    }
    return @"Extra memory, in megabytes, granted to each listed process "
            "when it starts. The injection layer reads this table at spawn time.";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == kSectionInjection) return 2;
    if (s == kSectionLogging) return 3;
    return _jetsamKeys.count + 1;
}

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style {
    return [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tv
         cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell;

    if (ip.section == kSectionInjection) {
        if (ip.row == 0) {
            cell = [self cellWithStyle:UITableViewCellStyleSubtitle];
            cell.textLabel.text = @"Injection";
            cell.detailTextLabel.text = [self injectionOn] ? @"On" : @"Off";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [self injectionOn];
            sw.onTintColor = [UIColor systemGreenColor];
            [sw addTarget:self action:@selector(injectionChanged:)
        forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell = [self cellWithStyle:UITableViewCellStyleDefault];
            cell.textLabel.text = @"Restart SpringBoard";
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
        return cell;
    }

    if (ip.section == kSectionLogging) {
        if (ip.row == 0) {
            cell = [self cellWithStyle:UITableViewCellStyleSubtitle];
            cell.textLabel.text = @"Enable log";
            cell.detailTextLabel.text = [self loggingOn] ? @"Writing" : @"Not writing";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [self loggingOn];
            [sw addTarget:self action:@selector(loggingChanged:)
        forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (ip.row == 1) {
            cell = [self cellWithStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = @"var/log/extensionloader.log";
            cell.detailTextLabel.text = [self sizeString];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell = [self cellWithStyle:UITableViewCellStyleDefault];
            cell.textLabel.text = @"Clear log";
            cell.textLabel.textColor = self.view.tintColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
        return cell;
    }

    cell = [self cellWithStyle:UITableViewCellStyleValue1];
    if (ip.row < (NSInteger)_jetsamKeys.count) {
        NSString *key = _jetsamKeys[ip.row];
        cell.textLabel.text = key;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        long long mb = [_jetsam[key] longLongValue];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%+lld MB", mb];
    } else {
        cell.textLabel.text = @"Add a process…";
        cell.textLabel.textColor = self.view.tintColor;
        cell.detailTextLabel.text = @"";
    }
    return cell;
}

#pragma mark - actions

- (void)injectionChanged:(UISwitch *)sw {
    [self runAction:sw.on ? @EKPANEL_ACTION_DISABLE : @EKPANEL_ACTION_ENABLE payload:nil];
}

- (void)loggingChanged:(UISwitch *)sw {
    [self runAction:sw.on ? @EKPANEL_ACTION_LOGON : @EKPANEL_ACTION_LOGOFF payload:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == kSectionInjection && ip.row == 1) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"Restart SpringBoard"
            message:@"SpringBoard will restart. Apps keep running; their tweaks "
                     "are reloaded when they start again."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
            style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Restart"
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                [self runAction:@EKPANEL_ACTION_RESPRING payload:nil];
            }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    if (ip.section == kSectionLogging && ip.row == 2) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"Clear log"
            message:@"The log file is deleted."
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
            style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Clear"
            style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
                [self runAction:@EKPANEL_ACTION_TRIMLOG payload:nil];
            }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    if (ip.section != kSectionJetsam) return;

    if (ip.row >= (NSInteger)_jetsamKeys.count) {
        [self promptAdd];
        return;
    }
    [self promptEdit:_jetsamKeys[ip.row]];
}

- (void)saveJetsam {
    [self runAction:@EKPANEL_ACTION_JETSAM payload:@{@"jetsam": _jetsam}];
}

- (void)promptAdd {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Add process"
        message:@"A process path, as the injection layer spells it, and the "
                 "extra megabytes to grant it."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = @"/SpringBoard";
        t.autocapitalizationType = UITextAutocapitalizationTypeNone;
        t.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.placeholder = @"64";
        t.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Add"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *path = a.textFields[0].text ?: @"";
            NSString *num = a.textFields[1].text ?: @"";
            if (path.length == 0 || num.length == 0) return;
            self->_jetsam[path] = @([num longLongValue]);
            [self saveJetsam];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptEdit:(NSString *)key {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:key
        message:@"Extra megabytes for this process."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) {
        t.text = [NSString stringWithFormat:@"%lld", [_jetsam[key] longLongValue]];
        t.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [self->_jetsam removeObjectForKey:key];
            [self saveJetsam];
        }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            NSString *num = a.textFields[0].text ?: @"";
            if (num.length == 0) return;
            self->_jetsam[key] = @([num longLongValue]);
            [self saveJetsam];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

@interface EKAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation EKAppDelegate
- (BOOL)application:(UIApplication *)app
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    EKPanelController *c = [[EKPanelController alloc] init];
    self.window.rootViewController =
        [[UINavigationController alloc] initWithRootViewController:c];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([EKAppDelegate class]));
    }
}
