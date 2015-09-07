//
//  XURelationshipSyncChange.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XURelationshipSyncChange.h"

#import "XUManagedObject.h"

@interface XURelationshipSyncChange ()
@property (readwrite, strong, nonnull, nonatomic) NSString *relationshipName;
@property (readwrite, strong, nullable, nonatomic) NSString *valueEntityName;
@property (readwrite, strong, nullable, nonatomic) NSString *valueSyncID;
@end

@implementation XURelationshipSyncChange

@dynamic relationshipName;
@dynamic valueEntityName;
@dynamic valueSyncID;

-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object relationshipName:(nonnull NSString *)relationship andValue:(nullable XUManagedObject *)value{
	self = [super initWithObject:object];
	
	[self setRelationshipName:relationship];
	[self setValueEntityName:[[value entity] name]];
	[self setValueSyncID:[value syncUUID]];
	
	return self;
}

@end
