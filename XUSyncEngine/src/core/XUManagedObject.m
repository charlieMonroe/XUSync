//
//  TICDSSynchronizedManagedObject.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/26/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUManagedObject.h"

#import "XUDocumentSyncManager.h"

#import "XUAttributeSyncChange.h"
#import "XUDeletionSyncChange.h"
#import "XUInsertionSyncChange.h"
#import "XUToManyRelationshipAdditionSyncChange.h"
#import "XUToManyRelationshipDeletionSyncChange.h"
#import "XUToOneRelationshipSyncChange.h"

/** These two static variables allow the mechanism described behind 
 * -awakeFromNonSyncInsert.
 */
static NSLock *_initializationLock;
static BOOL _currentInitInitiatedInSync = NO;


/** Theoretically, we could be adding insertion/deletion changes more than once,
 * since there is no way of knowing when the -createSyncChange method is called.
 *
 * We will hence keep a local list of UUIDs for which we've created insertion/
 * deletion changes.
 */
static NSLock *_changesLock;
static NSMutableSet *_deletionChanges;
static NSMutableSet *_insertionChanges;

/** This dictionary holds the last values of attributes. The dictionary
 * has this signature: [syncID:[attr:value]].
 *
 * Note that NSMutableSet set is used instead of NSMutableArray to prevent
 * duplicates.
 */
static NSMutableDictionary *_attributeValueChanges;

/** This dictionary holds the last values of relationships. The dictionary
 * has this signature: [syncID:[relationship:(syncID|[syncIDs])]].
 *
 * Note that NSMutableSet set is used instead of NSMutableArray to prevent
 * duplicates.
 */
static NSMutableDictionary *_relationshipValueChanges;

@interface XUManagedObject ()
@property (nonatomic, copy) NSString *ticdsSyncID;
@end

@implementation XUManagedObject

@dynamic ticdsSyncID;
@synthesize isApplyingSyncChange = _isApplyingSyncChange;

+(void)initialize{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_changesLock = [[NSLock alloc] init];
		_initializationLock = [[NSLock alloc] init];
		_deletionChanges = [[NSMutableSet alloc] init];
		_insertionChanges = [[NSMutableSet alloc] init];
		
		_attributeValueChanges = [[NSMutableDictionary alloc] init];
		_relationshipValueChanges = [[NSMutableDictionary alloc] init];
	});
}
+(void)noticeSyncInsertionOfObjectWithID:(nonnull NSString *)syncUUID{
	[_changesLock lock];
	[_insertionChanges addObject:syncUUID];
	[_changesLock unlock];
}

