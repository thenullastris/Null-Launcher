#import "authenticator/BaseAuthenticator.h"
#import "AccountListViewController.h"
#import "AFNetworking.h"
#import "ALTServerConnection.h"
#import "LauncherNavigationController.h"
#import "LauncherMenuViewController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherProfilesViewController.h"
#import "PLProfiles.h"
#import "UIButton+AFNetworking.h"
#import "UIImageView+AFNetworking.h"
#import "UIKit+hook.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

#include <dlfcn.h>

@implementation LauncherMenuCustomItem

+ (LauncherMenuCustomItem *)title:(NSString *)title imageName:(NSString *)imageName action:(id)action {
    LauncherMenuCustomItem *item = [[LauncherMenuCustomItem alloc] init];
    item.title = title;
    item.imageName = imageName;
    item.action = action;
    return item;
}

+ (LauncherMenuCustomItem *)vcClass:(Class)class {
    id vc = [class new];
    LauncherMenuCustomItem *item = [[LauncherMenuCustomItem alloc] init];
    item.title = [vc title];
    item.imageName = [vc imageName];
    item.vcArray = @[vc];
    return item;
}

@end

@interface LauncherMenuViewController()
@property(nonatomic) NSMutableArray<LauncherMenuCustomItem*> *options;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) int lastSelectedIndex;

// JIT status UI
@property(nonatomic) UIView *jitStatusView;
@property(nonatomic) UIView *waveformContainer;
@property(nonatomic) UIView *successDot;
@property(nonatomic) UIView *failDot;
@property(nonatomic) UILabel *jitStatusLabel;
@property(nonatomic) NSArray<UIView *> *waveformBars;
@property(nonatomic) BOOL waveformAnimating;
@property(nonatomic) CADisplayLink *displayLink;
@end

@implementation LauncherMenuViewController

#define contentNavigationController ((LauncherNavigationController *)self.splitViewController.viewControllers[1])

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.isInitialVc = YES;
    
    UIImageView *titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"AppLogo"]];
    [titleView setContentMode:UIViewContentModeScaleAspectFit];
    self.navigationItem.titleView = titleView;
    [titleView sizeToFit];
    
    self.options = @[
        [LauncherMenuCustomItem vcClass:LauncherProfilesViewController.class],
        [LauncherMenuCustomItem vcClass:LauncherPreferencesViewController.class],
    ].mutableCopy;
    if (realUIIdiom != UIUserInterfaceIdiomTV) {
        [self.options addObject:(id)[LauncherMenuCustomItem
                                     title:localize(@"launcher.menu.custom_controls", nil)
                                     imageName:@"MenuCustomControls" action:^{
            [contentNavigationController performSelector:@selector(enterCustomControls)];
        }]];
    }
    [self.options addObject:
     (id)[LauncherMenuCustomItem
          title:localize(@"launcher.menu.execute_jar", nil)
          imageName:@"MenuInstallJar" action:^{
        [contentNavigationController performSelector:@selector(enterModInstaller)];
    }]];
    
    [self.options addObject:
     (id)[LauncherMenuCustomItem
          title:localize(@"login.menu.sendlogs", nil)
          imageName:@"square.and.arrow.up" action:^{
        NSString *latestlogPath = [NSString stringWithFormat:@"file://%s/latestlog.old.txt", getenv("POJAV_HOME")];
        NSLog(@"Path is %@", latestlogPath);
        UIActivityViewController *activityVC;
        if (realUIIdiom != UIUserInterfaceIdiomTV) {
            activityVC = [[UIActivityViewController alloc]
                          initWithActivityItems:@[[NSURL URLWithString:latestlogPath]]
                          applicationActivities:nil];
        } else {
            dlopen("/System/Library/PrivateFrameworks/SharingUI.framework/SharingUI", RTLD_GLOBAL);
            activityVC =
            [[NSClassFromString(@"SFAirDropSharingViewControllerTV") alloc]
             performSelector:@selector(initWithSharingItems:)
             withObject:@[[NSURL URLWithString:latestlogPath]]];
        }
        activityVC.popoverPresentationController.sourceView = titleView;
        activityVC.popoverPresentationController.sourceRect = titleView.bounds;
        [self presentViewController:activityVC animated:YES completion:nil];
    }]];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"MM-dd";
    NSString* date = [dateFormatter stringFromDate:NSDate.date];
    if([date isEqualToString:@"06-29"] || [date isEqualToString:@"06-30"] || [date isEqualToString:@"07-01"]) {
        [self.options addObject:(id)[LauncherMenuCustomItem
                                     title:@"Technoblade never dies!"
                                     imageName:@"" action:^{
            openLink(self, [NSURL URLWithString:@"https://youtu.be/DPMluEVUqS0"]);
        }]];
    }
    
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    self.accountBtnItem = [self drawAccountButton];
    
    [self updateAccountInfo];
    
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
    self.lastSelectedIndex = 0;
    
    if (getEntitlementValue(@"get-task-allow")) {
        [self displayProgress:localize(@"login.jit.checking", nil)];
        if (isJITEnabled(false)) {
            [self displayProgress:localize(@"login.jit.enabled", nil)];
        } else if (@available(iOS 17.0, *)) {
            // JIT for 17.0+ is enabled when the game actually launches
        } else {
            [self enableJITWithAltKit];
        }
    } else if (!NSProcessInfo.processInfo.macCatalystApp && !getenv("SIMULATOR_DEVICE_NAME")) {
        [self displayProgress:localize(@"login.jit.fail", nil)];
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:localize(@"login.jit.fail.title", nil)
            message:localize(@"login.jit.fail.description_unsupported", nil)
            preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction* okAction = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(id action){
            exit(-1);
        }];
        [alert addAction:okAction];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self restoreHighlightedSelection];
}

