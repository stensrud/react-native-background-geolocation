////
//  LocationManager
//
//  Created by Marian Hello on 04/06/16.
//  Version 2.0.0
//
//  According to apache license
//
//  This is class is using code from christocracy cordova-plugin-background-geolocation plugin
//  https://github.com/christocracy/cordova-plugin-background-geolocation
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "LocationManager.h"
#import "LocationUploader.h"
#import "SQLiteLocationDAO.h"
#import "BackgroundTaskManager.h"
#import "Reachability.h"
#import "Logging.h"
#import "ActivityLocationProvider.h"
#import "DistanceFilterLocationProvider.h"

// error messages
#define UNKNOWN_LOCATION_PROVIDER_MSG   "Unknown location provider."

static NSString * const Domain = @"com.marianhello";

@interface LocationManager () <LocationDelegate, LocationManagerDelegate>
@end

@implementation LocationManager {
    BOOL isStarted;
    BOOL hasConnectivity;
    
    BGOperationMode operationMode;
    //    BOOL shouldStart; //indicating intent to start service, but we're waiting for user permission
    
    UILocalNotification *localNotification;
    
    NSNumber *maxBackgroundHours;
    UIBackgroundTaskIdentifier bgTask;
    NSDate *lastBgTaskAt;
    
    // configurable options
    Config *_config;
    
    Location *stationaryLocation;
    NSMutableArray *locationQueue;
    AbstractLocationProvider<LocationProvider> *locationProvider;
    LocationUploader *uploader;
    Reachability *reach;
}


- (id) init
{
    self = [super init];
    
    if (self == nil) {
        return self;
    }
    
    reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    reach.reachableBlock = ^(Reachability *_reach){
        // keep in mind this is called on a background thread
        // and if you are updating the UI it needs to happen
        // on the main thread:
        DDLogInfo(@"Network is now reachable");
        hasConnectivity = YES;
        [_reach stopNotifier];
    };

    reach.unreachableBlock = ^(Reachability *reach) {
        DDLogInfo(@"Network is now unreachable");
        hasConnectivity = NO;
    };

    localNotification = [[UILocalNotification alloc] init];
    localNotification.timeZone = [NSTimeZone defaultTimeZone];

    locationQueue = [[NSMutableArray alloc] init];

    bgTask = UIBackgroundTaskInvalid;

    isStarted = NO;
    hasConnectivity = YES;
    //    shouldStart = NO;

    return self;
}

/**
 * configure manager
 * @param {Config} configuration
 * @param {NSError} optional error
 */
- (BOOL) configure:(Config*)config error:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"LocationManager configure with: %@", config);
    _config = config;

    // ios 8 requires permissions to send local-notifications
    if (_config.isDebugging) {
        UIApplication *app = [UIApplication sharedApplication];
        if ([app respondsToSelector:@selector(registerUserNotificationSettings:)]) {
            [app registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeBadge|UIUserNotificationTypeSound categories:nil]];
        }
    }
   
    if ([config hasSyncUrl] && uploader == nil) {
        uploader = [[LocationUploader alloc] init];
    }

    return YES;
}

/**
 * Turn on background geolocation
 * in case of failure it calls error callback from configure method
 * may fire two callback when location services are disabled and when authorization failed
 */
- (BOOL) start:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"LocationManager will start: %d", isStarted);

    if (isStarted) {
        return NO;
    }
    
    // Note: CLLocationManager must be created on a thread with an active run loop (main thread)
    __block NSError *error = nil;
    __block NSDictionary *errorDictionary;
    
    [self runOnMainThread:^{
        switch (_config.locationProvider) {
            case DISTANCE_FILTER_PROVIDER:
                locationProvider = [[DistanceFilterLocationProvider alloc] init];
                break;
            case ACTIVITY_PROVIDER:
                locationProvider = [[ActivityLocationProvider alloc] init];
                break;
            default:
                errorDictionary = @{ @"code": [NSNumber numberWithInt:UNKNOWN_LOCATION_PROVIDER], @"message": @UNKNOWN_LOCATION_PROVIDER_MSG };
                error = [NSError errorWithDomain:Domain code:UNKNOWN_LOCATION_PROVIDER userInfo:errorDictionary];
                return;
        }
       
        // trap configuration errors
        if (![locationProvider configure:_config error:&error]) {
            if (outError != nil) *outError = error;
            return;
        }
        
        isStarted = [locationProvider start:&error];
        locationProvider.delegate = self;
    }];

    if (locationProvider == nil) {
        if (outError != nil) *outError = error;
        return NO;
    }
    
    if (!isStarted) {
        if (outError != nil) *outError = error;
        return NO;
    }
  
    return isStarted;
}