-(void)_applyAttributeSyncChange:(XUAttributeSyncChange *)syncChange{
	id value = [syncChange attributeValue];
	if ([value isKindOfClass:[NSNull class]]) {
		value = nil;
	}
	[self setValue:value forKey:[syncChange attributeName]];
	
	[_changesLock lock];
	
	NSMutableDictionary *changes = _attributeValueChanges[[self syncUUID]];
	if (changes == nil){
		changes = [NSMutableDictionary dictionary];
		_attributeValueChanges[[self syncUUID]] = changes;
	}
	
	// Change it back to null if necessary
	if (value == nil){
		value = [NSNull null];
	}
	changes[[syncChange attributeName]] = value;
	
	[_changesLock unlock];
}
-(void)_applyDeletionSyncChange:(XUDeletionSyncChange *)syncChange{
	// Delete
	NSString *UUID = [self syncUUID];
	[[self managedObjectContext] deleteObject:self];
	
	[_changesLock lock];
	[_deletionChanges addObject:UUID];
	[_changesLock unlock];
}
-(void)_applyToManyRelationshipAdditionSyncChange:(XUToManyRelationshipAdditionSyncChange *)syncChange{
	NSString *targetUUID = [syncChange valueSyncID];
	NSString *entityName = [syncChange valueEntityName];
	
	/** We need to fetch this object. Since all synchable objects are subclasses
	 * of XUManagedObject, we can look for XUManagedObject with such sync ID.
	 */
	NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
	[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"ticdsSyncID == %@", targetUUID]];
	
	NSError *err;
	NSArray *items = [[self managedObjectContext] executeFetchRequest:fetchRequest error:&err];
	if ([items count] != 1){
		NSLog(@"Cannot find object with syncID %@ - should be added for relationship %@", targetUUID, [syncChange relationshipName]);
		return;
	}
	
	NSMutableSet *valueSet = [[self valueForKey:[syncChange relationshipName]] mutableCopy];
	if (valueSet == nil) {
		valueSet = [NSMutableSet set];
	}
	
	[valueSet addObject:[items firstObject]];
	[self setValue:valueSet forKey:[syncChange relationshipName]];
	
	[_changesLock lock];
	NSMutableDictionary *relationshipValues = _relationshipValueChanges[[self syncUUID]];
	if (relationshipValues == nil){
		relationshipValues = [NSMutableDictionary dictionary];
		_relationshipValueChanges[[self syncUUID]] = relationshipValues;
	}
	
	NSMutableSet *UUIDs = relationshipValues[[syncChange relationshipName]];
	if (UUIDs == nil){
		UUIDs = [NSMutableSet set];
		relationshipValues[[syncChange relationshipName]] = UUIDs;
	}
	[UUIDs addObject:targetUUID];
	[_changesLock unlock];
}
-(void)_applyToManyRelationshipDeletionSyncChange:(XUToManyRelationshipDeletionSyncChange *)syncChange{
	NSString *targetUUID = [syncChange valueSyncID];
	
	NSMutableSet *valueSet = [[self valueForKey:[syncChange relationshipName]] mutableCopy];
	
	// Need to find the object
	id objectToDelete = nil;
	for (XUManagedObject *obj in valueSet){
		if ([[obj syncUUID] isEqualToString:targetUUID]){
			objectToDelete = obj;
			break;
		}
	}
	
	if (objectToDelete == nil){
		NSLog(@"Cannot remove object with syncID %@ - should be removed for relationship %@", targetUUID, [syncChange relationshipName]);
		return;
	}
	
	[valueSet removeObject:objectToDelete];
	[self setValue:valueSet forKey:[syncChange relationshipName]];
	
	[_changesLock lock];
	NSMutableDictionary *relationshipValues = _relationshipValueChanges[[self syncUUID]];
	if (relationshipValues == nil){
		relationshipValues = [NSMutableDictionary dictionary];
		_relationshipValueChanges[[self syncUUID]] = relationshipValues;
	}
	
	// Don't care if the array doesn't exist
	NSMutableSet *UUIDs = relationshipValues[[syncChange relationshipName]];
	[UUIDs removeObject:targetUUID];
	[_changesLock unlock];
}
-(void)_applyToOneRelationshipSyncChange:(XUToOneRelationshipSyncChange *)syncChange{
	NSString *targetUUID = [syncChange valueSyncID];
	if (targetUUID == nil){
		// Removing relationship - don't really care if the _relationshipValueChanges
		// actually contains a value
		
		if ([self valueForKey:[syncChange relationshipName]] != nil) {
			// It's already nil -> do not set it, since it could mark the entity
			// as updated.
			return;
		}
		
		[self setValue:nil forKey:[syncChange relationshipName]];
		
		[_changesLock lock];
		[(NSMutableDictionary *)_relationshipValueChanges[[self syncUUID]] setObject:[NSNull null] forKey:[syncChange relationshipName]];
		[_changesLock unlock];
		return;
	}
	
	/** We need to fetch this object. Since all synchable objects are subclasses
	 * of XUManagedObject, we can look for XUManagedObject with such sync ID.
	 */
	NSString *entityName = [syncChange valueEntityName];
	id value;
	if (entityName == nil) {
		// This shouldn't happen - should be handled above.
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"-[XUManagedObject _applyToOneRelationshipSyncChange:] - targetUUID != nil and entityName == nil!" userInfo:nil];
	}else{
		NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
		[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"ticdsSyncID == %@", targetUUID]];
		
		NSError *err;
		NSArray *items = [[self managedObjectContext] executeFetchRequest:fetchRequest error:&err];
		if ([items count] != 1){
			NSLog(@"Cannot find object with syncID %@ - should be set for relationship %@", targetUUID, [syncChange relationshipName]);
			return;
		}
		value = [items firstObject];
	}
	
	[self setValue:value forKey:[syncChange relationshipName]];
	
	[_changesLock lock];
	NSMutableDictionary *relationshipValues = _relationshipValueChanges[[self syncUUID]];
	if (relationshipValues == nil){
		relationshipValues = [NSMutableDictionary dictionary];
		_relationshipValueChanges[[self syncUUID]] = relationshipValues;
	}
	[relationshipValues setObject:targetUUID forKey:[syncChange relationshipName]];
	[_changesLock unlock];
}

