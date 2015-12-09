//
//  XUDocumentSyncManager.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/25/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUDocumentSyncManager.h"

@import ObjectiveC;

#if TARGET_OS_IPHONE
	@import UIKit;
#endif

#import "XUApplicationSyncManager.h"
#import "XUManagedObject.h"

#import "XUInsertionSyncChange.h"
#import "XUSyncChange.h"
#import "XUSyncChangeSet.h"

#import <CommonCrypto/CommonCrypto.h>

#if !TARGET_OS_IPHONE
	#import <IOKit/IOKitLib.h>
#else
	// For UIDevice
	#import <UIKit/UIKit.h>
#endif

static NSString *const XUDocumentSyncManagerErrorDomain = @"XUDocumentSyncManagerErrorDomain";

static NSString *const XUDocumentLastUploadDateKey = @"XUDocumentLastUploadDate";
static NSString *const XUDocumentLastSyncChangeSetTimestampKey = @"XUDocumentLastSyncChangeSetTimestamp";
static NSString *const XUDocumentNameKey = @"XUDocumentName";

static NSString *const XUDocumentLastProcessedChangeSetKey = @"XUDocumentLastProcessedChangeSet";

@implementation XUDocumentSyncManager {
	/** Lock used for ensuring that only one synchronization is done at once. */
	NSLock *_synchronizationLock;
	
	/** Model used in -syncManagedObjectContext. */
	NSManagedObjectModel *_syncModel;
	
	/** Persistent store coordinator used in -syncManagedObjectContext. */
	NSPersistentStoreCoordinator *_syncStoreCoordinator;
	
	#if TARGET_OS_IPHONE
		/** Background task while syncing. */
		UIBackgroundTaskIdentifier _syncBackgroundTaskIdentifier;
	#endif
	
	struct {
		BOOL _isSyncing : 1;
		BOOL _isUploadingEntireDocument : 1;
	} _flags;
}

+(NSString *)_calculateMD5HashOfString:(NSString *)string{
	const char *cstr = [string UTF8String];
	unsigned char result[16];
	CC_MD5(cstr, (CC_LONG)strlen(cstr), result);
	
	return [NSString stringWithFormat:
				@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
					result[0], result[1], result[2], result[3],
					result[4], result[5], result[6], result[7],
					result[8], result[9], result[10], result[11],
					result[12], result[13], result[14], result[15]
			];
}

/** A convenience macro for getting the device ID. */
#define XU_DEVICE_ID() ([XUDocumentSyncManager _deviceIdentifier])
 
/** Returns a unique identifier for this device/user combo. */
+(NSString *)_deviceIdentifier{
	#if TARGET_OS_IPHONE
		return [[[UIDevice currentDevice] identifierForVendor] UUIDString];
	#else
		static NSString *_cachedID = nil;
		if (_cachedID != nil){
			return _cachedID;
		}
	
		io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
		CFStringRef serialNumberAsCFString = NULL;
		if (platformExpert != 0) {
			serialNumberAsCFString = IORegistryEntryCreateCFProperty(platformExpert, CFSTR(kIOPlatformSerialNumberKey), kCFAllocatorDefault, 0);
			IOObjectRelease(platformExpert);
		}
		
		NSString *serialNumberAsNSString = nil;
		if (serialNumberAsCFString != NULL) {
			serialNumberAsNSString = (NSString *)CFBridgingRelease(serialNumberAsCFString);
		}
	
		// Put in the user salt as well - we may have two users on the same computer
		NSString *computerID = [self _calculateMD5HashOfString:[serialNumberAsNSString stringByAppendingString:NSUserName()]];
		return (_cachedID = computerID);
	#endif
}

