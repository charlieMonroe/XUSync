//
//  XUSyncChangeSet.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/31/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUSyncChangeSet.h"

@interface XUSyncChangeSet ()
@property (readwrite, strong, nonnull, nonatomic) NSSet *changes;
@property (readwrite, nonatomic) NSTimeInterval timestamp;
@end

@implementation XUSyncChangeSet

@dynamic changes;
@dynamic timestamp;

+(NSArray *)allChangeSetsInManagedObjectContext:(nonnull NSManagedObjectContext *)ctx withTimestampNewerThan:(NSTimeInterval)timestamp{
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(self)];
	NSArray *allChangeSets = [ctx executeFetchRequest:request error:NULL] ?: @[ ];
	NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(XUSyncChangeSet *changeSet, NSDictionary *bindings) {
		return [changeSet timestamp] > timestamp;
	}];
	return [allChangeSets filteredArrayUsingPredicate:predicate];
}
+(nullable XUSyncChangeSet *)newestChangeSetInManagedObjectContext:(nonnull NSManagedObjectContext *)ctx{
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass(self)];
	[request setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"timestamp" ascending:NO] ]];
	[request setFetchLimit:1];
	
	return [[ctx executeFetchRequest:request error:NULL] firstObject];
}

-(nonnull instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)ctx andChanges:(nonnull NSArray *)changes{
	self = [super initWithEntity:[NSEntityDescription entityForName:@"XUSyncChangeSet" inManagedObjectContext:ctx] insertIntoManagedObjectContext:ctx];

	[self setTimestamp:[NSDate timeIntervalSinceReferenceDate]];
	
	// Interestingly, [NSSet setWithArray:changes] creates a set that contains 1
	// object: the array - hum?
	NSMutableSet *set = [NSMutableSet set];
	for (id change in changes) {
		[set addObject:change];
	}
	[self setChanges:set];
	return self;
}

@end