/**
 * Turn off background geolocation
 */
- (BOOL) stop:(NSError * __autoreleasing *)outError
{
    DDLogInfo(@"LocationManager stop");

    if (!isStarted) {
        return YES;
    }

    [reach stopNotifier];
    
    [self runOnMainThread:^{
        isStarted = ![locationProvider stop:outError];
    }];

    return isStarted;
}

/**
 * toggle between foreground and background operation mode
 */
- (void) switchMode:(BGOperationMode)mode
{
    DDLogInfo(@"LocationManager switchMode %lu", (unsigned long)mode);

    operationMode = mode;

    if (!isStarted) return;

    if (_config.isDebugging) {
        AudioServicesPlaySystemSound (operationMode  == FOREGROUND ? paceChangeYesSound : paceChangeNoSound);
    }
   
    [self runOnMainThread:^{
        [locationProvider switchMode:mode];
    }];
}

/**
 * Called by js to signify the end of a background-geolocation event
 */
- (BOOL) finish
{
    DDLogInfo(@"LocationManager finish");
    [self stopBackgroundTask];
    return YES;
}

- (BOOL) isLocationEnabled
{
    if ([CLLocationManager respondsToSelector:@selector(locationServicesEnabled)]) { // iOS 4.x
        return [CLLocationManager locationServicesEnabled];
    }

    return NO;
}

- (void) showAppSettings
{
    BOOL canGoToSettings = (UIApplicationOpenSettingsURLString != NULL);
    if (canGoToSettings) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
    }
}

- (void) showLocationSettings
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=LOCATION_SERVICES"]];
}

- (Location*) getStationaryLocation
{
    return stationaryLocation;
}

- (NSArray<Location*>*) getLocations
{
    SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
    return [locationDAO getAllLocations];
}

- (NSArray<Location*>*) getValidLocations
{
    SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
    return [locationDAO getValidLocations];
}

- (BOOL) deleteLocation:(NSNumber*) locationId
{
    SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
    return [locationDAO deleteLocation:locationId];
}

- (BOOL) deleteAllLocations
{
    SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
    return [locationDAO deleteAllLocations];
}

- (Config*) getConfig
{
    return _config;
}

- (void) flushQueue
{
    // Sanity-check the duration of last bgTask:  If greater than 30s, kill it.
    if (bgTask != UIBackgroundTaskInvalid) {
        if (-[lastBgTaskAt timeIntervalSinceNow] > 30.0) {
            DDLogWarn(@"LocationManager#flushQueue has to kill an out-standing background-task!");
            if (_config.isDebugging) {
                [self notify:@"Outstanding bg-task was force-killed"];
            }
            [self stopBackgroundTask];
        }
        return;
    }

    Location *location;
    @synchronized(self) {
        if ([locationQueue count] < 1) {
            return;
        }
        // retrieve first queued location
        location = [locationQueue firstObject];
        [locationQueue removeObject:location];
    }

    // Create a background-task and delegate to Javascript for syncing location
    bgTask = [self createBackgroundTask];

    [self sync:location];

    if ([_config hasSyncUrl] || [_config hasUrl]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            if (hasConnectivity && [_config hasUrl]) {
                NSError *error = nil;
                if ([location postAsJSON:_config.url withHttpHeaders:_config.httpHeaders error:&error]) {
                    SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
                    if (location.id != nil) {
                        [locationDAO deleteLocation:location.id];
                    }
                } else {
                    DDLogWarn(@"LocationManager postJSON failed: error: %@", error.userInfo[@"NSLocalizedDescription"]);
                    hasConnectivity = [reach isReachable];
                    [reach startNotifier];
                }
            }

            NSString *syncUrl = [_config hasSyncUrl] ? _config.syncUrl : _config.url;
            [uploader sync:syncUrl onLocationThreshold:_config.syncThreshold];
        });
    }
}

