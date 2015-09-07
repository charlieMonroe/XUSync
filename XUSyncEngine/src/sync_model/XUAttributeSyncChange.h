//
//  XUAttributeSyncChange.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChange.h"

/** This class represents a change of attribute's value. */
@interface XUAttributeSyncChange : XUSyncChange

/** Designated initializer. */
-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object attributeName:(nonnull NSString *)name andValue:(nullable id)value;


/** Name of the attribute. */
@property (readonly, strong, nonnull, nonatomic) NSString *attributeName;

/** Value of the attribute. */
@property (readonly, strong, nullable, nonatomic) id attributeValue;

@end

@interface XUAttributeSyncChange (Deprecation)
-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object UNAVAILABLE_ATTRIBUTE;
@end
