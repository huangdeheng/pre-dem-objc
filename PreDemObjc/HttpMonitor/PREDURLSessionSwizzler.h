//
//  PREDURLSessionSwizzler.h
//  PreDemSDK
//
//  Created by WangSiyu on 14/03/2017.
//  Copyright © 2017 pre-engineering. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PREDURLSessionSwizzler : NSObject

@property (nonatomic, assign) BOOL isSwizzle;

+ (PREDURLSessionSwizzler *)defaultSwizzler;
- (void)load;
- (void)unload;

@end