- (UIBackgroundTaskIdentifier) createBackgroundTask
{
    lastBgTaskAt = [NSDate date];
    return [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self stopBackgroundTask];
    }];
}

- (void) stopBackgroundTask
{
    UIApplication *app = [UIApplication sharedApplication];
    if (bgTask != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
    [self flushQueue];
}

/**
 * We are running in the background if this is being executed.
 * We can't assume normal network access.
 * bgTask is defined as an instance variable of type UIBackgroundTaskIdentifier
 */
- (void) sync:(Location*)location
{
    DDLogInfo(@"LocationManager#sync %@", location);
    if (_config.isDebugging) {
        [self notify:[NSString stringWithFormat:@"Location update: %s\nSPD: %0.0f | DF: %ld | ACY: %0.0f",
            ((operationMode == FOREGROUND) ? "FG" : "BG"),
            [location.speed doubleValue],
            (long) locationProvider.distanceFilter,
            [location.accuracy doubleValue]
        ]];

        AudioServicesPlaySystemSound (locationSyncSound);
    }

    // Build a resultset for javascript callback.
    if (self.delegate && [self.delegate respondsToSelector:@selector(onLocationChanged:)]) {
        [self.delegate onLocationChanged:location];
    }
}

- (void) notify:(NSString*)message
{
    localNotification.fireDate = [NSDate date];
    localNotification.alertBody = message;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

-(void) runOnMainThread:(dispatch_block_t)completionHandle {
    BOOL alreadyOnMainThread = [NSThread isMainThread];
    // this check avoids possible deadlock resulting from
    // calling dispatch_sync() on the same queue as current one
    if (alreadyOnMainThread) {
        // execute code in place
        completionHandle();
    } else {
        // dispatch to main queue
        dispatch_sync(dispatch_get_main_queue(), completionHandle);
    }
}

- (void) onStationaryChanged:(Location *)location
{
    DDLogDebug(@"LocationManager#onStationaryChanged");
    stationaryLocation = location;

    // Any javascript stationaryRegion event-listeners?
    if (self.delegate && [self.delegate respondsToSelector:@selector(onStationaryChanged:)]) {
        [self.delegate onStationaryChanged:location];
    }
//    [self stopBackgroundTask];
}

- (void) onLocationChanged:(Location *)location
{
    DDLogDebug(@"LocationManager#onLocationChanged %@", location);
    stationaryLocation = nil;
    
    //SQLiteLocationDAO* locationDAO = [SQLiteLocationDAO sharedInstance];
    //location.id = [locationDAO persistLocation:location limitRows:_config.maxLocations];
    
    @synchronized(self) {
        [locationQueue addObject:location];
    }

    [self flushQueue];
}

- (void) onAuthorizationChanged:(NSInteger)authStatus
{
    [self.delegate onAuthorizationChanged:authStatus];
}

- (void) onError:(NSError*)error
{
    [self.delegate onError:error];
}

/**@
 * If you don't stopMonitoring when application terminates, the app will be awoken still when a
 * new location arrives, essentially monitoring the user's location even when they've killed the app.
 * Might be desirable in certain apps.
 */
- (void) onAppTerminate
{
    if (_config.stopOnTerminate) {
        DDLogInfo(@"LocationManager is stopping on app terminate.");
        [self stop:nil];
    } else {
        [self switchMode:BACKGROUND];
    }
}

- (void) dealloc
{
    [locationProvider onDestroy];
    //    [super dealloc];
}

@end
