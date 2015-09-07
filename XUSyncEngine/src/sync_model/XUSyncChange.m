//
//  XUSyncChange.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChange.h"

#import "XUDocumentSyncManager.h"
#import "XUManagedObject.h"

@interface XUSyncChange ()
@property (readwrite, strong, nonnull, nonatomic) NSString *objectEntityName;
@property (readwrite, strong, nonnull, nonatomic) NSString *objectSyncID;
@property (readwrite, nonatomic) NSTimeInterval timestamp;
@end

@implementation XUSyncChange

@dynamic changeSet;
@dynamic objectEntityName;
@dynamic objectSyncID;
@synthesize syncObject = _syncObject;
@dynamic timestamp;

-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object{
	NSManagedObjectContext *ctx = [[[object managedObjectContext] documentSyncManager] syncManagedObjectContext];
	self = [super initWithEntity:[NSEntityDescription entityForName:NSStringFromClass([self class]) inManagedObjectContext:ctx] insertIntoManagedObjectContext:ctx];
	
	_syncObject = object;
	
	[self setObjectEntityName:[[object entity] name]];
	[self setObjectSyncID:[object syncUUID]];
	[self setTimestamp:[NSDate timeIntervalSinceReferenceDate]];
	
	return self;
}

@end
