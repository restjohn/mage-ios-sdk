//
//  LocationFetchService.m
//  mage-ios-sdk
//
//

#import "LocationFetchService.h"
#import "Location.h"
#import "MageSessionManager.h"
#import "UserUtility.h"

NSString * const kLocationFetchFrequencyKey = @"userFetchFrequency";

@interface LocationFetchService ()
    @property (nonatomic) NSTimeInterval interval;
    @property (nonatomic, strong) NSTimer* locationFetchTimer;
@end

@implementation LocationFetchService

+ (instancetype) singleton {
    static LocationFetchService *fetchService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fetchService = [[self alloc] init];
    });
    return fetchService;
}

- (id) init {
    if (self = [super init]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        _interval = [[defaults valueForKey:kLocationFetchFrequencyKey] doubleValue];
        
        [[NSUserDefaults standardUserDefaults] addObserver:self
                                                forKeyPath:kLocationFetchFrequencyKey
                                                   options:NSKeyValueObservingOptionNew
                                                   context:NULL];
    }
	
	return self;
}

- (void) start {
    [self stop];

    [self pullLocations];
}

- (void) scheduleTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        _locationFetchTimer = [NSTimer scheduledTimerWithTimeInterval:_interval target:self selector:@selector(onTimerFire) userInfo:nil repeats:NO];
    });
}

- (void) onTimerFire {
    NSLog(@"timer to pull locations fired");
    if (![[UserUtility singleton] isTokenExpired]) {
        [self pullLocations];
    }
}

- (void) pullLocations{
    NSURLSessionDataTask *locationFetchTask = [Location operationToPullLocationsWithSuccess: ^{
        if (![[UserUtility singleton] isTokenExpired]) {
            NSLog(@"Scheduling the location fetch timer");
            [self scheduleTimer];
        }
    } failure:^(NSError* error) {
        NSLog(@"Failed to pull locations, scheduling the timer again");
        [self scheduleTimer];
    }];
    
    NSLog(@"pulling locations");
    [[MageSessionManager manager] addTask:locationFetchTask];
}

-(void) stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_locationFetchTimer isValid]) {
            NSLog(@"Stopping the location fetch timer");
            [_locationFetchTimer invalidate];
            _locationFetchTimer = nil;
        }
    });
}

- (void) observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    _interval = [[change objectForKey:NSKeyValueChangeNewKey] doubleValue];
    [self start];
}


@end
