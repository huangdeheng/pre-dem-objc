//
//  PREDEnums.h
//  PreDemObjc
//
//  Created by Lukas Spieß on 08/10/15.
//
//

#ifndef PreDemObjc_Enums_h
#define PreDemObjc_Enums_h

@class PREDNetDiagResult;

/**
 *  PreDemObjc Log Levels
 */
typedef NS_ENUM(NSUInteger, PREDLogLevel) {
    /**
     *  Logging is disabled
     */
    PREDLogLevelNone = 0,
    /**
     *  Only errors will be logged
     */
    PREDLogLevelError = 1,
    /**
     *  Errors and warnings will be logged
     */
    PREDLogLevelWarning = 2,
    /**
     *  Debug information will be logged
     */
    PREDLogLevelDebug = 3,
    /**
     *  Logging will be very chatty
     */
    PREDLogLevelVerbose = 4
};

/**
 *  PreDemObjc App environment
 */
typedef NS_ENUM(NSInteger, PREDEnvironment) {
    /**
     *  App has been downloaded from the AppStore
     */
    PREDEnvironmentAppStore = 0,
    /**
     *  App has been downloaded from TestFlight
     */
    PREDEnvironmentTestFlight = 1,
    /**
     *  App has been installed by some other mechanism.
     *  This could be Ad-Hoc, Enterprise, etc.
     */
    PREDEnvironmentOther = 99
};

/**
 *  PreDemObjc Crash Reporter error domain
 */
typedef NS_ENUM (NSInteger, PREDCrashErrorReason) {
    /**
     *  Unknown error
     */
    PREDCrashErrorUnknown,
    /**
     *  API Server rejected app version
     */
    PREDCrashAPIAppVersionRejected,
    /**
     *  API Server returned empty response
     */
    PREDCrashAPIReceivedEmptyResponse,
    /**
     *  Connection error with status code
     */
    PREDCrashAPIErrorWithStatusCode
};

typedef void (^PREDNetDiagCompleteHandler)(PREDNetDiagResult* result);

typedef NSString *(^PREDLogMessageProvider)(void);

typedef void (^PREDLogHandler)(PREDLogMessageProvider messageProvider, PREDLogLevel logLevel, const char *file, const char *function, uint line);

#endif /* PreDemObjc_Enums_h */
