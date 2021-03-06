/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2012-2014 HockeyApp, Bit Stadium GmbH.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPREDS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "PreDemObjc.h"
#import "PREDPrivate.h"
#import "PREDBaseManagerPrivate.h"
#import "PREDHelper.h"
#import "PREDNetworkClient.h"
#import "PREDKeychainUtils.h"
#import "PREDVersion.h"
#import "PREDConfigManager.h"
#import "PREDNetDiag.h"
#import "PREDCrashManagerPrivate.h"
#import "PREDMetricsManagerPrivate.h"
#import "PREDURLProtocol.h"

@interface PREDManager ()
<
PREDConfigManagerDelegate
>

@end


@implementation PREDManager {
    NSString *_appIdentifier;
    NSString *_liveIdentifier;
    
    BOOL _validAppIdentifier;
    
    BOOL _startManagerIsInvoked;
    
    BOOL _managersInitialized;
    
    PREDNetworkClient *_hockeyAppClient;
    
    PREDConfigManager *_configManager;
}


#pragma mark - Public Class Methods

+ (PREDManager *)sharedPREDManager {
    static PREDManager *sharedInstance = nil;
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[PREDManager alloc] init];
    });
    
    return sharedInstance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _serverURL = PRED_URL;
        _delegate = nil;
        _managersInitialized = NO;
        
        _hockeyAppClient = nil;
        
        _disableCrashManager = NO;
        _disableMetricsManager = NO;
        
        _appEnvironment = pres_currentAppEnvironment();
        _startManagerIsInvoked = NO;
        
        _liveIdentifier = nil;
        _installString = pres_appAnonID(NO);
        
        _configManager = [PREDConfigManager sharedInstance];
        _configManager.delegate = self;
        
        [self performSelector:@selector(validateStartManagerIsInvoked) withObject:nil afterDelay:0.0f];
    }
    return self;
}

#pragma mark - Public Instance Methods (Configuration)

- (void)configureWithIdentifier:(NSString *)appIdentifier {
    _appIdentifier = [appIdentifier copy];
    
    [self initializeModules];
    
    [self applyConfig:[_configManager getConfigWithAppKey:appIdentifier]];
}

- (void)configureWithIdentifier:(NSString *)appIdentifier delegate:(id)delegate {
    _delegate = delegate;
    _appIdentifier = [appIdentifier copy];
    
    [self initializeModules];
    
    [self applyConfig:[_configManager getConfigWithAppKey:appIdentifier]];
}

- (void)configureWithBetaIdentifier:(NSString *)betaIdentifier liveIdentifier:(NSString *)liveIdentifier delegate:(id)delegate {
    _delegate = delegate;
    
    // check the live identifier now, because otherwise invalid identifier would only be logged when the app is already in the store
    if (![self checkValidityOfAppIdentifier:liveIdentifier]) {
        [self logInvalidIdentifier:@"liveIdentifier"];
        _liveIdentifier = [liveIdentifier copy];
    }
    
    if ([self shouldUseLiveIdentifier]) {
        _appIdentifier = [liveIdentifier copy];
    }
    else {
        _appIdentifier = [betaIdentifier copy];
    }
    
    [self initializeModules];
    
    [self applyConfig:[_configManager getConfigWithAppKey:_appIdentifier]];
}


- (void)startManager {
    if (!_validAppIdentifier) return;
    if (_startManagerIsInvoked) {
        PREDLogWarning(@"startManager should only be invoked once! This call is ignored.");
        return;
    }
    
    // Fix bug where Application Support directory was encluded from backup
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *appSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    pres_fixBackupAttributeForURL(appSupportURL);
    
    if (![self isSetUpOnMainThread]) return;
    
    PREDLogDebug(@"Starting PREDManager");
    _startManagerIsInvoked = YES;
    
    // start CrashManager
    if (![self isCrashManagerDisabled]) {
        PREDLogDebug(@"Start CrashManager");
        
        [_crashManager startManager];
    }
    
    // App Extensions can only use PREDCrashManager, so ignore all others automatically
    if (pres_isRunningInAppExtension()) {
        return;
    }
    
    // start MetricsManager
    if (!self.isMetricsManagerDisabled) {
        PREDLogDebug(@"Start MetricsManager");
        [_metricsManager startManager];
    }
    
    if (!self.isHttpMonitorDisabled) {
        [PREDURLProtocol enableHTTPDem];
    }
}