/** Returns the device specific ubiquity folder for the document - SYNC_ROOT/DOC_UUID/DEV_UUID. */
+(NSURL *)_deviceSpecificUbiquityFolderURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _documentUbiquityFolderURLForSyncManager:syncManager andDocumentUUID:UUID] URLByAppendingPathComponent:computerID];
}
/** Returns the document ubiquity folder - SYNC_ROOT/DOC_UUID. */
+(NSURL *)_documentUbiquityFolderURLForSyncManager:(XUApplicationSyncManager *)syncManager andDocumentUUID:(NSString *)UUID{
	return [[syncManager ubiquityFolderURL] URLByAppendingPathComponent:UUID];
}
/** Returns the Info.plist for particular document's whole store - SYNC_ROOT/DOC_UUID/DEV_UUID/whole_store/Info.plist. */
+(NSURL *)_entireDocumentInfoFileURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _entireDocumentUbiquityFolderURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:@"Info.plist"];
}
/** Returns the store for the dev's doc whole-upload store folder - SYNC_ROOT/DOC_UUID/DEV_UUID/whole_store. */
+(NSURL *)_entireDocumentUbiquityFolderURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _deviceSpecificUbiquityFolderURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:@"whole_store"];
}
/** Returns the URL of the Info.plist that contains information about last timestamp
 * read by this computer. - SYNC_ROOT/DOC_UUID/DEV_UUID/sync_store/stamps/THIS_DEV_UUID.plist. */
+(NSURL *)_persistentSyncStorageInfoURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _timestampsDirectoryURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", [self _deviceIdentifier]]];
}
/** Returns the URL of folder where the document sync manager keeps its sync data. - SYNC_ROOT/DOC_UUID/DEV_UUID/sync_store. */
+(NSURL *)_persistentSyncStorageFolderURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _deviceSpecificUbiquityFolderURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:@"sync_store"];
}
/** Returns the URL of the actual SQL databse where sync manager keeps its sync data. - SYNC_ROOT/DOC_UUID/DEV_UUID/sync_store/persistent_store.sql. */
+(NSURL *)_persistentSyncStorageURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _persistentSyncStorageFolderURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:@"persistent_store.sql"];
}
/** Returns the URL of the folder that contains information about last timestamp
 * read by computers. - SYNC_ROOT/DOC_UUID/DEV_UUID/sync_store/stamps. */
+(NSURL *)_timestampsDirectoryURLForSyncManager:(XUApplicationSyncManager *)syncManager computerID:(NSString *)computerID andDocumentUUID:(NSString *)UUID{
	return [[self _persistentSyncStorageFolderURLForSyncManager:syncManager computerID:computerID andDocumentUUID:UUID] URLByAppendingPathComponent:@"stamps"];
}

+(nullable NSURL *)downloadDocumentWithID:(nonnull NSString *)documentID forApplicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager toURL:(nonnull NSURL *)fileURL andReturnError:(NSError *__autoreleasing  __nullable * __nullable)error{
	NSString *computerID = nil;
	NSURL *accountURL = [XUDocumentSyncManager URLOfNewestEntireDocumentWithUUID:documentID forApplicationSyncManager:appSyncManager andReturnComputerID:&computerID];
	if (accountURL == nil || computerID == nil){
		NSLog(@"Document sync manager was unable to find whole-store upload for document with ID %@", documentID);
		
		*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
					NSLocalizedFailureReasonErrorKey : NSLocalizedString(@"Cannot find such document. Check back later, it might not have synced through.", @"")
				}];
		return nil;
	}
	
	
	
	__block NSURL *documentURL;
	
	NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
	[coordinator coordinateReadingItemAtURL:accountURL options:NSFileCoordinatorReadingWithoutChanges error:error byAccessor:^(NSURL *newURL) {
		NSURL *infoFileURL = [[accountURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"Info.plist"];
		NSDictionary *accountDict = [NSDictionary dictionaryWithContentsOfURL:infoFileURL];
		if (accountDict == nil) {
			*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
					NSLocalizedFailureReasonErrorKey : NSLocalizedString(@"Cannot open document metadata file.", @"")
				}];
			return;
		}
		
		NSString *documentName = accountDict[XUDocumentNameKey];
		if (documentName == nil) {
			*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
					NSLocalizedFailureReasonErrorKey : NSLocalizedString(@"Metadata file doesn't contain required information.", @"")
				}];
			return;
		}
		
		NSURL *remoteDocumentURL = [accountURL URLByAppendingPathComponent:documentName];
		NSURL *localDocumentURL = [fileURL URLByAppendingPathComponent:documentName];
		if ([[NSFileManager defaultManager] copyItemAtURL:remoteDocumentURL toURL:localDocumentURL error:error]) {
			documentURL = localDocumentURL;
			
			// We need to copy the sync timestamp
			NSURL *syncInfoURL = [self _persistentSyncStorageInfoURLForSyncManager:appSyncManager computerID:computerID andDocumentUUID:documentID];
			[[NSFileManager defaultManager] createDirectoryAtURL:[syncInfoURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
			
			NSTimeInterval timeStamp = [accountDict[XUDocumentLastUploadDateKey] doubleValue];
			NSDictionary *syncInfoDict = @{
					   XUDocumentLastProcessedChangeSetKey: @(timeStamp)
				   };
			[syncInfoDict writeToURL:syncInfoURL atomically:YES];
		}
	}];
	
	return documentURL;
}

