//
//  ActivityLocationProvider.m
//  CDVBackgroundGeolocation
//
//  Created by Marian Hello on 14/09/2016.
//  Copyright © 2016 mauron85. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ActivityLocationProvider.h"
#import "Logging.h"

static NSString * const TAG = @"ActivityLocationProvider";
static NSString * const Domain = @"com.marianhello";

@interface ActivityLocationProvider () <CLLocationManagerDelegate>
@end

@implementation ActivityLocationProvider {
    BOOL isUpdatingLocation;
    
    BGOperationMode operationMode;
    NSDate *aquireStartTime;
    //    BOOL shouldStart; //indicating intent to start service, but we're waiting for user permission
    
    CLLocationManager *locationManager;
    
    // configurable options
    Config *_config;
    
    NSMutableArray *locationBuffer;
}


- (id) init
{
    self = [super init];
    
    if (self == nil) {
        return self;
    }
    
    // background location cache, for when no network is detected.
    locationManager = [[CLLocationManager alloc] init];
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"9.0")) {
        DDLogDebug(@"DistanceFilterProvider iOS9 detected");
        locationManager.allowsBackgroundLocationUpdates = YES;
    }
    
    locationManager.delegate = self;
    
    isUpdatingLocation = NO;
    //    shouldStart = NO;
    
    locationBuffer = [[NSMutableArray alloc] init];
    
    return self;
}

- (void) onCreate {/* noop */}

/**
 * configure provider
 * @param {Config} configuration
 * @param {NSError} optional error
 */
- (BOOL) configure:(Config*)config error:(NSError * __autoreleasing *)outError
{
    DDLogVerbose(@"DistanceFilterProvider configure");
    _config = config;
    
    locationManager.pausesLocationUpdatesAutomatically = _config.pauseLocationUpdates;
    locationManager.activityType = [_config decodeActivityType];
    locationManager.distanceFilter = _config.distanceFilter; // meters
    locationManager.desiredAccuracy = [_config decodeDesiredAccuracy];
    
    return YES;
}

/**
 * Turn on background geolocation
 * in case of failure it calls error callback from configure method
 * may fire two callback when location services are disabled and when authorization failed
 */
- (BOOL) start:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"DistanceFilterProvider will start");
    
    NSUInteger authStatus;
    
    if ([CLLocationManager respondsToSelector:@selector(authorizationStatus)]) { // iOS 4.2+
        authStatus = [CLLocationManager authorizationStatus];
        
        if (authStatus == kCLAuthorizationStatusDenied) {
            NSDictionary *errorDictionary = @{ @"code": [NSNumber numberWithInt:DENIED], @"message" : @LOCATION_DENIED };
            if (outError != NULL) {
                *outError = [NSError errorWithDomain:Domain code:DENIED userInfo:errorDictionary];
            }
            
            return NO;
        }
        
        if (authStatus == kCLAuthorizationStatusRestricted) {
            NSDictionary *errorDictionary = @{ @"code": [NSNumber numberWithInt:DENIED], @"message" : @LOCATION_RESTRICTED };
            if (outError != NULL) {
                *outError = [NSError errorWithDomain:Domain code:DENIED userInfo:errorDictionary];
            }
            
            return NO;
        }
        
#ifdef __IPHONE_8_0
        // we do startUpdatingLocation even though we might not get permissions granted
        // we can stop later on when recieved callback on user denial
        // it's neccessary to start call startUpdatingLocation in iOS < 8.0 to show user prompt!
        
        if (authStatus == kCLAuthorizationStatusNotDetermined) {
            if ([locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {  //iOS 8.0+
                DDLogVerbose(@"DistanceFilterProvider requestWhenInUseAuthorization");
                [locationManager requestWhenInUseAuthorization];
            }
        }
#endif
    }
    
    [self switchMode:FOREGROUND];
    
    return YES;
}

/**
 * Turn it off
 */
- (BOOL) stop:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"DistanceFilterProvider stop");
    
    [self stopUpdatingLocation];
    
    return YES;
}

/**
 * toggle between foreground and background operation mode
 */