-(nonnull NSArray *)_createDeletionChanges{
	[_changesLock lock];
	
	if ([_deletionChanges containsObject:[self syncUUID]]){
		[_changesLock unlock];
		return nil;
	}
	
	[_deletionChanges addObject:[self syncUUID]];
	[_changesLock unlock];
	
	XUDeletionSyncChange *deletionSyncChange = [[XUDeletionSyncChange alloc] initWithObject:self];
	NSLog(@"Created deletion sync change for %@ [%@]", [self syncUUID], [self class]);
	
	return @[ deletionSyncChange ];
}
-(nonnull NSArray *)_createInsertionChanges{
	[_changesLock lock];
	
	if ([_insertionChanges containsObject:[self syncUUID]]){
		[_changesLock unlock];
		return @[ ];
	}
	
	[_insertionChanges addObject:[self syncUUID]];
	[_changesLock unlock];
	
	XUInsertionSyncChange *syncChange = [[XUInsertionSyncChange alloc] initWithObject:self];
	NSLog(@"Created insertion sync change for %@ [%@]", [self syncUUID], [self class]);
	
	return [[self _createRelationshipChanges] arrayByAddingObject:syncChange];
}
-(nonnull NSArray *)_createRelationshipChangesForRelationship:(NSRelationshipDescription *)relationship{
	NSRelationshipDescription *inverseRelationship = [relationship inverseRelationship];
	if ([relationship isToMany] && inverseRelationship != nil && ![inverseRelationship isToMany]){
		// With relationships that have inverse relationships, prefer the -to-one
		// side of the relationship
		return @[ ];
	}
	
	if ([relationship isToMany] && inverseRelationship != nil && [inverseRelationship isToMany] && [[relationship name] caseInsensitiveCompare:[inverseRelationship name]] == NSOrderedDescending){
		// Both relationships (this and the inverse) are -to-many - in order, not
		// to sync both sides, just sync the relationship that is first alphabetically
		return @[ ];
	}
	
	if (![relationship isToMany] && inverseRelationship != nil && ![inverseRelationship isToMany] && [[relationship name] caseInsensitiveCompare:[inverseRelationship name]] == NSOrderedDescending){
		// Both relationships (this and the inverse) are -to-one - in order, not
		// to sync both sides, just sync the relationship that is first alphabetically
		return @[ ];
	}
	
	if ([relationship isToMany]){
		return [self _createToManyRelationshipChangesForRelationship:relationship];
	}else{
		return [self _createToOneRelationshipChangesForRelationship:relationship];
	}
}
-(nonnull NSArray *)_createRelationshipChanges{
	NSDictionary *objectRelationshipsByName = [[self entity] relationshipsByName];
	NSMutableArray *changes = [NSMutableArray arrayWithCapacity:[objectRelationshipsByName count]];
	for (NSString *relationshipName in objectRelationshipsByName) {
		[changes addObjectsFromArray:[self _createRelationshipChangesForRelationship:objectRelationshipsByName[relationshipName]]];
	}
	return changes;
}
-(nonnull NSArray *)_createToManyRelationshipChangesForRelationship:(NSRelationshipDescription *)relationship {
	NSString *relationshipName = [relationship name];
	NSSet *objects = [self valueForKey:relationshipName];
	NSSet *commitedObjects = [self committedValuesForKeys:@[ relationshipName ]][relationshipName];
	NSMutableArray *changes = [NSMutableArray arrayWithCapacity:1];
	
	NSMutableSet *addedObjects = [NSMutableSet set];
	NSMutableSet *removedObjects = [NSMutableSet set];
	for (XUManagedObject *obj in objects) {
		if (![obj isKindOfClass:[XUManagedObject class]]) {
			continue;
		}
		
		if (![commitedObjects containsObject:obj]){
			[addedObjects addObject:obj];
		}
	}
	for (XUManagedObject *obj in commitedObjects) {
		if (![obj isKindOfClass:[XUManagedObject class]]) {
			continue;
		}
		
		if (![objects containsObject:obj]){
			[removedObjects addObject:obj];
		}
	}
	
	/** We now make sure that the last values saved are non-nil. */
	[_changesLock lock];
	NSMutableDictionary *objDict = _relationshipValueChanges[[self syncUUID]];
	if (objDict == nil){
		objDict = [NSMutableDictionary dictionary];
		_relationshipValueChanges[[self syncUUID]] = objDict;
	}
	if (objDict[relationshipName] == nil){
		NSMutableSet *UUIDs = [NSMutableSet setWithCapacity:[commitedObjects count]];
		for (XUManagedObject *obj in commitedObjects){
			[UUIDs addObject:[obj syncUUID]];
		}
		objDict[relationshipName] = UUIDs;
	}
	[_changesLock unlock];
	
	
	for (XUManagedObject *obj in addedObjects){
		NSString *objUUID = [obj syncUUID];
		
		[_changesLock lock];
		NSMutableDictionary *objDict = _relationshipValueChanges[[self syncUUID]];
		
		/** We represent to-many relationships as a list of UUIDs. */
		NSMutableSet *UUIDs = objDict[relationshipName];
		if ([UUIDs containsObject:objUUID]){
			// We've already seen this change
			[_changesLock unlock];
			continue;
		}
		
		[UUIDs addObject:objUUID];
		[_changesLock unlock];
		
		XUSyncChange *syncChange = [[XUToManyRelationshipAdditionSyncChange alloc] initWithObject:self relationshipName:relationshipName andValue:obj];
		NSLog(@"Created to-many addition sync change for [%@ %@]{%@} %@ [%@]", [self class], relationshipName, [self syncUUID], [obj class], objUUID);
		
		[changes addObject:syncChange];
	}
	
	for (XUManagedObject *obj in removedObjects){
		NSString *objUUID = [obj syncUUID];
		
		[_changesLock lock];
		NSMutableDictionary *objDict = _relationshipValueChanges[[self syncUUID]];
		
		/** We represent to-many relationships as a list of UUIDs. */
		NSMutableSet *UUIDs = objDict[relationshipName];
		if (![UUIDs containsObject:objUUID]){
			// We've already seen this change, since the UUIDs do not contain this object
			[_changesLock unlock];
			continue;
		}
		
		[UUIDs removeObject:objUUID];
		[_changesLock unlock];
		
		XUSyncChange *syncChange = [[XUToManyRelationshipDeletionSyncChange alloc] initWithObject:self relationshipName:relationshipName andValue:obj];
		NSLog(@"Created to-many deletion sync change for [%@ %@]{%@} %@ [%@]", [self class], relationshipName, [self syncUUID], [obj class], objUUID);
		[changes addObject:syncChange];
	}
	
	return changes;
	
}
-(nonnull NSArray *)_createToOneRelationshipChangesForRelationship:(NSRelationshipDescription *)relationship {
	NSString *relationshipName = [relationship name];
	XUManagedObject *value = [self valueForKey:relationshipName];
	if (value != nil && ![value isKindOfClass:[XUManagedObject class]]){
		NSLog(@"Skipping sync of [%@ %@]{%@} because value isn't subclass of XUManagedObject (%@).", [self class], relationshipName, [self syncUUID], [value class]);
		return @[ ];
	}
	
	// In order to prevent an infinite loop of change syncs, we need to
	// take a look if the update is indeed from the user
	[_changesLock lock];
	NSMutableDictionary *objDict = _relationshipValueChanges[[self syncUUID]];
	if (objDict == nil){
		objDict = [NSMutableDictionary dictionary];
		_relationshipValueChanges[[self syncUUID]] = objDict;
	}
	
	id objValue = objDict[relationshipName];
	if (objValue != nil){
		// We represent nil values as NSNull
		if ((value == nil && [objValue isKindOfClass:[NSNull class]])
			|| [[value syncUUID] isEqualToString:objValue]){
			// It's the same -> unlock the lock and continue
			[_changesLock unlock];
			return @[ ];
		}
	}
	
	// Update the property value
	if (value == nil){
		objDict[relationshipName] = [NSNull null];
	}else{
		objDict[relationshipName] = [value syncUUID];
	}
	
	[_changesLock unlock];
	
	
	XUSyncChange *syncChange = [[XUToOneRelationshipSyncChange alloc] initWithObject:self relationshipName:relationshipName andValue:value];
	NSLog(@"Creating to-one relationship change on [%@ %@]{%@} -> %@{%@}", [self class], relationshipName, [self syncUUID], [value class], [value syncUUID]);
	return @[ syncChange ];
}
-(nonnull NSArray *)_createUpdateChanges{
	NSDictionary *changedValues = [self changedValues];
	NSMutableArray *changes = [NSMutableArray arrayWithCapacity:[changedValues count]];
	for (NSString *propertyName in changedValues) {
		id value = changedValues[propertyName];
		
		NSRelationshipDescription *relationship = [[self entity] relationshipsByName][propertyName];
		if (relationship != nil){
			// This is a relationship change
			[changes addObjectsFromArray:[self _createRelationshipChangesForRelationship:relationship]];
		}else{
			// This is a simple value change
			// In order to prevent an infinite loop of change syncs, we need to
			// take a look if the update is indeed from the user
			[_changesLock lock];
			NSMutableDictionary *objDict = _attributeValueChanges[[self syncUUID]];
			if (objDict == nil){
				objDict = [NSMutableDictionary dictionary];
				_attributeValueChanges[[self syncUUID]] = objDict;
			}
			
			id objValue = objDict[propertyName];
			if (objValue != nil){
				// We represent nil values as NSNull
				if ((value == nil && [objValue isKindOfClass:[NSNull class]])
					|| [value isEqual:objValue]){
					// It's the same -> unlock the lock and continue
					[_changesLock unlock];
					continue;
				}
			}
			
			// Update the property value
			if (value == nil){
				objDict[propertyName] = [NSNull null];
			}else{
				objDict[propertyName] = value;
			}
			
			[_changesLock unlock];
			
			XUAttributeSyncChange *change = [[XUAttributeSyncChange alloc] initWithObject:self attributeName:propertyName andValue:value];
			NSLog(@"Creating value change on [%@ %@]{%@}", [self class], propertyName, [self syncUUID]);
			[changes addObject:change];
		}
	}
	return changes;
}

