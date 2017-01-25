//
//  LocationDelegate.h
//  CDVBackgroundGeolocation
//
//  Created by Marian Hello on 14/09/2016.
//  Copyright © 2016 mauron85. All rights reserved.
//

#ifndef LocationDelegate_h
#define LocationDelegate_h

#import "Location.h"

// Debug sounds for bg-geolocation life-cycle events.
// http://iphonedevwiki.net/index.php/AudioServices
#define exitRegionSound         1005
#define locationSyncSound       1004
#define paceChangeYesSound      1110
#define paceChangeNoSound       1112
#define acquiringLocationSound  1103
#define acquiredLocationSound   1052
#define locationErrorSound      1073

enum BGAuthorizationStatus {
    NOT_DETERMINED = 0,
    ALLOWED,
    DENIED
};

enum BGErrorCode {
    UNKNOWN_LOCATION_PROVIDER = 1,
    NOT_IMPLEMENTED = 99
};

enum BGOperationMode {
    BACKGROUND = 0,
    FOREGROUND = 1
};

typedef NSUInteger BGOperationMode;

@protocol LocationDelegate <NSObject>

- (void) onAuthorizationChanged:(NSInteger)authStatus;
- (void) onLocationChanged:(Location*)location;
- (void) onLocationsChanged:(NSArray*)locations;
- (void) onStationaryChanged:(Location*)location;
- (void) onError:(NSError*)error;

@end

#endif /* LocationDelegate_h */