#pragma mark - JIT Status UI

- (void)setupJITStatusView {
    // Container pinned to bottom of sidebar, above safe area
    self.jitStatusView = [[UIView alloc] init];
    self.jitStatusView.translatesAutoresizingMaskIntoConstraints = NO;
    self.jitStatusView.alpha = 0;
    [self.view addSubview:self.jitStatusView];

    [NSLayoutConstraint activateConstraints:@[
        [self.jitStatusView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.jitStatusView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.jitStatusView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.jitStatusView.heightAnchor constraintEqualToConstant:48],
    ]];

    // Top separator
    UIView *separator = [[UIView alloc] init];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    separator.backgroundColor = [UIColor separatorColor];
    [self.jitStatusView addSubview:separator];
    [NSLayoutConstraint activateConstraints:@[
        [separator.topAnchor constraintEqualToAnchor:self.jitStatusView.topAnchor],
        [separator.leadingAnchor constraintEqualToAnchor:self.jitStatusView.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.jitStatusView.trailingAnchor],
        [separator.heightAnchor constraintEqualToConstant:0.5],
    ]];

    // Waveform container
    self.waveformContainer = [[UIView alloc] init];
    self.waveformContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.waveformContainer.clipsToBounds = NO;
    [self.jitStatusView addSubview:self.waveformContainer];

    int barCount = 5;
    CGFloat barWidth = 3.0;
    CGFloat spacing = 3.0;
    CGFloat totalWidth = barCount * barWidth + (barCount - 1) * spacing;

    NSMutableArray *bars = [NSMutableArray array];
    for (int i = 0; i < barCount; i++) {
        UIView *bar = [[UIView alloc] init];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.backgroundColor = [UIColor colorWithRed:220/255.0 green:38/255.0 blue:38/255.0 alpha:1.0];
        bar.layer.cornerRadius = barWidth / 2.0;
        [self.waveformContainer addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[
            [bar.widthAnchor constraintEqualToConstant:barWidth],
            [bar.heightAnchor constraintEqualToConstant:4],
            [bar.centerYAnchor constraintEqualToAnchor:self.waveformContainer.centerYAnchor],
            [bar.leadingAnchor constraintEqualToAnchor:self.waveformContainer.leadingAnchor
                                              constant:i * (barWidth + spacing)],
        ]];
        [bars addObject:bar];
    }
    self.waveformBars = bars;

    // Success dot (green)
    self.successDot = [[UIView alloc] init];
    self.successDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.successDot.backgroundColor = [UIColor systemGreenColor];
    self.successDot.layer.cornerRadius = 4;
    self.successDot.hidden = YES;
    [self.jitStatusView addSubview:self.successDot];

    // Fail dot (red)
    self.failDot = [[UIView alloc] init];
    self.failDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.failDot.backgroundColor = [UIColor colorWithRed:220/255.0 green:38/255.0 blue:38/255.0 alpha:1.0];
    self.failDot.layer.cornerRadius = 4;
    self.failDot.hidden = YES;
    [self.jitStatusView addSubview:self.failDot];

    // Status label
    self.jitStatusLabel = [[UILabel alloc] init];
    self.jitStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.jitStatusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.jitStatusLabel.textColor = [UIColor secondaryLabelColor];
    [self.jitStatusView addSubview:self.jitStatusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.waveformContainer.centerYAnchor constraintEqualToAnchor:self.jitStatusView.centerYAnchor],
        [self.waveformContainer.leadingAnchor constraintEqualToAnchor:self.jitStatusView.leadingAnchor constant:16],
        [self.waveformContainer.widthAnchor constraintEqualToConstant:totalWidth],
        [self.waveformContainer.heightAnchor constraintEqualToConstant:20],

        [self.successDot.centerYAnchor constraintEqualToAnchor:self.jitStatusView.centerYAnchor],
        [self.successDot.leadingAnchor constraintEqualToAnchor:self.jitStatusView.leadingAnchor constant:16],
        [self.successDot.widthAnchor constraintEqualToConstant:8],
        [self.successDot.heightAnchor constraintEqualToConstant:8],

        [self.failDot.centerYAnchor constraintEqualToAnchor:self.jitStatusView.centerYAnchor],
        [self.failDot.leadingAnchor constraintEqualToAnchor:self.jitStatusView.leadingAnchor constant:16],
        [self.failDot.widthAnchor constraintEqualToConstant:8],
        [self.failDot.heightAnchor constraintEqualToConstant:8],

        [self.jitStatusLabel.centerYAnchor constraintEqualToAnchor:self.jitStatusView.centerYAnchor],
        [self.jitStatusLabel.leadingAnchor constraintEqualToAnchor:self.jitStatusView.leadingAnchor constant:34],
        [self.jitStatusLabel.trailingAnchor constraintEqualToAnchor:self.jitStatusView.trailingAnchor constant:-16],
    ]];
}

