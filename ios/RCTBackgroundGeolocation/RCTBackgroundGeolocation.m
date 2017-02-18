//
//  RCTBackgroundGeolocation.m
//  RCTBackgroundGeolocation
//
//  Created by Marian Hello on 04/06/16.
//  Copyright © 2016 mauron85. All rights reserved.
//

#import "RCTBackgroundGeolocation.h"
#import <React/RCTLog.h>
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import "Logging.h"

#define isNull(value) value == nil || [value isKindOfClass:[NSNull class]]

@implementation RCTBackgroundGeolocation

FMDBLogger *sqliteLogger;

@synthesize bridge = _bridge;
@synthesize locationManager;

RCT_EXPORT_MODULE();


-(instancetype)init
{
    self = [super init];
    if (self) {
        //[DDLog addLogger:[DDASLLogger sharedInstance] withLevel:DDLogLevelInfo];
        //[DDLog addLogger:[DDTTYLogger sharedInstance] withLevel:DDLogLevelDebug];
        
        sqliteLogger = [[FMDBLogger alloc] initWithLogDirectory:[self loggerDirectory]];
        sqliteLogger.saveThreshold     = 1;
        sqliteLogger.saveInterval      = 0;
        sqliteLogger.maxAge            = 60 * 60 * 24 * 7; //  7 days
        sqliteLogger.deleteInterval    = 60 * 60 * 24;     //  1 day
        sqliteLogger.deleteOnEverySave = NO;
        
        [DDLog addLogger:sqliteLogger withLevel:DDLogLevelDebug];

        locationManager = [[LocationManager alloc] init];
        locationManager.delegate = self;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onPause:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume:) name:UIApplicationWillEnterForegroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onFinishLaunching:) name:UIApplicationDidFinishLaunchingNotification object:nil];        
    }

    return self;
}

/**
 * configure plugin
 */
RCT_EXPORT_METHOD(configure:(NSDictionary*)configDictionary success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #configure");
    Config* config = [Config fromDictionary:configDictionary];
    NSError *error = nil;
    
    if ([locationManager configure:config error:&error]) {
        success(@[[NSNull null]]);
    } else {
        failure(@[@"Configuration error"]);
    }
}

RCT_EXPORT_METHOD(start:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #start");
    NSError *error = nil;
    [locationManager start:&error];

    if (error == nil) {
        success(@[[NSNull null]]);
    } else {
        failure(@[[error userInfo]]);
    }
}

RCT_EXPORT_METHOD(stop:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #stop");
    NSError *error = nil;
    [locationManager stop:&error];

    if (error == nil) {
        success(@[[NSNull null]]);
    } else {
        failure(@[[error userInfo]]);
    }
}

RCT_EXPORT_METHOD(switchMode:(NSNumber*)mode success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #getLogEntries");
    [locationManager switchMode:[mode integerValue]];
}

RCT_EXPORT_METHOD(finish)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #finish");
    [locationManager finish];
}

RCT_EXPORT_METHOD(isLocationEnabled:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #isLocationEnabled");
    success(@[@([locationManager isLocationEnabled])]);
}

RCT_EXPORT_METHOD(showAppSettings)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #showAppSettings");
    [locationManager showAppSettings];
}

RCT_EXPORT_METHOD(showLocationSettings)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #showLocationSettings");
    [locationManager showLocationSettings];
}

RCT_EXPORT_METHOD(getLocations:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #getLocations");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *locations = [locationManager getLocations];
        NSMutableArray* dictionaryLocations = [[NSMutableArray alloc] initWithCapacity:[locations count]];
        for (Location* location in locations) {
            [dictionaryLocations addObject:[location toDictionary]];
        }
        success(@[dictionaryLocations]);
    });
}

RCT_EXPORT_METHOD(getValidLocations:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #getValidLocations");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *locations = [locationManager getValidLocations];
        NSMutableArray* dictionaryLocations = [[NSMutableArray alloc] initWithCapacity:[locations count]];
        for (Location* location in locations) {
            [dictionaryLocations addObject:[location toDictionary]];
        }
        success(@[dictionaryLocations]);
    });
}