- (void)setDisableMetricsManager:(BOOL)disableMetricsManager {
    if (_metricsManager) {
        _metricsManager.disabled = disableMetricsManager;
    }
    _disableMetricsManager = disableMetricsManager;
    
}

- (void)setDisableHttpMonitor:(BOOL)disableHttpMonitor {
    _disableHttpMonitor = disableHttpMonitor;
    if (disableHttpMonitor) {
        [PREDURLProtocol disableHTTPDem];
    } else {
        [PREDURLProtocol enableHTTPDem];
    }
}

- (void)setServerURL:(NSString *)aServerURL {
    // ensure url ends with a trailing slash
    if (![aServerURL hasSuffix:@"/"]) {
        aServerURL = [NSString stringWithFormat:@"%@/", aServerURL];
    }
    
    if (_serverURL != aServerURL) {
        _serverURL = [aServerURL copy];
        
        if (_hockeyAppClient) {
            _hockeyAppClient.baseURL = [NSURL URLWithString:_serverURL ?: PRED_URL];
        }
    }
}


- (void)setDelegate:(id<PREDManagerDelegate>)delegate {
    if (self.appEnvironment != PREDEnvironmentAppStore) {
        if (_startManagerIsInvoked) {
            PREDLogError(@"The `delegate` property has to be set before calling [[PREDManager sharedPREDManager] startManager] !");
        }
    }
    
    if (_delegate != delegate) {
        _delegate = delegate;
        
        if (_crashManager) {
            _crashManager.delegate = _delegate;
        }
    }
}

- (PREDLogLevel)logLevel {
    return PREDLogger.currentLogLevel;
}

- (void)setLogLevel:(PREDLogLevel)logLevel {
    PREDLogger.currentLogLevel = logLevel;
}

- (void)setLogHandler:(PREDLogHandler)logHandler {
    [PREDLogger setLogHandler:logHandler];
}

- (void)modifyKeychainUserValue:(NSString *)value forKey:(NSString *)key {
    NSError *error = nil;
    BOOL success = YES;
    NSString *updateType = @"update";
    
    if (value) {
        success = [PREDKeychainUtils storeUsername:key
                                       andPassword:value
                                    forServiceName:pres_keychainPreDemObjcServiceName()
                                    updateExisting:YES
                                     accessibility:kSecAttrAccessibleAlwaysThisDeviceOnly
                                             error:&error];
    } else {
        updateType = @"delete";
        if ([PREDKeychainUtils getPasswordForUsername:key
                                       andServiceName:pres_keychainPreDemObjcServiceName()
                                                error:&error]) {
            success = [PREDKeychainUtils deleteItemForUsername:key
                                                andServiceName:pres_keychainPreDemObjcServiceName()
                                                         error:&error];
        }
    }
    
    if (!success) {
        NSString *errorDescription = [error description] ?: @"";
        PREDLogError(@"Couldn't %@ key %@ in the keychain. %@", updateType, key, errorDescription);
    }
}

- (void)setUserID:(NSString *)userID {
    // always set it, since nil value will trigger removal of the keychain entry
    _userID = userID;
    
    [self modifyKeychainUserValue:userID forKey:kPREDMetaUserID];
}

- (void)setUserName:(NSString *)userName {
    // always set it, since nil value will trigger removal of the keychain entry
    _userName = userName;
    
    [self modifyKeychainUserValue:userName forKey:kPREDMetaUserName];
}

- (void)setUserEmail:(NSString *)userEmail {
    // always set it, since nil value will trigger removal of the keychain entry
    _userEmail = userEmail;
    
    [self modifyKeychainUserValue:userEmail forKey:kPREDMetaUserEmail];
}


- (NSString *)version {
    return [PREDVersion getSDKVersion];
}

- (NSString *)build {
    return [PREDVersion getSDKBuild];
}

#pragma mark - Private Instance Methods

- (PREDNetworkClient *)hockeyAppClient {
    if (!_hockeyAppClient) {
        _hockeyAppClient = [[PREDNetworkClient alloc] initWithBaseURL:[NSURL URLWithString:self.serverURL]];
    }
    return _hockeyAppClient;
}