+(nullable NSURL *)URLOfNewestEntireDocumentWithUUID:(nonnull NSString *)UUID forApplicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager andReturnComputerID:(NSString * __nullable * __nullable)computerIDPtr{
	NSURL *folderURL = [self _documentUbiquityFolderURLForSyncManager:appSyncManager andDocumentUUID:UUID];
	NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
	__block NSURL *newestURL = nil;
	__block NSDate *newestDate = nil;
	__block NSString *newestComputerID = nil;
	[coordinator coordinateReadingItemAtURL:folderURL options:NSFileCoordinatorReadingWithoutChanges error:nil byAccessor:^(NSURL *newURL) {
		for (NSURL *computerURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:newURL includingPropertiesForKeys:nil options:0 error:nil]) {
			NSString *computerID = [computerURL lastPathComponent];
			if ([computerID isEqualToString:@".DS_Store"]){
				continue;
			}
			
			NSURL *wholeStoreURL = [computerURL URLByAppendingPathComponent:@"whole_store"];
			NSURL *infoFileURL = [wholeStoreURL URLByAppendingPathComponent:@"Info.plist"];
			NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:infoFileURL];
			if (dict == nil){
				[[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:infoFileURL error:nil];
				continue;
			}
			
			NSDate *fileDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[dict[XUDocumentLastUploadDateKey] doubleValue]];
			if (fileDate == nil){
				continue;
			}
			
			if (newestDate == nil || [fileDate compare:newestDate] == NSOrderedDescending){
				newestDate = fileDate;
				newestURL = [wholeStoreURL URLByAppendingPathComponent:@"Document"];
				
				newestComputerID = computerID;
			}
		}
	}];
	
	if (computerIDPtr != NULL){
		*computerIDPtr = newestComputerID;
	}
	
	return newestURL;
}

/** Applies changes from changeSet and returns error. 
 *
 * objCache is a mutable dictionary with UUID -> obj mapping that is kept during
 * the sync, so that we don't have to perform fetches unless necessary.
 */