RCT_EXPORT_METHOD(deleteLocation:(int)locationId success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #deleteLocation");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [locationManager deleteLocation:[NSNumber numberWithInt:locationId]];
    });
}

RCT_EXPORT_METHOD(deleteAllLocations:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #deleteAllLocations");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [locationManager deleteAllLocations];
    });
}

RCT_EXPORT_METHOD(getLogEntries:(int)limit success:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #getLogEntries");
//    limit = isNull(limit) ? [NSNumber numberWithInt:0] : limit;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *path = [[self loggerDirectory] stringByAppendingPathComponent:@"log.sqlite"];
        NSArray *logs = [LogReader getEntries:path limit:(NSInteger)limit];
        success(@[logs]);
    });
}

RCT_EXPORT_METHOD(getConfig:(RCTResponseSenderBlock)success failure:(RCTResponseSenderBlock)failure)
{
    RCTLogInfo(@"RCTBackgroundGeolocation #getConfig");
    Config *config = [locationManager getConfig];
    success(@[[config toDictionary]]);
}

-(void) sendEvent:(NSString*)name resultAsDictionary:(NSDictionary*)resultAsDictionary
{
    NSString *event = [NSString stringWithFormat:@"%@", name];
    [_bridge.eventDispatcher sendDeviceEventWithName:event body:resultAsDictionary];
}

-(void) sendEvent:(NSString*)name resultAsArray:(NSArray*)resultAsArray
{
    NSString *event = [NSString stringWithFormat:@"%@", name];
    [_bridge.eventDispatcher sendDeviceEventWithName:event body:resultAsArray];
}

-(void) sendEvent:(NSString*)name resultAsNumber:(NSNumber*)resultAsNumber
{
    NSString *event = [NSString stringWithFormat:@"%@", name];
    [_bridge.eventDispatcher sendDeviceEventWithName:event body:resultAsNumber];
}

- (NSString *)loggerDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    
    return [basePath stringByAppendingPathComponent:@"SQLiteLogger"];
}

- (void) onAuthorizationChanged:(NSInteger)authStatus
{
    RCTLogInfo(@"RCTBackgroundGeolocation onAuthorizationChanged");
    [self sendEvent:@"authorizationChanged" resultAsNumber:[NSNumber numberWithInteger:authStatus]];
}

- (void) onLocationChanged:(Location*)location
{
    RCTLogInfo(@"RCTBackgroundGeolocation onLocationChanged");
    [self sendEvent:@"location" resultAsDictionary:[location toDictionary]];
}

- (void) onLocationsChanged:(NSArray*)locations
{
    RCTLogInfo(@"RCTBackgroundGeolocation onLocationsChanged");
    [self sendEvent:@"locations" resultAsArray:locations];
}

- (void) onStationaryChanged:(Location*)location
{
    RCTLogInfo(@"RCTBackgroundGeolocation onStationaryChanged");
    [self sendEvent:@"stationary" resultAsDictionary:[location toDictionary]];
}

- (void) onError:(NSError*)error
{
    RCTLogInfo(@"RCTBackgroundGeolocation onStationaryChanged");
    [self sendEvent:@"error" resultAsDictionary:[error userInfo]];
}

/**@
 * Resume.  Turn background off
 */
-(void) onResume:(NSNotification *)notification
{
    RCTLogInfo(@"CDVBackgroundGeoLocation resumed");
    [locationManager switchMode:FOREGROUND];
}

-(void) onPause:(NSNotification *)notification
{
    RCTLogInfo(@"CDVBackgroundGeoLocation paused");
    [locationManager switchMode:BACKGROUND];
}

/**@
 * on UIApplicationDidFinishLaunchingNotification
 */
-(void) onFinishLaunching:(NSNotification *)notification
{
    NSDictionary *dict = [notification userInfo];
    
    if ([dict objectForKey:UIApplicationLaunchOptionsLocationKey]) {
        DDLogInfo(@"CDVBackgroundGeolocation started by system on location event.");
        //        [manager switchOperationMode:BACKGROUND];
    }
}

-(void) onAppTerminate
{
    DDLogInfo(@"CDVBackgroundGeoLocation appTerminate");
    [locationManager onAppTerminate];
}

@end