- (void)startWaveformAnimation {
    self.waveformAnimating = YES;
    [self.displayLink invalidate];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tickWaveform:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)tickWaveform:(CADisplayLink *)link {
    if (!self.waveformAnimating) return;
    CFTimeInterval t = link.timestamp * 3.5;
    static const CGFloat phases[5] = {0.0, 0.5, 1.0, 1.5, 2.0};
    CGFloat minH = 3.0, maxH = 18.0;
    [self.waveformBars enumerateObjectsUsingBlock:^(UIView *bar, NSUInteger i, BOOL *stop) {
        CGFloat h = minH + (maxH - minH) * (0.5 + 0.5 * sin(t + phases[i]));
        CGRect f = bar.frame;
        f.size.height = h;
        f.origin.y = (20.0 - h) / 2.0;
        bar.frame = f;
    }];
}

- (void)stopWaveformAnimation {
    self.waveformAnimating = NO;
    [self.displayLink invalidate];
    self.displayLink = nil;
    // Collapse bars smoothly
    [UIView animateWithDuration:0.25 animations:^{
        [self.waveformBars enumerateObjectsUsingBlock:^(UIView *bar, NSUInteger i, BOOL *stop) {
            CGRect f = bar.frame;
            f.size.height = 3.0;
            f.origin.y = 8.5;
            bar.frame = f;
        }];
    }];
}

