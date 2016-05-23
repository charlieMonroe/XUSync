//
//  XUSyncChange.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import <CoreData/CoreData.h>

@class XUManagedObject, XUSyncChangeSet;

/** This is a base class for all sync changes. Unlike TICDS, we use subclassing
 * instead of attributes to distinguish between sync changes.
 *
 * Unfortunately, the initial idea was that it would be required for 
 * XUManagedObject to be an actual entity, but this kind of went downhill due
 * to maintaining backward compatibility with TICDS...
 */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore.")
@interface XUSyncChange : NSManagedObject

/** Creates a new sync change */
-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object;


/** Change set this change belongs to. Nil during initialization, hence nullable,
 * but otherwise should be nonnull.
 */
@property (readonly, strong, nullable, nonatomic) XUSyncChangeSet *changeSet;

/** Name of the entity. */
@property (readonly, strong, nonnull, nonatomic) NSString *objectEntityName;

/** This is generally all we need to identify the object. */
@property (readonly, strong, nonnull, nonatomic) NSString *objectSyncID;

/** Object that is being sync'ed. Only stored locally. */
@property (readonly, weak, nullable, nonatomic) XUManagedObject *syncObject;

/** Timestamp of the change. */
@property (readonly, nonatomic) NSTimeInterval timestamp;

@end

@interface XUSyncChange (Deprecation)
-(nonnull instancetype)init UNAVAILABLE_ATTRIBUTE;
-(nonnull instancetype)initWithEntity:(nonnull NSEntityDescription *)entity insertIntoManagedObjectContext:(nullable NSManagedObjectContext *)context UNAVAILABLE_ATTRIBUTE;
@end