-(BOOL)_applyChangeSet:(XUSyncChangeSet *)changeSet withObjectCache:(NSMutableDictionary *)objCache andReturnError:(NSError **)error{
	NSArray *changes = [[changeSet changes] allObjects];
	
	// We need to apply insertion changes first since other changes may include
	// relationship changes, which include these entities
	NSPredicate *insertionPredicate = [NSPredicate predicateWithBlock:^BOOL(XUSyncChange *change, NSDictionary *bindings) {
		return [change isKindOfClass:[XUInsertionSyncChange class]];
	}];
	NSArray *insertionChanges = [changes filteredArrayUsingPredicate:insertionPredicate];
	for (XUInsertionSyncChange *change in insertionChanges) {
		NSEntityDescription *entityDescription = [NSEntityDescription entityForName:[change insertedEntityName] inManagedObjectContext:[self managedObjectContext]];
		if (entityDescription == nil){
			*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
							 NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"Cannot find entity named %@", @""), [change insertedEntityName]]
					 }];
			return NO; // This is a fatal error
		}
		
		Class cl = NSClassFromString([entityDescription managedObjectClassName]);
		if (cl == Nil) {
			*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
							 NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"Cannot find class named %@", @""), [entityDescription managedObjectClassName]]
					 }];
			return NO; // This is a fatal error
		}
		
		XUManagedObject *obj;
		NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[change objectEntityName]];
		[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"ticdsSyncID == %@", [change objectSyncID]]];
		obj = [[_managedObjectContext executeFetchRequest:fetchRequest error:nil] firstObject];
		if (obj != nil) {
			NSLog(@"-[XUDocumentSyncManager _applyChangeSet:withObjectCache:andReturnError:] - object with ID %@ already exists!", [obj syncUUID]);
			continue;
		}
		
		obj = [(XUManagedObject *)[cl alloc] initWithEntity:entityDescription insertIntoManagedObjectContext:_managedObjectContext asResultOfSyncAction:YES];
		NSDictionary *attributes = [change attributes];
		for (NSString *key in attributes){
			id value = attributes[key];
			[obj setValue:value forKey:key];
		}
		
		// TODO - should this be really an assertion?
		if ([obj syncUUID] != nil){
			[XUManagedObject noticeSyncInsertionOfObjectWithID:[obj syncUUID]];
			objCache[[obj syncUUID]] = obj;
		}
	}
	
	// Done with insertion - now get the remaining changes and apply them
	NSMutableArray *otherChanges = [changes mutableCopy];
	[otherChanges removeObjectsInArray:insertionChanges];
	for (XUSyncChange *change in otherChanges) {
		XUManagedObject *obj = objCache[[change objectSyncID]];
		if (obj == nil) {
			NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[change objectEntityName]];
			[fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"ticdsSyncID == %@", [change objectSyncID]]];
			obj = [[_managedObjectContext executeFetchRequest:fetchRequest error:nil] firstObject];
		}
		
		if (obj == nil){
			*error = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
							 NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"Cannot find entity with ID %@", @""), [change objectSyncID]]
					 }];
			return NO; // This is a fatal error?
		}
		
		[obj applySyncChange:change];
	}
	
	return YES;
}

/** This method is an observer for NSManagedObjectContextWillSaveNotification. */
-(void)_createSyncChanges:(NSNotification *)aNotif{
	if (![NSThread isMainThread]) {
		[self performSelectorOnMainThread:_cmd withObject:aNotif waitUntilDone:YES];
		return;
	}
	
	NSLog(@"%@ - managed object context will save, creating sync changes.", self);
	
	NSMutableArray *changes = [NSMutableArray array];
	for (XUManagedObject *obj in [_managedObjectContext insertedObjects]){
		[changes addObjectsFromArray:[obj createSyncChanges]];
	}
	for (XUManagedObject *obj in [_managedObjectContext updatedObjects]){
		[changes addObjectsFromArray:[obj createSyncChanges]];
	}
	for (XUManagedObject *obj in [_managedObjectContext deletedObjects]){
		[changes addObjectsFromArray:[obj createSyncChanges]];
	}
	
	if ([changes count] == 0){
		// Do not create anything.
		if ([[self delegate] respondsToSelector:@selector(documentSyncManagerDidSuccessfullyFinishSynchronization:)]) {
			[self _safelyPerformBlockOnMainThread:^{
				[[self delegate] documentSyncManagerDidSuccessfullyFinishSynchronization:self];
			}];
		}
		
		// Don't even do sync cleanup, we'll simply do it next time
		return;
	}
	
	// Create a change set.
	__unused XUSyncChangeSet *changeSet = [[XUSyncChangeSet alloc] initWithManagedObjectContext:_syncManagedObjectContext andChanges:changes];
	NSLog(@"%@ - created change set with %li changes", self, (unsigned long)[changes count]);
	
	[self _performSyncCleanup];
	
	NSError *err;
	if (![[self syncManagedObjectContext] save:&err]){
		NSLog(@"%@ - failed saving sync managed object context %@", self, err);
		[self _safelyPerformBlockOnMainThread:^{
			[[self delegate] documentSyncManager:self didFailToSaveSynchronizationContextWithError:err];
		}];
	}else{
		if ([[self delegate] respondsToSelector:@selector(documentSyncManagerDidSuccessfullyFinishSynchronization:)]) {
			[self _safelyPerformBlockOnMainThread:^{
				[[self delegate] documentSyncManagerDidSuccessfullyFinishSynchronization:self];
			}];
		}
	}
}

/** This method removes old sync changes. This is done by iterating the time stamps
 * folder and finding the lowest timestamp available. We can delete all changesets
 * before that timestamps, since all other clients have definitely seen these changes
 * already.
 *
 * If no timestamp is found, we simply have no clients so far and can delete
 * all changesets.
 */
