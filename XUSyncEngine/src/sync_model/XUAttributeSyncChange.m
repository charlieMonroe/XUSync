//
//  XUAttributeSyncChange.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUAttributeSyncChange.h"

@interface XUAttributeSyncChange ()
@property (readwrite, strong, nonnull, nonatomic) NSString *attributeName;
@property (readwrite, strong, nullable, nonatomic) id attributeValue;
@end

@implementation XUAttributeSyncChange

@dynamic attributeName;
@dynamic attributeValue;

-(nonnull instancetype)initWithObject:(nonnull XUManagedObject *)object attributeName:(nonnull NSString *)name andValue:(nullable id)value{
	self = [super initWithObject:object];
	
	[self setAttributeName:name];
	[self setAttributeValue:value];
	return self;
}

@end
