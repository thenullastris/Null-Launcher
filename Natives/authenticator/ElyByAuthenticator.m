#import "ElyByAuthenticator.h"
#import "../external/AFNetworking/AFNetworking/AFNetworking.h"
#import "../ios_uikit_bridge.h" 

@implementation ElyByAuthenticator

- (void)loginWithCallback:(Callback)callback {
    NSString *email = self.authData[@"input_email"];
    NSString *password = self.authData[@"input_password"];
    
    // Generate a clientToken (random UUID)
    NSString *clientToken = [[NSUUID UUID] UUIDString];
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.requestSerializer = [AFJSONRequestSerializer serializer];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    
    NSDictionary *params = @{
        @"username": email,
        @"password": password,
        @"clientToken": clientToken,
        @"requestUser": @YES
    };
    
    [manager POST:@"https://authserver.ely.by/auth/authenticate"
       parameters:params
          headers:nil
          progress:nil
          success:^(NSURLSessionDataTask *task, id responseObject) {
        
        NSDictionary *profile = responseObject[@"selectedProfile"];
        NSDictionary *user = responseObject[@"user"];
        
        self.authData[@"type"] = @"ely.by";
        self.authData[@"username"] = profile[@"name"];
        self.authData[@"oldusername"] = profile[@"name"];
        self.authData[@"profileId"] = profile[@"id"];
        self.authData[@"accessToken"] = responseObject[@"accessToken"];
        self.authData[@"clientToken"] = clientToken;
        self.authData[@"expiresAt"] = @(0); // keep 0 so BaseAuthenticator doesn't mistake it for Microsoft
        
        // Ely.by skin URL
        NSString *uuid = profile[@"id"];
        self.authData[@"profilePicURL"] = [NSString stringWithFormat:
            @"https://crafatar.com/avatars/%@?size=64&overlay", uuid];
        
        [self.authData removeObjectForKey:@"input_email"];
        [self.authData removeObjectForKey:@"input_password"];
        
        callback(nil, [self saveChanges]);
        
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        // Try to get the error message from ely.by response
        NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        if (data) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *msg = json[@"errorMessage"] ?: error.localizedDescription;
            
            // Check for 2FA error
            if ([msg isEqualToString:@"Account protected with two factor auth."]) {
                callback(@"2FA_REQUIRED", NO);
            } else {
                callback(msg, NO);
            }
        } else {
            callback(error.localizedDescription, NO);
        }
    }];
}

- (void)refreshTokenWithCallback:(Callback)callback {
    // Ely.by tokens don't expire the same way, just validate
    // For now treat as always valid like LocalAuthenticator
    callback(nil, YES);
}

@end