- (void)displayProgress:(NSString *)status {
    if (!self.jitStatusView) {
        [self setupJITStatusView];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (status == nil) return;

        self.jitStatusLabel.text = status;
        [UIView animateWithDuration:0.3 animations:^{
            self.jitStatusView.alpha = 1;
        }];

        NSString *checking = localize(@"login.jit.checking", nil);
        NSString *enabled  = localize(@"login.jit.enabled", nil);

        if ([status isEqualToString:checking]) {
            // Pulse waveform indefinitely
            self.successDot.hidden = YES;
            self.failDot.hidden = YES;
            self.waveformContainer.hidden = NO;
            self.jitStatusLabel.textColor = [UIColor secondaryLabelColor];
            if (!self.waveformAnimating) [self startWaveformAnimation];
        } else if ([status isEqualToString:enabled]) {
            // Green dot
            [self stopWaveformAnimation];
            self.waveformContainer.hidden = YES;
            self.failDot.hidden = YES;
            self.successDot.hidden = NO;
            self.jitStatusLabel.textColor = [UIColor systemGreenColor];
        } else {
            // JIT unavailable / fail
            [self stopWaveformAnimation];
            self.waveformContainer.hidden = YES;
            self.successDot.hidden = YES;
            self.failDot.hidden = NO;
            self.jitStatusLabel.textColor = [UIColor colorWithRed:220/255.0 green:38/255.0 blue:38/255.0 alpha:1.0];
        }
    });
}

#pragma mark - Account Button

- (UIBarButtonItem *)drawAccountButton {
    if (!self.accountBtnItem) {
        self.accountButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.accountButton addTarget:self action:@selector(selectAccount:) forControlEvents:UIControlEventPrimaryActionTriggered];
        self.accountButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.accountButton.titleEdgeInsets = UIEdgeInsetsMake(0, 4, 0, -4);
        self.accountButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.accountButton.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.accountBtnItem = [[UIBarButtonItem alloc] initWithCustomView:self.accountButton];
    }
    [self updateAccountInfo];
    return self.accountBtnItem;
}

- (void)restoreHighlightedSelection {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.lastSelectedIndex inSection:0];
    [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
}

#pragma mark - Table View

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    }

    cell.textLabel.text = [self.options[indexPath.row] title];
    
    UIImage *origImage = [UIImage systemImageNamed:[self.options[indexPath.row]
        performSelector:@selector(imageName)]];
    if (origImage) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext*_Nonnull myContext) {
            CGFloat scaleFactor = 40/origImage.size.height;
            [origImage drawInRect:CGRectMake(20 - origImage.size.width*scaleFactor/2, 0, origImage.size.width*scaleFactor, 40)];
        }];
        cell.imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    
    if (cell.imageView.image == nil) {
        cell.imageView.layer.magnificationFilter = kCAFilterNearest;
        cell.imageView.layer.minificationFilter = kCAFilterNearest;
        cell.imageView.image = [UIImage imageNamed:[self.options[indexPath.row]
            performSelector:@selector(imageName)]];
        cell.imageView.image = [cell.imageView.image _imageWithSize:CGSizeMake(40, 40)];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    LauncherMenuCustomItem *selected = self.options[indexPath.row];
    
    if (selected.action != nil) {
        [self restoreHighlightedSelection];
        ((LauncherMenuCustomItem *)selected).action();
    } else {
        if(self.isInitialVc) {
            self.isInitialVc = NO;
        } else {
            self.options[self.lastSelectedIndex].vcArray = contentNavigationController.viewControllers;
            [contentNavigationController setViewControllers:selected.vcArray animated:NO];
            self.lastSelectedIndex = indexPath.row;
        }
        selected.vcArray[0].navigationItem.rightBarButtonItem = self.accountBtnItem;
        selected.vcArray[0].navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
        selected.vcArray[0].navigationItem.leftItemsSupplementBackButton = true;
    }
}

#pragma mark - Account Selection

