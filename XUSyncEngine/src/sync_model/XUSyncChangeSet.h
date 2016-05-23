//
//  XUSyncChangeSet.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/31/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import <CoreData/CoreData.h>

/** To make the syncing more efficient, we group XUSyncChanges in to change sets.
 * This allows XUSyncEngine to go just through a few change sets, instead of 
 * potentially hundreds or even thousands of actual changes.
 */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore.")
@interface XUSyncChangeSet : NSManagedObject

/** Fetches all change sets in the supplied MOC. */
+(nonnull NSArray *)allChangeSetsInManagedObjectContext:(nonnull NSManagedObjectContext *)ctx withTimestampNewerThan:(NSTimeInterval)timestamp;

/** Returns the newest change set in MOC, if one exists. */
+(nullable XUSyncChangeSet *)newestChangeSetInManagedObjectContext:(nonnull NSManagedObjectContext *)ctx;


/** Desginated initializer. */
-(nonnull instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)ctx andChanges:(nonnull NSArray *)changes;


/** A set of changes within this change set. */
@property (readonly, strong, nonnull, nonatomic) NSSet *changes;

/** Timestamp of the sync change set. */
@property (readonly, nonatomic) NSTimeInterval timestamp;

@end
