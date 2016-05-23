//
//  XURelationshipSyncChange.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChange.h"

/** This is an abstract class representing relationship sync changes. */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore.")
@interface XURelationshipSyncChange : XUSyncChange

/** Designated initializer. */
-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object relationshipName:(nonnull NSString *)relationship andValue:(nullable XUManagedObject *)value;


/** Name of the relationship. */
@property (readonly, strong, nonnull, nonatomic) NSString *relationshipName;

/** Name of the entity of value. */
@property (readonly, strong, nullable, nonatomic) NSString *valueEntityName;

/** ID of the object that is being either deleted from or inserted into
 * the relationship.
 */
@property (readonly, strong, nullable, nonatomic) NSString *valueSyncID;

@end

@interface XURelationshipSyncChange (Deprecation)
-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object UNAVAILABLE_ATTRIBUTE;
@end
