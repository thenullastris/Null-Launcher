#import <AuthenticationServices/AuthenticationServices.h>

#import "authenticator/BaseAuthenticator.h"
#import "AccountListViewController.h"
#import "AFNetworking.h"
#import "LauncherPreferences.h"
#import "UIImageView+AFNetworking.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface AccountListViewController()<ASWebAuthenticationPresentationContextProviding>

@property(nonatomic, strong) NSMutableArray *accountList;
@property(nonatomic) ASWebAuthenticationSession *authVC;

@end

@implementation AccountListViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Account";

    if (self.accountList == nil) {
        self.accountList = [NSMutableArray array];
    } else {
        [self.accountList removeAllObjects];
    }

    NSString *listPath = [NSString stringWithFormat:@"%s/accounts", getenv("POJAV_HOME")];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:listPath error:nil];
    for(NSString *file in files) {
        NSString *path = [listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if(!isDir && [file hasSuffix:@".json"]) {
            [self.accountList addObject:parseJSONFromFile(path)];
        }
    }

    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleSingleLine];

    if (BaseAuthenticator.current != nil) {
        self.tableView.tableHeaderView = [self buildSkinHeaderView];
    }
}

- (UIView *)buildSkinHeaderView {
    NSDictionary *authData = BaseAuthenticator.current.authData;
    CGFloat totalHeight = 160.0;
    CGFloat leftWidth = 130.0;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, totalHeight)];
    container.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];

    UIView *leftPanel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, leftWidth, totalHeight)];
    leftPanel.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];

    UIView *leftBorder = [[UIView alloc] initWithFrame:CGRectMake(leftWidth - 1, 0, 1, totalHeight)];
    leftBorder.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [leftPanel addSubview:leftBorder];

    UIImageView *skinView = [[UIImageView alloc] init];
    skinView.contentMode = UIViewContentModeScaleAspectFit;
    skinView.layer.magnificationFilter = kCAFilterNearest;
    skinView.layer.minificationFilter = kCAFilterNearest;
    skinView.translatesAutoresizingMaskIntoConstraints = NO;
    [leftPanel addSubview:skinView];

    [NSLayoutConstraint activateConstraints:@[
        [skinView.centerXAnchor constraintEqualToAnchor:leftPanel.centerXAnchor],
        [skinView.bottomAnchor constraintEqualToAnchor:leftPanel.bottomAnchor constant:-8],
        [skinView.widthAnchor constraintEqualToConstant:72],
        [skinView.heightAnchor constraintEqualToConstant:130],
    ]];

    NSString *username = authData[@"username"];
    if ([username hasPrefix:@"Demo."]) {
        username = [username substringFromIndex:5];
    }
    NSString *bodyURL = [NSString stringWithFormat:@"https://mc-heads.net/body/%@/100", username];
    UIImage *placeholder = [UIImage imageNamed:@"DefaultAccount"];
    [skinView setImageWithURL:[NSURL URLWithString:bodyURL] placeholderImage:placeholder];

    [container addSubview:leftPanel];

    UIView *rightPanel = [[UIView alloc] initWithFrame:CGRectMake(leftWidth, 0, self.tableView.bounds.size.width - leftWidth, totalHeight)];
    rightPanel.backgroundColor = [UIColor clearColor];

    NSString *displayName = authData[@"username"];
    if ([displayName hasPrefix:@"Demo."]) {
        displayName = [displayName substringFromIndex:5];
    }
    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = displayName;
    nameLabel.font = [UIFont boldSystemFontOfSize:17];
    nameLabel.textColor = [UIColor whiteColor];
    nameLabel.adjustsFontSizeToFitWidth = YES;
    nameLabel.minimumScaleFactor = 0.7;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPanel addSubview:nameLabel];

    NSString *subtitleText;
    if ([authData[@"username"] hasPrefix:@"Demo."]) {
        subtitleText = localize(@"login.option.demo", nil);
    } else if (authData[@"xboxGamertag"] != nil) {
        subtitleText = authData[@"xboxGamertag"];
    } else {
        subtitleText = localize(@"login.option.local", nil);
    }
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitleText;
    subtitleLabel.font = [UIFont systemFontOfSize:13];
    subtitleLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPanel addSubview:subtitleLabel];

    UILabel *badgeLabel = [[UILabel alloc] init];
    BOOL isMicrosoft = authData[@"xboxGamertag"] != nil;
    badgeLabel.text = isMicrosoft ? @"● Microsoft" : @"● Local account";
    badgeLabel.font = [UIFont systemFontOfSize:11];
    badgeLabel.textColor = isMicrosoft
        ? [UIColor colorWithRed:0.37 green:0.64 blue:0.98 alpha:1.0]
        : [UIColor colorWithWhite:0.4 alpha:1.0];
    badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [rightPanel addSubview:badgeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [nameLabel.leadingAnchor constraintEqualToAnchor:rightPanel.leadingAnchor constant:16],
        [nameLabel.trailingAnchor constraintEqualToAnchor:rightPanel.trailingAnchor constant:-16],
        [nameLabel.centerYAnchor constraintEqualToAnchor:rightPanel.centerYAnchor constant:-22],

        [subtitleLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:5],

        [badgeLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [badgeLabel.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:8],
    ]];

    [container addSubview:rightPanel];

    UIView *bottomLine = [[UIView alloc] initWithFrame:CGRectMake(0, totalHeight - 1, self.tableView.bounds.size.width, 1)];
    bottomLine.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    [container addSubview:bottomLine];

    return container;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.accountList.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    }

    if (indexPath.row == self.accountList.count) {
    cell.imageView.image = [UIImage imageNamed:@"IconAdd"];
    cell.textLabel.text = localize(@"login.option.add", nil);
    cell.detailTextLabel.text = @"";
    return cell;
    }

    NSDictionary *selected = self.accountList[indexPath.row];
    cell.textLabel.text = selected[@"username"];
    if ([selected[@"username"] hasPrefix:@"Demo."]) {
        cell.textLabel.text = [selected[@"username"] substringFromIndex:5];
        cell.detailTextLabel.text = localize(@"login.option.demo", nil);
    } else if (selected[@"xboxGamertag"] == nil) {
        cell.detailTextLabel.text = localize(@"login.option.local", nil);
    } else {
        cell.detailTextLabel.text = selected[@"xboxGamertag"];
    }

    cell.imageView.contentMode = UIViewContentModeCenter;
    [cell.imageView setImageWithURL:[NSURL URLWithString:[selected[@"profilePicURL"] stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"]] placeholderImage:[UIImage imageNamed:@"DefaultAccount"]];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];

    if (indexPath.row == self.accountList.count) {
        [self actionAddAccount:cell];
        return;
    }

    self.modalInPresentation = YES;
    self.tableView.userInteractionEnabled = NO;
    [self addActivityIndicatorTo:cell];

    id callback = ^(id status, BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^(){
            [self callbackMicrosoftAuth:status success:success forCell:cell];
        });
    };
    [[BaseAuthenticator loadSavedName:self.accountList[indexPath.row][@"username"]] refreshTokenWithCallback:callback];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *str = self.accountList[indexPath.row][@"username"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [NSString stringWithFormat:@"%s/accounts/%@.json", getenv("POJAV_HOME"), str];
        if (self.whenDelete != nil) {
            self.whenDelete(str);
        }
        NSString *xuid = self.accountList[indexPath.row][@"xuid"];
        if (xuid) {
            [MicrosoftAuthenticator clearTokenDataOfProfile:xuid];
        }
        [fm removeItemAtPath:path error:nil];
        [self.accountList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];

        if (BaseAuthenticator.current != nil) {
            self.tableView.tableHeaderView = [self buildSkinHeaderView];
        }
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == self.accountList.count) {
        return UITableViewCellEditingStyleNone;
    } else {
        return UITableViewCellEditingStyleDelete;
    }
}

- (NSDictionary *)parseQueryItems:(NSString *)url {
    NSMutableDictionary *result = [NSMutableDictionary new];
    NSArray<NSURLQueryItem *> *queryItems = [NSURLComponents componentsWithString:url].queryItems;
    for (NSURLQueryItem *item in queryItems) {
        result[item.name] = item.value;
    }
    return result;
}

- (void)actionAddAccount:(UITableViewCell *)sender {
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *actionMicrosoft = [UIAlertAction actionWithTitle:localize(@"login.option.microsoft", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self actionLoginMicrosoft:sender];
    }];
    [picker addAction:actionMicrosoft];
    UIAlertAction *actionLocal = [UIAlertAction actionWithTitle:localize(@"login.option.local", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self actionLoginLocal:sender];
    }];
    [picker addAction:actionLocal];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [picker addAction:cancel];
    picker.popoverPresentationController.sourceView = sender;
    picker.popoverPresentationController.sourceRect = sender.bounds;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)actionLoginLocal:(UIView *)sender {
    if (getPrefBool(@"warnings.local_warn")) {
        setPrefBool(@"warnings.local_warn", NO);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"login.warn.title.localmode", nil) message:localize(@"login.warn.message.localmode", nil) preferredStyle:UIAlertControllerStyleActionSheet];
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
        UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self actionLoginLocal:sender];
        }];
        [alert addAction:ok];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *controller = [UIAlertController alertControllerWithTitle:localize(@"Sign in", nil) message:localize(@"login.option.local", nil) preferredStyle:UIAlertControllerStyleAlert];
    [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = localize(@"login.alert.field.username", nil);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.borderStyle = UITextBorderStyleRoundedRect;
    }];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray *textFields = controller.textFields;
        UITextField *usernameField = textFields[0];
        if (usernameField.text.length < 3 || usernameField.text.length > 16) {
            controller.message = localize(@"login.error.username.outOfRange", nil);
            [self presentViewController:controller animated:YES completion:nil];
        } else {
            id callback = ^(id status, BOOL success) {
                if (self.whenItemSelected) self.whenItemSelected();
                [self dismissOrPop];
            };
            [[[LocalAuthenticator alloc] initWithInput:usernameField.text] loginWithCallback:callback];
        }
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)actionLoginMicrosoft:(UITableViewCell *)sender {
    NSURL *url = [NSURL URLWithString:@"https://login.live.com/oauth20_authorize.srf?client_id=00000000402b5328&response_type=code&scope=service%3A%3Auser.auth.xboxlive.com%3A%3AMBI_SSL&redirect_url=https%3A%2F%2Flogin.live.com%2Foauth20_desktop.srf"];
    self.authVC = [[ASWebAuthenticationSession alloc] initWithURL:url
        callbackURLScheme:@"ms-xal-00000000402b5328"
        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        if (callbackURL == nil) {
            if (error.code != ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
            }
            return;
        }
        NSDictionary *queryItems = [self parseQueryItems:callbackURL.absoluteString];
        if (queryItems[@"code"]) {
            dispatch_async(dispatch_get_main_queue(), ^(){
                self.modalInPresentation = YES;
                self.tableView.userInteractionEnabled = NO;
                [self addActivityIndicatorTo:sender];
            });
            id callback = ^(id status, BOOL success) {
                if ([status isKindOfClass:NSString.class] && [status isEqualToString:@"DEMO"] && success) {
                    showDialog(localize(@"login.warn.title.demomode", nil), localize(@"login.warn.message.demomode", nil));
                }
                dispatch_async(dispatch_get_main_queue(), ^(){
                    [self callbackMicrosoftAuth:status success:success forCell:sender];
                });
            };
            [[[MicrosoftAuthenticator alloc] initWithInput:queryItems[@"code"]] loginWithCallback:callback];
        } else {
            if ([queryItems[@"error"] hasPrefix:@"access_denied"]) {
                return;
            }
            showDialog(localize(@"Error", nil), queryItems[@"error_description"]);
        }
    }];
    self.authVC.prefersEphemeralWebBrowserSession = YES;
    self.authVC.presentationContextProvider = self;
    if ([self.authVC start] == NO) {
        showDialog(localize(@"Error", nil), @"Unable to open Safari");
    }
}

