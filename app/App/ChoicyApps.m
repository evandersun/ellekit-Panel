// Per-app tweak control, on top of Choicy's own settings.
//
// Choicy keeps these in /var/mobile/Library/Preferences/com.opa334.choicyprefs.plist
// under appSettings, one entry per app:
//
//   tweakInjectionDisabled          = <bool>
//   customTweakConfigurationEnabled = <bool>
//   allowDenyMode                   = <int>
//   allowedTweaks / deniedTweaks    = [ <tweak name> ... ]
//
// Its injected dylib reads that file directly, so the helper writes it and
// this screen never touches preferences itself (the app's sandbox would not
// let it).

#import "ChoicyApps.h"

static NSString *EKAppName(NSString *bundleID) {
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass == Nil) return nil;
    id workspace = [wsClass performSelector:@selector(defaultWorkspace)];
    if (workspace == nil) return nil;
    NSArray *apps = [workspace performSelector:@selector(allInstalledApplications)];
    for (id proxy in apps) {
        NSString *ident = [proxy performSelector:@selector(applicationIdentifier)];
        if (![ident isEqualToString:bundleID]) continue;
        NSString *name = [proxy performSelector:@selector(localizedName)];
        if (name.length) return name;
    }
    return nil;
}

#pragma mark - app picker

@interface EKAppPickerController : UITableViewController
@property (nonatomic, copy) void (^onPick)(NSString *bundleID);
@property (nonatomic, strong) NSArray *apps;
@end

@implementation EKAppPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Choose an app";

    NSMutableArray *rows = [NSMutableArray array];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (wsClass != Nil) {
        id workspace = [wsClass performSelector:@selector(defaultWorkspace)];
        NSArray *installed = [workspace performSelector:@selector(allInstalledApplications)];
        for (id proxy in installed) {
            NSString *ident = [proxy performSelector:@selector(applicationIdentifier)];
            NSString *name = [proxy performSelector:@selector(localizedName)];
            if (ident.length == 0 || name.length == 0) continue;
            [rows addObject:@{@"id": ident, @"name": name}];
        }
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    self.apps = rows;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *row = self.apps[ip.row];
    cell.textLabel.text = row[@"name"];
    cell.detailTextLabel.text = row[@"id"];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11
                                                          weight:UIFontWeightRegular];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *row = self.apps[ip.row];
    if (self.onPick) self.onPick(row[@"id"]);
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - the list

@implementation EKChoicyController {
    NSMutableDictionary *_settings;
    NSArray *_keys;
    void (^_onSave)(NSDictionary *);
}

- (instancetype)initWithSettings:(NSDictionary *)settings
                          onSave:(void (^)(NSDictionary *))onSave {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _settings = [settings mutableCopy] ?: [NSMutableDictionary dictionary];
        _onSave = [onSave copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Per-app injection";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(addApp)];
    [self sortKeys];
}

- (void)sortKeys {
    _keys = [_settings.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSString *na = EKAppName(a) ?: a;
        NSString *nb = EKAppName(b) ?: b;
        return [na localizedCaseInsensitiveCompare:nb];
    }];
}

- (void)save {
    [self sortKeys];
    [self.tableView reloadData];
    if (_onSave) _onSave([_settings copy]);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"Turn an app off to stop Choicy injecting tweaks into it. The change "
            "applies the next time that app starts.";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return _keys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
        initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSString *bundleID = _keys[ip.row];
    NSDictionary *entry = _settings[bundleID];
    BOOL off = [entry[@"tweakInjectionDisabled"] boolValue];
    BOOL custom = [entry[@"customTweakConfigurationEnabled"] boolValue];

    cell.textLabel.text = EKAppName(bundleID) ?: bundleID;
    cell.detailTextLabel.text = off ? @"Tweaks off"
                              : (custom ? @"Some tweaks off" : @"Tweaks on");
    cell.detailTextLabel.textColor = off ? [UIColor systemRedColor]
                                         : [UIColor secondaryLabelColor];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = !off;
    sw.onTintColor = [UIColor systemGreenColor];
    sw.tag = ip.row;
    [sw addTarget:self action:@selector(toggle:)
        forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)toggle:(UISwitch *)sw {
    if (sw.tag < 0 || sw.tag >= (NSInteger)_keys.count) return;
    NSString *bundleID = _keys[sw.tag];
    NSMutableDictionary *entry = [_settings[bundleID] mutableCopy];
    if (entry == nil) entry = [NSMutableDictionary dictionary];
    if (sw.on) {
        [entry removeObjectForKey:@"tweakInjectionDisabled"];
    } else {
        entry[@"tweakInjectionDisabled"] = @YES;
    }
    _settings[bundleID] = entry;
    [self save];
}

- (void)addApp {
    EKAppPickerController *picker = [[EKAppPickerController alloc] init];
    __weak typeof(self) weakSelf = self;
    picker.onPick = ^(NSString *bundleID) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) return;
        NSMutableDictionary *entry = [self->_settings[bundleID] mutableCopy];
        if (entry == nil) entry = [NSMutableDictionary dictionary];
        entry[@"tweakInjectionDisabled"] = @YES;
        self->_settings[bundleID] = entry;
        [self save];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)tableView:(UITableView *)tv
    commitEditingStyle:(UITableViewCellEditingStyle)style
     forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    [_settings removeObjectForKey:_keys[ip.row]];
    [self save];
}

@end