-(void)applySyncChange:(nonnull XUSyncChange *)syncChange{
	BOOL previousValue = _isApplyingSyncChange;
	[self setIsApplyingSyncChange:YES];
	
	if ([syncChange isKindOfClass:[XUAttributeSyncChange class]]) {
		[self _applyAttributeSyncChange:(XUAttributeSyncChange *)syncChange];
		[self setIsApplyingSyncChange:previousValue];
		return;
	}
	
	if ([syncChange isKindOfClass:[XUDeletionSyncChange class]]) {
		[self _applyDeletionSyncChange:(XUDeletionSyncChange *)syncChange];
		[self setIsApplyingSyncChange:previousValue];
		return;
	}
	
	if ([syncChange isKindOfClass:[XUToManyRelationshipAdditionSyncChange class]]) {
		[self _applyToManyRelationshipAdditionSyncChange:(XUToManyRelationshipAdditionSyncChange *)syncChange];
		[self setIsApplyingSyncChange:previousValue];
		return;
	}
	
	if ([syncChange isKindOfClass:[XUToManyRelationshipDeletionSyncChange class]]) {
		[self _applyToManyRelationshipDeletionSyncChange:(XUToManyRelationshipDeletionSyncChange *)syncChange];
		[self setIsApplyingSyncChange:previousValue];
		return;
	}
	
	if ([syncChange isKindOfClass:[XUToOneRelationshipSyncChange class]]) {
		[self _applyToOneRelationshipSyncChange:(XUToOneRelationshipSyncChange *)syncChange];
		[self setIsApplyingSyncChange:previousValue];
		return;
	}
	
	// Insertion change needs to be handled by the sync engine itself since the
	// entity doesn't exist yet, hence it cannot be called on the entity
	
	NSLog(@"Trying to process unknown sync change %@", syncChange);
	@throw [NSException exceptionWithName:@"XUManagedObjectInvalidSyncChangeException" reason:@"Unknown sync change." userInfo:nil];
}
-(void)awakeFromInsert{
	[super awakeFromInsert];
	
	if (![self isBeingCreatedBySyncEngine]){
		[self awakeFromNonSyncInsert];
	}
}
-(void)awakeFromNonSyncInsert{
	// Sets a new TICDS Sync ID
	[self setTicdsSyncID:[[NSUUID UUID] UUIDString]];
}
-(nonnull NSArray *)createSyncChanges{
	if ([[self managedObjectContext] documentSyncManager] == nil) {
		NSLog(@"Skipping creating sync change for object %@ since there is no document sync manager!", self);
		return @[ ];
	}
	
	if ([self isInserted]){
		return [self _createInsertionChanges];
	}
	if ([self isUpdated]){
		return [self _createUpdateChanges];
	}
	if ([self isDeleted]){
		return [self _createDeletionChanges];
	}
	
	return @[ ];
}
-(XUDocumentSyncManager *)documentSyncManager{
	return [[self managedObjectContext] documentSyncManager];
}
-(instancetype)initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context{
	return [self initWithEntity:entity insertIntoManagedObjectContext:context asResultOfSyncAction:NO];
}
-(nonnull instancetype)initWithEntity:(nonnull NSEntityDescription *)entity insertIntoManagedObjectContext:(nullable NSManagedObjectContext *)context asResultOfSyncAction:(BOOL)isSync{
	// We cannot assign _isBeingCreatedBySyncEngine = sync, since CoreData
	// re-allocates the object as an instance of a generated subclass,
	// which hence loses the data. The new instance also has a different
	// address.
	[_initializationLock lock];
	
	if (_currentInitInitiatedInSync) {
		[_initializationLock unlock];
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Nested object creation within synchronization - this is likely caused by you inserting new entities into MOC from -awakeFromInsert. Use -awakeFromNonSyncInsert instead." userInfo:nil];
	}
	
	_currentInitInitiatedInSync = isSync;
	[_initializationLock unlock];
	
	@try {
		self = [super initWithEntity:entity insertIntoManagedObjectContext:context];
	}
	@finally{
		[_initializationLock lock];
		_currentInitInitiatedInSync = NO;
		[_initializationLock unlock];
	}
	return self;
}
-(BOOL)isBeingCreatedBySyncEngine{
	return _currentInitInitiatedInSync;
}
-(NSString * __nonnull)syncUUID{
	return [self ticdsSyncID];
}

@end


@implementation TICDSSynchronizedManagedObject
@end