- (void) switchMode:(BGOperationMode)mode
{
    DDLogInfo(@"DistanceFilterProvider switchMode %lu", (unsigned long)mode);
    
    operationMode = mode;
    
    aquireStartTime = [NSDate date];
    
    NSLog(@"Buffer length %d", locationBuffer.count);
    
    if (locationBuffer.count > 0) {
        [super.delegate onLocationsChanged:locationBuffer];
        locationBuffer = nil;
        locationBuffer = [[NSMutableArray alloc] init];
    }

    // Crank up the GPS power temporarily to get a good fix on our current location
    [self stopUpdatingLocation];
    locationManager.distanceFilter = kCLDistanceFilterNone;
    locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    [self startUpdatingLocation];
}

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    DDLogDebug(@"DistanceFilterProvider didUpdateLocations (operationMode: %lu)", (unsigned long)operationMode);
    Location *bgloc;
    CLLocation *location;
    
    switch (operationMode) {
        case BACKGROUND:
            for (location in locations) {
                NSLog(@"Buffering location");
                [locationBuffer addObject:[[Location fromCLLocation:location] toDictionary]];
            }
            break;
            
        case FOREGROUND:
             for (location in locations) {
                bgloc = [Location fromCLLocation:location];
                [super.delegate onLocationChanged:bgloc];
            }
            break;
    }


    return;
}

- (void) locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager
{
    DDLogDebug(@"DistanceFilterProvider location updates paused");
    if (_config.isDebugging) {
        [self notify:@"Location updates paused"];
    }
}

- (void) locationManagerDidResumeLocationUpdates:(CLLocationManager *)manager
{
    DDLogDebug(@"DistanceFilterProvider location updates resumed");
    if (_config.isDebugging) {
        [self notify:@"Location updates resumed b"];
    }
}

- (void) locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    DDLogError(@"DistanceFilterProvider didFailWithError: %@", error);
    if (_config.isDebugging) {
        AudioServicesPlaySystemSound (locationErrorSound);
        [self notify:[NSString stringWithFormat:@"Location error: %@", error.localizedDescription]];
    }
    
    switch(error.code) {
        case kCLErrorLocationUnknown:
        case kCLErrorNetwork:
        case kCLErrorRegionMonitoringDenied:
        case kCLErrorRegionMonitoringSetupDelayed:
        case kCLErrorRegionMonitoringResponseDelayed:
        case kCLErrorGeocodeFoundNoResult:
        case kCLErrorGeocodeFoundPartialResult:
        case kCLErrorGeocodeCanceled:
            break;
        case kCLErrorDenied:
            break;
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(onError:)]) {
        [self.delegate onError:error];
    }
}

- (void) locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    DDLogInfo(@"LocationManager didChangeAuthorizationStatus %u", status);
    if (_config.isDebugging) {
        [self notify:[NSString stringWithFormat:@"Authorization status changed %u", status]];
    }

    switch(status) {
        case kCLAuthorizationStatusRestricted:
        case kCLAuthorizationStatusDenied:
            if (self.delegate && [self.delegate respondsToSelector:@selector(onAuthorizationChanged:)]) {
                [self.delegate onAuthorizationChanged:DENIED];
            }
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
        case kCLAuthorizationStatusAuthorizedAlways:
            if (self.delegate && [self.delegate respondsToSelector:@selector(onAuthorizationChanged:)]) {
                [self.delegate onAuthorizationChanged:ALLOWED];
            }
            break;
        default:
            break;
    }
}

- (void) stopUpdatingLocation
{
    if (isUpdatingLocation) {
        [locationManager stopUpdatingLocation];
        isUpdatingLocation = NO;
    }
}

- (void) startUpdatingLocation
{
    if (!isUpdatingLocation) {
        [locationManager startUpdatingLocation];
        isUpdatingLocation = YES;
    }
}

- (void) notify:(NSString*)message
{
    [super notify:message];
}

- (void) onDestroy
{
    locationManager.delegate = nil;
    //    [super dealloc];
}

@end
