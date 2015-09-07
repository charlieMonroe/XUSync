//
//  XUInsertionSyncChange.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUInsertionSyncChange.h"
#import "XUManagedObject.h"

@interface XUInsertionSyncChange ()
@property (readwrite, strong, nullable, nonatomic) NSDictionary *attributes;
@property (readwrite, strong, nonnull, nonatomic) NSString *insertedEntityName;
@end

@implementation XUInsertionSyncChange

@dynamic attributes;
@dynamic insertedEntityName;

-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object{
	self = [super initWithObject:object];
	
	// Create attribute changes
	NSDictionary *objectAttributeNames = [[object entity] attributesByName];
	NSMutableDictionary *attributeValues = [NSMutableDictionary dictionaryWithCapacity:[objectAttributeNames count]];
	for (NSString *attribute in objectAttributeNames) {
		[attributeValues setValue:[object valueForKey:attribute] forKey:attribute];
	}
	[self setAttributes:attributeValues];
	
	[self setInsertedEntityName:[[object entity] name]];
	
	return self;
}

@end
