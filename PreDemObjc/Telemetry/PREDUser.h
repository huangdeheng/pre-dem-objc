#import "PREDTelemetryObject.h"

@interface PREDUser : PREDTelemetryObject <NSCoding>

@property (nonatomic, copy) NSString *accountAcquisitionDate;
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *userAgent;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, copy) NSString *storeRegion;
@property (nonatomic, copy) NSString *authUserId;
@property (nonatomic, copy) NSString *anonUserAcquisitionDate;
@property (nonatomic, copy) NSString *authUserAcquisitionDate;

- (BOOL)isEqualToUser:(PREDUser *)aUser;

@end