-(void)_performSyncCleanup{
	NSURL *timestampsFolderURL = [XUDocumentSyncManager _timestampsDirectoryURLForSyncManager:_applicationSyncManager computerID:XU_DEVICE_ID() andDocumentUUID:_UUID];
	NSTimeInterval latestTimeStamp = (NSTimeInterval)CGFLOAT_MAX;
	for (NSURL *timestampURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:timestampsFolderURL includingPropertiesForKeys:nil options:0 error:NULL]) {
		if (![[timestampURL pathExtension] isEqualToString:@"plist"]) {
			continue;
		}
		
		NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:timestampURL];
		NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:[dict[XUDocumentLastProcessedChangeSetKey] doubleValue]];
		if (date == nil){
			// Ignore
			continue;
		}
		
		latestTimeStamp = MIN([date timeIntervalSinceReferenceDate], latestTimeStamp);
	}
	
	// Due to a few issues with immediately deleting the sync change sets, we're
	// keeping them for 24 hours just to be sure.
	//
	// The main issue here is the following scenario:
	//
	// 1) Device A creates a document, uploads whole store.
	// 2) Device B downloads the whole store, opens it.
	// 3) Device A in the meantime creates a new change, which is, however,
	//		immediately deleted, since there are no registered observers.
	//
	// We're trying to prevent this by immediately writing a timestamp to the
	// Device A's sync folder, but the changes may take some time to propagate.
	// So generally speaking, this is just to be safe rather than sorry.
	
	latestTimeStamp = MIN(latestTimeStamp, [NSDate timeIntervalSinceReferenceDate] - (24.0 * 3600.0));
	
	// NewerThan: 0.0 -> All of them
	NSArray *syncChangeSets = [XUSyncChangeSet allChangeSetsInManagedObjectContext:_syncManagedObjectContext withTimestampNewerThan:0.0];
	for (XUSyncChangeSet *changeSet in syncChangeSets){
		if ([changeSet timestamp] < latestTimeStamp){
			// Delete
			for (XUSyncChange *change in [changeSet changes]){
				[_syncManagedObjectContext deleteObject:change];
			}
			
			NSLog(@"[XUDocumentSyncManager _performSyncCleanup] - deleting changeSet with timestamp [%0.2f]", [changeSet timestamp]);
			[_syncManagedObjectContext deleteObject:changeSet];
		}
	}
}

