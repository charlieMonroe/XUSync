//
//  XUInsertionSyncChange.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChange.h"

/** This class represents a sync change where an object has been inserted
 * into the MOC.
 */
DEPRECATED_MSG_ATTRIBUTE("Use XUCore")
@interface XUInsertionSyncChange : XUSyncChange

/** A list of all attributes. Created by -initWithObject:. Relationships are
 * handled by separate relationship changes.
 *
 * The dictionary is marked as Transformable, hence it's not all that efficient
 * when it comes to deserialization - if possible, query this property as little
 * as possible.
 */
@property (readonly, strong, nullable, nonatomic) NSDictionary *attributes;

/** Name of the entity being inserted. Created by -initWithObject:. */
@property (readonly, strong, nonnull, nonatomic) NSString *insertedEntityName;

@end
