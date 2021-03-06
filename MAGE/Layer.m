//
//  Layer.m
//  mage-ios-sdk
//
//  Created by William Newman on 4/13/16.
//  Copyright © 2016 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Layer.h"
#import "MageSessionManager.h"
#import "MageServer.h"
#import "StaticLayer.h"

@implementation Layer

NSString * const LayerFetched = @"mil.nga.giat.mage.layer.fetched";

- (id) populateObjectFromJson: (NSDictionary *) json withEventId: (NSNumber *) eventId {
    [self setRemoteId:[json objectForKey:@"id"]];
    [self setName:[json objectForKey:@"name"]];
    [self setType:[json objectForKey:@"type"]];
    [self setUrl:[json objectForKey:@"url"]];
    [self setFormId:[json objectForKey:@"formId"]];
    [self setEventId:eventId];
    
    return self;
}

+ (NSString *) layerIdFromJson:(NSDictionary *) json {
    return [json objectForKey:@"id"];
}

+ (NSString *) layerTypeFromJson:(NSDictionary *) json {
    return [json objectForKey:@"type"];
}

+ (void) refreshLayersForEvent:(NSNumber *)eventId {
    MageSessionManager *manager = [MageSessionManager manager];
    NSURLSessionDataTask *task = [Layer operationToPullLayersForEvent:eventId success:^{
        [[NSNotificationCenter defaultCenter] postNotificationName:LayerFetched object:nil];
        NSArray *staticLayers = [StaticLayer MR_findAllWithPredicate:[NSPredicate predicateWithFormat:@"eventId == %@", eventId]];
        for (StaticLayer *l in staticLayers) {
            NSURLSessionDataTask *fetchFeaturesTask = [StaticLayer operationToFetchStaticLayerData:l];
            [manager addTask:fetchFeaturesTask];
        }
    } failure:^(NSError *error) {
        [[NSNotificationCenter defaultCenter] postNotificationName:LayerFetched object:nil];
    }];
    [manager addTask:task];
}

+ (NSURLSessionDataTask *) operationToPullLayersForEvent: (NSNumber *) eventId success: (void (^)()) success failure: (void (^)(NSError *)) failure {
    
    NSString *url = [NSString stringWithFormat:@"%@/api/events/%@/layers", [MageServer baseURL], eventId];
    
    MageSessionManager *manager = [MageSessionManager manager];
    NSURLSessionDataTask *task = [manager GET_TASK:url parameters:nil progress:nil success:^(NSURLSessionTask *task, id responseObject) {
        [MagicalRecord saveWithBlock:^(NSManagedObjectContext *localContext) {
            [StaticLayer MR_deleteAllMatchingPredicate:[NSPredicate predicateWithFormat:@"eventId == %@", eventId] inContext:localContext];
            
            NSArray *layers = responseObject;
            
            NSMutableArray *layerRemoteIds = [[NSMutableArray alloc] init];
            
            for (id layer in layers) {
                NSString *remoteLayerId = [Layer layerIdFromJson:layer];
                [layerRemoteIds addObject:remoteLayerId];
                if ([[Layer layerTypeFromJson:layer] isEqualToString:@"Feature"]) {
                    [StaticLayer createOrUpdateStaticLayer:layer withEventId:eventId inContext:localContext];
                } else {
                    Layer *l = [Layer MR_findFirstWithPredicate:[NSPredicate predicateWithFormat:@"(remoteId == %@ AND eventId == %@)", remoteLayerId, eventId] inContext:localContext];
                    if (l == nil) {
                        l = [Layer MR_createEntityInContext:localContext];
                        [l populateObjectFromJson:layer withEventId:eventId];
                        NSLog(@"Inserting layer with id: %@ in event: %@", l.remoteId, eventId);
                    } else {
                        NSLog(@"Updating layer with id: %@ in event: %@", l.remoteId, eventId);
                        [l populateObjectFromJson:layer withEventId:eventId];
                    }
                }
            }
            [Layer MR_deleteAllMatchingPredicate:[NSPredicate predicateWithFormat:@"(NOT (remoteId IN %@)) AND eventId == %@", layerRemoteIds, eventId] inContext:localContext];
            [StaticLayer MR_deleteAllMatchingPredicate:[NSPredicate predicateWithFormat:@"(NOT (remoteId IN %@)) AND eventId == %@", layerRemoteIds, eventId] inContext:localContext];
        } completion:^(BOOL contextDidSave, NSError *error) {
            if (error) {
                if (failure) {
                    failure(error);
                }
            } else if (success) {
                success();
            }
        }];
    } failure:^(NSURLSessionTask *operation, NSError *error) {
        NSLog(@"Error: %@", error);
        if (failure) {
            failure(error);
        }
    }];
    
    return task;
}
@end