- (void)selectAccount:(UIButton *)sender {
    AccountListViewController *vc = [[AccountListViewController alloc] init];
    vc.whenDelete = ^void(NSString* name) {
        if ([name isEqualToString:getPrefObject(@"internal.selected_account")]) {
            BaseAuthenticator.current = nil;
            setPrefObject(@"internal.selected_account", @"");
            [self updateAccountInfo];
        }
    };
    vc.whenItemSelected = ^void() {
        setPrefObject(@"internal.selected_account", BaseAuthenticator.current.authData[@"username"]);
        [self updateAccountInfo];
        if (sender != self.accountButton) {
            [sender sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        }
    };
    vc.modalPresentationStyle = UIModalPresentationPopover;
    vc.preferredContentSize = CGSizeMake(350, 250);

    UIPopoverPresentationController *popoverController = vc.popoverPresentationController;
    popoverController.sourceView = sender;
    popoverController.sourceRect = sender.bounds;
    popoverController.permittedArrowDirections = UIPopoverArrowDirectionAny;
    popoverController.delegate = vc;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)updateAccountInfo {
    NSDictionary *selected = BaseAuthenticator.current.authData;
    CGSize size = CGSizeMake(contentNavigationController.view.frame.size.width, contentNavigationController.view.frame.size.height);
    
    if (selected == nil) {
        if((size.width / 3) > 200) {
            [self.accountButton setAttributedTitle:[[NSAttributedString alloc] initWithString:localize(@"login.option.select", nil)] forState:UIControlStateNormal];
        } else {
            [self.accountButton setAttributedTitle:(NSAttributedString *)@"" forState:UIControlStateNormal];
        }
        [self.accountButton setImage:[UIImage imageNamed:@"DefaultAccount"] forState:UIControlStateNormal];
        [self.accountButton sizeToFit];
        return;
    }

    BOOL isDemo = [selected[@"username"] hasPrefix:@"Demo."];
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:[selected[@"username"] substringFromIndex:(isDemo?5:0)]];

    BOOL shouldUpdateProfiles = (getenv("DEMO_LOCK")!=NULL) != isDemo;

    unsetenv("DEMO_LOCK");
    setenv("POJAV_GAME_DIR", [NSString stringWithFormat:@"%s/Library/Application Support/minecraft", getenv("POJAV_HOME")].UTF8String, 1);

    id subtitle;
    if (isDemo) {
        subtitle = localize(@"login.option.demo", nil);
        setenv("DEMO_LOCK", "1", 1);
        setenv("POJAV_GAME_DIR", [NSString stringWithFormat:@"%s/.demo", getenv("POJAV_HOME")].UTF8String, 1);
    } else if (selected[@"xboxGamertag"] == nil) {
        subtitle = localize(@"login.option.local", nil);
    } else {
        subtitle = selected[@"xboxGamertag"];
    }

    subtitle = [[NSAttributedString alloc] initWithString:subtitle attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12]}];
    [title appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:nil]];
    [title appendAttributedString:subtitle];
    
    if((size.width / 3) > 200) {
        [self.accountButton setAttributedTitle:title forState:UIControlStateNormal];
    } else {
        [self.accountButton setAttributedTitle:(NSAttributedString *)@"" forState:UIControlStateNormal];
    }
    
    NSURL *url = [NSURL URLWithString:[selected[@"profilePicURL"] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]];
    UIImage *placeholder = [UIImage imageNamed:@"DefaultAccount"];
    [self.accountButton setImageForState:UIControlStateNormal withURL:url placeholderImage:placeholder];
    [self.accountButton.imageView setImageWithURL:url placeholderImage:placeholder];
    [self.accountButton sizeToFit];

    if (shouldUpdateProfiles) {
        [contentNavigationController fetchLocalVersionList];
        [contentNavigationController performSelector:@selector(reloadProfileList)];
    }

    UITableViewController *tableVC = contentNavigationController.viewControllers.lastObject;
    if ([tableVC isKindOfClass:UITableViewController.class]) {
        [tableVC.tableView reloadData];
    }
}

#pragma mark - AltKit JIT

- (void)enableJITWithAltKit {
    [ALTServerManager.sharedManager startDiscovering];
    [ALTServerManager.sharedManager autoconnectWithCompletionHandler:^(ALTServerConnection *connection, NSError *error) {
        if (error) {
            NSLog(@"[AltKit] Could not auto-connect to server. %@", error.localizedRecoverySuggestion);
            [self displayProgress:localize(@"login.jit.fail", nil)];
            return;
        }
        [connection enableUnsignedCodeExecutionWithCompletionHandler:^(BOOL success, NSError *error) {
            if (success) {
                NSLog(@"[AltKit] Successfully enabled JIT compilation!");
                [ALTServerManager.sharedManager stopDiscovering];
                [self displayProgress:localize(@"login.jit.enabled", nil)];
            } else {
                NSLog(@"[AltKit] Error enabling JIT: %@", error.localizedRecoverySuggestion);
                [self displayProgress:localize(@"login.jit.fail", nil)];
            }
            [connection disconnect];
        }];
    }];
}

@end