/** This ensures that the block is called on main thread without locking up. */
-(void)_safelyPerformBlockOnMainThread:(void(^)(void))block{
	if ([NSThread isMainThread]){
		block();
	}else{
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

/** This method is an observer for NSManagedObjectContextWillSaveNotification.
 * We start a sync after each save.
 */
-(void)_startSync:(NSNotification *)aNotif{
	[self startSynchronizingWithCompletionHandler:^void(BOOL success, NSError * __nullable error) {
		if (success){
			NSLog(@"%@ - successfully completed synchronization.", self);
		}else{
			NSLog(@"%@ - failed synchronization with error %@.", self, error);
		}
	}];
}

/** Performs the actual synchronization. This is done by enumerating existing
 * folders representing computers that upload sync changes.
 *
 * For each computer then, a new MOC is created and the database is read as
 * read-only for performance reasons.
 *
 * All changes are then processed on main thread. (THIS IS IMPORTANT.)
 *
 */
-(BOOL)_synchronizeAndReturnError:(NSError **)err{
	__autoreleasing NSError *___err = nil;
	if (err == NULL){
		err = &___err;
	}
	
	/** This is an objectCache that allows quick object lookup by ID. We're keeping
	 * one per entire sync since it's likely that recently used items will be reused.
	 */
	NSMutableDictionary *objectCache = [NSMutableDictionary dictionary];
	NSURL *documentFolder = [XUDocumentSyncManager _documentUbiquityFolderURLForSyncManager:_applicationSyncManager andDocumentUUID:_UUID];
	for (NSURL *computerURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:documentFolder includingPropertiesForKeys:nil options:0 error:NULL]) {
		// The computerURL is a folder that contains computer-specific sync data
		
		NSString *computerID = [computerURL lastPathComponent];
		if ([computerID isEqualToString:@".DS_Store"]) {
			// Ignore DS_Store
			continue;
		}
		
		if ([computerID isEqualToString:XU_DEVICE_ID()]) {
			// Ignore our own sync data
			continue;
		}
		
		if (![self _synchronizeWithComputerWithID:computerID objectCache:objectCache andReturnError:err]){
			return NO;
		}
	}
	
	return YES;
}

/** This method syncs with data from computer with ID and returns error. If the
 * error is non-fatal, this method will still return YES. NO is returned on fatal
 * errors, e.g. when we fail to initialize a new managed object, etc.
 *
 * The minor errors are reported to the delegate.
 */
-(BOOL)_synchronizeWithComputerWithID:(NSString *)computerID objectCache:(NSMutableDictionary *)objCache andReturnError:(NSError **)error{
	NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_syncModel];
	NSURL *fileURL = [XUDocumentSyncManager _persistentSyncStorageURLForSyncManager:_applicationSyncManager computerID:computerID andDocumentUUID:_UUID];
	
	NSError *err;
	NSDictionary *options = @{
							  NSReadOnlyPersistentStoreOption : @(YES),
							  NSMigratePersistentStoresAutomaticallyOption : @(NO)
						  };
	NSPersistentStore *store = [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:fileURL options:options error:&err];
	if (store == nil){
		if ([[self delegate] respondsToSelector:@selector(documentSyncManager:didEncounterNonFatalErrorDuringSynchronization:)]) {
			[self _safelyPerformBlockOnMainThread:^{
				[[self delegate] documentSyncManager:self didEncounterNonFatalErrorDuringSynchronization:err];
			}];
		}
		
		// It's a minor error - the file might not exist, might be from future version, etc.
		return YES;
	}
	
	[ctx setPersistentStoreCoordinator:coordinator];
	
	// We need to find out which change was last seen by this computer
	NSURL *infoDictURL = [XUDocumentSyncManager _persistentSyncStorageInfoURLForSyncManager:_applicationSyncManager computerID:computerID andDocumentUUID:_UUID];
	[[NSFileManager defaultManager] createDirectoryAtURL:[infoDictURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
	
	NSDictionary *infoDict = [NSDictionary dictionaryWithContentsOfURL:infoDictURL];
	NSTimeInterval lastTimestampSeen = [(NSNumber *)infoDict[XUDocumentLastProcessedChangeSetKey] doubleValue];
	
	// If this is the first sync, lastTimestampSeen will be 0.0, hence everything
	// will be applied.
	
	NSArray *changeSets = [XUSyncChangeSet allChangeSetsInManagedObjectContext:ctx withTimestampNewerThan:lastTimestampSeen];
	if ([changeSets count] == 0){
		// A likely scenario -> bail out
		return YES;
	}
	
	__block NSError *blockError = nil;
	__block BOOL syncApplicationFailed = NO;
	dispatch_sync(dispatch_get_main_queue(), ^{
		for (XUSyncChangeSet *changeSet in changeSets){
			if (![self _applyChangeSet:changeSet withObjectCache:objCache andReturnError:&blockError]){
				// This is a igger issue
				syncApplicationFailed = YES;
				break;
			}
		}
	});
	
	*error = blockError;
	
	if (syncApplicationFailed){
		return NO;
	}
	
	// Since the array is sorted by timestamps, we can just take the last one
	NSTimeInterval maxTimestamp = [(XUSyncChangeSet *)[changeSets lastObject] timestamp];
	infoDict = @{ XUDocumentLastProcessedChangeSetKey : @(maxTimestamp) };
	
	// Since each device has its own file, we don't need to lock the file anyhow,
	// or worry about some collision issues.
	[infoDict writeToURL:infoDictURL atomically:YES];
	
	return YES;
}

-(nullable instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)managedObjectContext applicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager andUUID:(nonnull NSString *)UUID{
	if ((self = [super init]) != nil) {
		_managedObjectContext = managedObjectContext;
		[_managedObjectContext setDocumentSyncManager:self];
		
		_applicationSyncManager = appSyncManager;
		_synchronizationLock = [[NSLock alloc] init];
		_UUID = UUID;
		
		NSError *err;
		NSURL *deviceSpecificFolderURL = [XUDocumentSyncManager _deviceSpecificUbiquityFolderURLForSyncManager:_applicationSyncManager computerID:XU_DEVICE_ID() andDocumentUUID:_UUID];
		if (deviceSpecificFolderURL != nil){
			if (![[NSFileManager defaultManager] createDirectoryAtURL:deviceSpecificFolderURL withIntermediateDirectories:YES attributes:nil error:&err]) {
				NSLog(@"%@ - failed to create device specific ubiquity folder URL %@, error %@", self, deviceSpecificFolderURL, err);
			}
		}
		
		/** We're running all syncing on the main thread. */
		_syncManagedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
		_syncModel = [NSManagedObjectModel mergedModelFromBundles:@[ [NSBundle bundleForClass:[self class]] ]];
		_syncStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_syncModel];
		
		NSURL *persistentStoreURL = [XUDocumentSyncManager _persistentSyncStorageURLForSyncManager:_applicationSyncManager computerID:XU_DEVICE_ID() andDocumentUUID:_UUID];
		if (persistentStoreURL == nil){
			return nil;
		}
		
		if (![[NSFileManager defaultManager] createDirectoryAtURL:[persistentStoreURL URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&err]){
			NSLog(@"%@ - failed to create persistent store folder URL %@, error %@", self, [persistentStoreURL URLByDeletingLastPathComponent], err);
		}
		
		NSDictionary *dict = @{
			   NSSQLitePragmasOption : @{ @"journal_mode" : @"DELETE" },
			   NSMigratePersistentStoresAutomaticallyOption : @(YES)
		   };
		if (![_syncStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:persistentStoreURL options:dict error:&err]){
			NSLog(@"%@ - failed to create persistent store URL URL %@, error %@", self, persistentStoreURL, err);
		}
		
		[_syncManagedObjectContext setPersistentStoreCoordinator:_syncStoreCoordinator];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_createSyncChanges:) name:NSManagedObjectContextWillSaveNotification object:managedObjectContext];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_startSync:) name:NSManagedObjectContextDidSaveNotification object:managedObjectContext];
	}
	return self;
}
-(void)startSynchronizingWithCompletionHandler:(nonnull void (^)(BOOL, NSError * __nullable))completionHandler{
	[_synchronizationLock lock];
	if (_flags._isSyncing) {
		// Already syncing
		[_synchronizationLock unlock];
		completionHandler(NO, [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
								  NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Synchronization is already in progress.", @"")
							  }]);
		return;
	}
	
	_flags._isSyncing = YES;
	[_synchronizationLock unlock];
	
	#if TARGET_OS_IPHONE
		_syncBackgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"XUDocumentSyncManager.Sync" expirationHandler:^{
			if (_syncBackgroundTaskIdentifier != UIBackgroundTaskInvalid) {
				// The sync hasn't finished yet. Inform the user.
				_syncBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
				
				UILocalNotification *notification = [[UILocalNotification alloc] init];
				[notification setAlertTitle:[NSString stringWithFormat:NSLocalizedString(@"%@ couldn't finish synchronization in the background.", @""), [[NSProcessInfo processInfo] processName]]];
				[notification setAlertBody:[NSString stringWithFormat:NSLocalizedString(@"Please switch back to %@ so that the synchronization can finish.", @""), [[NSProcessInfo processInfo] processName]]];
				[notification setFireDate:[[NSDate date] dateByAddingTimeInterval:1.0]];
				[[UIApplication sharedApplication] scheduleLocalNotification:notification];
			}
		}];
	#endif
	
	__weak XUDocumentSyncManager *weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSError *err = nil;
		BOOL result = [weakSelf _synchronizeAndReturnError:&err];
		
		dispatch_sync(dispatch_get_main_queue(), ^{
			#if TARGET_OS_IPHONE
				[[UIApplication sharedApplication] endBackgroundTask:_syncBackgroundTaskIdentifier];
				_syncBackgroundTaskIdentifier = UIBackgroundTaskInvalid;
			#endif
			
			completionHandler(result, err);
		});
	});
	
	_flags._isSyncing = NO;
}
-(void)uploadEntireDocumentFromURL:(nonnull NSURL *)fileURL withCompletionHandler:(nonnull void (^)(BOOL, NSError * __nullable))completionHandler{
	// The _flags._isUploadingEntireDocument flag is only changed from main thread
	// so no locks are necessary
	if (_flags._isUploadingEntireDocument){
		completionHandler(NO, [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
									  NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"An upload operation is already in progress.", @"")
							  }]);
		return;
	}
	
	_flags._isUploadingEntireDocument = YES;
	
	// We need to figure out which is last change set in our sync MOC, so that
	// we can mark the upload as including these change sets. Why? When the other
	// device downloads the whole-store, it mustn't apply any changes to it that
	// have already been included in the whole-store upload
	//
	// Since we perform all syncing on main thread, it is guaranteed that the
	// lastChangeSet will indeed be last.
	XUSyncChangeSet *lastChangeSet = [XUSyncChangeSet newestChangeSetInManagedObjectContext:_syncManagedObjectContext];
	
	// We don't care if lastChangeSet == nil, since that will simply make
	// lastChangeSetTimestamp == 0.0 which works just fine
	NSTimeInterval lastChangeSetTimestamp = [lastChangeSet timestamp];
	
	// Copy the document somewhere else, since the upload may take some time and
	// changes may be made
	NSURL *tempFolderURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtURL:tempFolderURL withIntermediateDirectories:YES attributes:nil error:NULL];
	
	NSError *fmErr;
	if (![[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[tempFolderURL URLByAppendingPathComponent:[fileURL lastPathComponent]] error:&fmErr]){
		completionHandler(NO, fmErr);
		_flags._isUploadingEntireDocument = NO;
		return;
	}
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
		__block NSError *err;
		__block BOOL success;
		NSURL *entireDocumentUbiquityFolderURL = [XUDocumentSyncManager _entireDocumentUbiquityFolderURLForSyncManager:_applicationSyncManager computerID:XU_DEVICE_ID() andDocumentUUID:_UUID];
		[coordinator coordinateWritingItemAtURL:entireDocumentUbiquityFolderURL options:NSFileCoordinatorWritingForReplacing error:&err byAccessor:^(NSURL *newURL) {
			
			NSURL *docURL = [newURL URLByAppendingPathComponent:@"Document"];
			[[NSFileManager defaultManager] createDirectoryAtURL:docURL withIntermediateDirectories:YES attributes:nil error:NULL];
			
			NSURL *targetURL = [docURL URLByAppendingPathComponent:[fileURL lastPathComponent]];
			
			// Delete the old whole-store
			[[NSFileManager defaultManager] removeItemAtURL:targetURL error:NULL];
			
			if (![[NSFileManager defaultManager] copyItemAtURL:[tempFolderURL URLByAppendingPathComponent:[fileURL lastPathComponent]] toURL:targetURL error:&err]){
				success = NO;
				return;
			}
			
			NSDictionary *documentConfig = @{
											 XUDocumentLastUploadDateKey: @([NSDate timeIntervalSinceReferenceDate]),
											 XUDocumentLastSyncChangeSetTimestampKey: @(lastChangeSetTimestamp),
											 XUDocumentNameKey: [fileURL lastPathComponent]
										 };
			
			if (![documentConfig writeToURL:[newURL URLByAppendingPathComponent:@"Info.plist"] atomically:YES]){
				success = NO;
				err = [NSError errorWithDomain:XUDocumentSyncManagerErrorDomain code:0 userInfo:@{
							  NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Could not save upload metadata.", @"")
					  }];
				return;
			}
			
			success = YES;
		}];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			completionHandler(success, err);
			_flags._isUploadingEntireDocument = NO;
		});
	});
}

@end



static NSString *const NSManagedObjectContextXUSyncManagerKey = @"NSManagedObjectContextXUSyncManager";

@implementation NSManagedObjectContext (XUSync)

-(XUDocumentSyncManager * __nullable)documentSyncManager{
	return objc_getAssociatedObject(self, &NSManagedObjectContextXUSyncManagerKey);
}
-(void)setDocumentSyncManager:(XUDocumentSyncManager * __nullable)documentSyncManager{
	objc_setAssociatedObject(self, &NSManagedObjectContextXUSyncManagerKey, documentSyncManager, OBJC_ASSOCIATION_RETAIN);
}

@end