- (void)logPingMessageForStatusCode:(NSInteger)statusCode {
    switch (statusCode) {
        case 400:
            PREDLogError(@"App ID not found");
            break;
        case 201:
            PREDLogDebug(@"Ping accepted.");
            break;
        case 200:
            PREDLogDebug(@"Ping accepted. Server already knows.");
            break;
        default:
            PREDLogError(@"Unknown error");
            break;
    }
}

- (void)validateStartManagerIsInvoked {
    if (_validAppIdentifier && (self.appEnvironment != PREDEnvironmentAppStore)) {
        if (!_startManagerIsInvoked) {
            PREDLogError(@"You did not call [[PREDManager sharedPREDManager] startManager] to startup the PreDemObjc! Please do so after setting up all properties. The SDK is NOT running.");
        }
    }
}

- (BOOL)isSetUpOnMainThread {
    NSString *errorString = @"PreDemObjc has to be setup on the main thread!";
    
    if (!NSThread.isMainThread) {
        if (self.appEnvironment == PREDEnvironmentAppStore) {
            PREDLogError(@"%@", errorString);
        } else {
            PREDLogError(@"%@", errorString);
            NSAssert(NSThread.isMainThread, errorString);
        }
        
        return NO;
    }
    
    return YES;
}

- (BOOL)shouldUseLiveIdentifier {
    BOOL delegateResult = NO;
    if ([_delegate respondsToSelector:@selector(shouldUseLiveIdentifierForPREDManager:)]) {
        delegateResult = [(NSObject <PREDManagerDelegate>*)_delegate shouldUseLiveIdentifierForPREDManager:self];
    }
    
    return (delegateResult) || (_appEnvironment == PREDEnvironmentAppStore);
}

- (void)initializeModules {
    if (_managersInitialized) {
        PREDLogWarning(@"The SDK should only be initialized once! This call is ignored.");
        return;
    }
    
    _validAppIdentifier = [self checkValidityOfAppIdentifier:_appIdentifier];
    
    if (![self isSetUpOnMainThread]) return;
    
    _startManagerIsInvoked = NO;
    
    if (_validAppIdentifier) {
        PREDLogDebug(@"Setup CrashManager");
        _crashManager = [[PREDCrashManager alloc] initWithAppIdentifier:_appIdentifier
                                                         appEnvironment:_appEnvironment
                                                        hockeyAppClient:[self hockeyAppClient]];
        _crashManager.delegate = _delegate;
        
        
        PREDLogDebug(@"Setup MetricsManager");
        _metricsManager = [[PREDMetricsManager alloc] initWithAppIdentifier:_appIdentifier appEnvironment:_appEnvironment];
        
        _managersInitialized = YES;
    } else {
        [self logInvalidIdentifier:@"app identifier"];
    }
}

- (void)applyConfig:(PREDConfig *)config {
    self.disableCrashManager = !config.crashReportEnabled;
    self.disableMetricsManager = !config.telemetryEnabled;
    self.disableHttpMonitor = !config.httpMonitorEnabled;
}

- (void)diagnose:(NSString *)host
        complete:(PREDNetDiagCompleteHandler)complete {
    [PREDNetDiag diagnose:host appKey:_appIdentifier complete:complete];
}

- (void)configManager:(PREDConfigManager *)manager didReceivedConfig:(PREDConfig *)config {
    [self applyConfig:config];
}

#pragma mark - Private Class Methods

- (BOOL)checkValidityOfAppIdentifier:(NSString *)identifier {
    BOOL result = NO;
    
    if (identifier) {
        NSCharacterSet *hexSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"];
        NSCharacterSet *inStringSet = [NSCharacterSet characterSetWithCharactersInString:identifier];
        result = ([identifier length] == 32) && ([hexSet isSupersetOfSet:inStringSet]);
    }
    
    return result;
}

- (void)logInvalidIdentifier:(NSString *)environment {
    if (self.appEnvironment != PREDEnvironmentAppStore) {
        if ([environment isEqualToString:@"liveIdentifier"]) {
            PREDLogWarning(@"The liveIdentifier is invalid! The SDK will be disabled when deployed to the App Store without setting a valid app identifier!");
        } else {
            PREDLogError(@"The %@ is invalid! Please use the PreDem app identifier you find on the apps website on PreDem! The SDK is disabled!", environment);
        }
    }
}

@end
