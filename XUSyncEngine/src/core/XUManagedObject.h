//
//  TICDSSynchronizedManagedObject.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import <CoreData/CoreData.h>

@class XUSyncChange;

/** This is the base class for all synchronized objects. Upon insert, it generates
 * a syncUUID, which is used for tracking changes.
 *
 * In your model, however, you need to create an attribute ticdsSyncID instead,
 * since this framework is designed to be compatible with existing stores that
 * use TICDS.
 */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore.")
@interface XUManagedObject : NSManagedObject

/** Call this when processing an insertion change - this will let the managed
 * object class know that an object with this syncUUID has been inserted, so
 * that it doesn't create an unnecessary sync change.
 */
+(void)noticeSyncInsertionOfObjectWithID:(nonnull NSString *)syncUUID;

/** This applies the sync change. It asserts that [self syncUUID] ==
 * [syncChange objectSyncID].
 */
-(void)applySyncChange:(nonnull XUSyncChange *)syncChange;

/** It is discouraged to use -awakeFromInsert for one main reason - you usually
 * populate fields with default values in -awakeFromInsert. This is completely 
 * unnecessary and contra-productive when the entity is being created by the sync
 * engine, since it overrides all the values anyway.
 *
 * Moreover, if you create new objects or relationships within -awakeFromInsert,
 * you end up creating new sync changes which is definitely undesirable.
 *
 * @note - you must NOT create new entities within -awakeFromInsert! It would
 *			lead to a deadlock. Use -awakeFromNonSyncInsert instead.
 */
-(void)awakeFromInsert NS_REQUIRES_SUPER DEPRECATED_MSG_ATTRIBUTE("Use -awakeFromNonSyncInsert");

/** This is called from -awakeFromInsert if the object is not being created by
 * the sync engine.
 *
 * @note - for this to work, all instances need to be created using 
 *			-initWithEntity:insertIntoManagedObjectContext:
 */
-(void)awakeFromNonSyncInsert NS_REQUIRES_SUPER;

/** This method will create sync change if necessary for this object. */
-(nonnull NSArray *)createSyncChanges;

/** This acts as the original method, but takes an extra isSync parameter.
 * You usually don't need to use this from your code. @see -awakeFromNonSyncInsert
 * for more information.
 */
-(nonnull instancetype)initWithEntity:(nonnull NSEntityDescription *)entity insertIntoManagedObjectContext:(nullable NSManagedObjectContext *)context asResultOfSyncAction:(BOOL)isSync;



/** Marked as YES if the engine is currently applying a sync change. If you are
 * observing some changes made to the object, and creating further changes based
 * on that observation, you can opt-out based on this property.
 */
@property (readwrite, nonatomic) BOOL isApplyingSyncChange;

/** This is an important property that returns YES if the object is being created
 * by the sync engine - i.e. the entity was inserted into the context.
 *
 * While it may seem unnecessary, you usually populate fields with initial values
 * within -awakeFromInsert.
 *
 */
@property (readonly, nonatomic) BOOL isBeingCreatedBySyncEngine;

/** Sync UUID. This property is only a proxy to the underlying ticdsSyncID which
 * is implemented for backward compatibility with existing stores.
 */
@property (readonly, nonnull, nonatomic) NSString *syncUUID;

@end



/** This is just a compatibility class. */
@interface TICDSSynchronizedManagedObject : XUManagedObject
@end