- (void)addActivityIndicatorTo:(UITableViewCell *)cell {
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    cell.accessoryView = indicator;
    [indicator sizeToFit];
    [indicator startAnimating];
}

- (void)removeActivityIndicatorFrom:(UITableViewCell *)cell {
    UIActivityIndicatorView *indicator = (id)cell.accessoryView;
    [indicator stopAnimating];
    cell.accessoryView = nil;
}

- (void)callbackMicrosoftAuth:(id)status success:(BOOL)success forCell:(UITableViewCell *)cell {
    if (status != nil) {
        if (success) {
            cell.detailTextLabel.text = status;
        } else {
            self.modalInPresentation = NO;
            self.tableView.userInteractionEnabled = YES;
            [self removeActivityIndicatorFrom:cell];
            cell.detailTextLabel.text = [status localizedDescription];
            NSData *errorData = ((NSError *)status).userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
            NSString *errorStr = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
            NSLog(@"[MSA] Error: %@", errorStr);
            showDialog(localize(@"Error", nil), errorStr);
        }
    } else if (success) {
        if (self.whenItemSelected) self.whenItemSelected();
        [self removeActivityIndicatorFrom:cell];
        self.tableView.tableHeaderView = [self buildSkinHeaderView];
        [self dismissOrPop];
    }
}

- (void)dismissOrPop {
    if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - UIPopoverPresentationControllerDelegate
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller traitCollection:(UITraitCollection *)traitCollection {
    return UIModalPresentationNone;
}

#pragma mark - ASWebAuthenticationPresentationContextProviding
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
