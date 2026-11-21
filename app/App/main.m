// ellekit-panel — the app half.
//
// Runs as mobile and cannot write /basebin, so it hands each instruction to
// ekpaneld (root, from launchd) through one request plist and reads back one
// result plist. Every exchange goes through _lock so a refresh can never
// overwrite a request the user just made.

#import <UIKit/UIKit.h>
#import "EKPanel.h"
#import "ekpanel.h"

static NSString *const kRequestPath = @EKPANEL_REQUEST_PATH;
static NSString *const kResultPath =
    @"/var/mobile/Library/Preferences/wiki.qaq.ellekit-panel.result.plist";

@interface EKPanelController : UIViewController
@end

@implementation EKPanelController {
    UILabel *_stateLabel;
    UILabel *_detailLabel;
    UISwitch *_toggle;
    UIButton *_respringButton;
    UIActivityIndicatorView *_spinner;
    NSLock *_lock;
    BOOL _busy;
}

- (instancetype)init {
    if ((self = [super init])) _lock = [[NSLock alloc] init];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ElleKit Panel";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    [self.view addSubview:card];

    UILabel *caption = [[UILabel alloc] init];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.text = @"Tweak injection";
    caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [card addSubview:caption];

    _toggle = [[UISwitch alloc] init];
    _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    _toggle.onTintColor = [UIColor systemGreenColor];
    [_toggle addTarget:self action:@selector(toggleChanged:)
      forControlEvents:UIControlEventValueChanged];
    [card addSubview:_toggle];

    _stateLabel = [[UILabel alloc] init];
    _stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _stateLabel.font = [UIFont boldSystemFontOfSize:22];
    _stateLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:_stateLabel];

    _spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    [card addSubview:_spinner];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _detailLabel.textColor = [UIColor secondaryLabelColor];
    _detailLabel.numberOfLines = 0;
    _detailLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:_detailLabel];

    _respringButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _respringButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_respringButton setTitle:@"Restart SpringBoard" forState:UIControlStateNormal];
    _respringButton.titleLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [_respringButton addTarget:self action:@selector(respringTapped:)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_respringButton];

    UILabel *note = [[UILabel alloc] init];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    note.textColor = [UIColor tertiaryLabelColor];
    note.numberOfLines = 0;
    note.text = @"A change applies to processes started from now on. "
                 "Respring to apply it to SpringBoard and its apps.";
    [self.view addSubview:note];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:g.topAnchor constant:20],
        [card.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],

        [caption.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [caption.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_toggle.centerYAnchor constraintEqualToAnchor:caption.centerYAnchor],
        [_toggle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [_stateLabel.topAnchor constraintEqualToAnchor:_toggle.bottomAnchor constant:18],
        [_stateLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_stateLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],

        [_spinner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_spinner.centerYAnchor constraintEqualToAnchor:_stateLabel.centerYAnchor],

        [_detailLabel.topAnchor constraintEqualToAnchor:_stateLabel.bottomAnchor constant:6],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [_detailLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-18],

        [_respringButton.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:18],
        [_respringButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],

        [note.topAnchor constraintEqualToAnchor:_respringButton.bottomAnchor constant:10],
        [note.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:16],
        [note.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [note.bottomAnchor constraintLessThanOrEqualToAnchor:g.bottomAnchor constant:-16],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(refreshFromForeground)
        name:UIApplicationWillEnterForegroundNotification object:nil];
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    _toggle.enabled = !busy;
    _respringButton.enabled = !busy;
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}

// One exchange with the helper. Serialised: the request and result files are
// shared, so two overlapping calls would clobber each other.
- (NSDictionary *)sendAction:(NSString *)action {
    NSString *req = EKPanelBootstrapPath(kRequestPath);
    NSString *res = EKPanelBootstrapPath(kResultPath);
    if (req == nil || res == nil) return nil;

    [_lock lock];
    NSDictionary *answer = nil;
    [[NSFileManager defaultManager] removeItemAtPath:res error:NULL];
    NSDictionary *request = @{@"action": action};
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

- (void)renderResult:(NSDictionary *)r {
    if (r == nil) {
        _stateLabel.text = @"No answer";
        _stateLabel.textColor = [UIColor systemOrangeColor];
        _detailLabel.text = @"The helper did not respond. Is ellekit-panel "
                            "installed with its launch daemon?";
        return;
    }
    NSString *state = r[@EKPANEL_RESULT_STATE];
    BOOL injected = ![state isEqualToString:@"enabled"];
    _toggle.on = injected;
    _stateLabel.text = injected ? @"Injection ON" : @"Injection OFF";
    _stateLabel.textColor = injected ? [UIColor systemGreenColor]
                                     : [UIColor systemRedColor];
    NSString *msg = r[@EKPANEL_RESULT_MESSAGE];
    _detailLabel.text = msg.length ? msg : @"";
}

- (void)refresh {
    if (_busy) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *r = [self sendAction:@"status"];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self->_busy) [self renderResult:r];
        });
    });
}

- (void)refreshFromForeground {
    [self refresh];
}

- (void)toggleChanged:(UISwitch *)sw {
    if (_busy) return;
    BOOL wantInject = sw.on;
    [self setBusy:YES];
    NSString *action = wantInject ? @"disable" : @"enable";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *r = [self sendAction:action];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            [self renderResult:r];
        });
    });
}

- (void)respringTapped:(id)sender {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"Restart SpringBoard"
        message:@"SpringBoard will restart. Apps keep running; their tweaks are reloaded when they start again."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restart"
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
            [self sendAction:@"respring"];
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
