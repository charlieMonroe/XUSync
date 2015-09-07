//
//  XUDocumentSyncManager.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/25/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class XUApplicationSyncManager, XUDocumentSyncManager;

@protocol XUDocumentSyncManagerDelegate <NSObject>

/** This method is called when the sync manager fails to save information
 * about the sync changes - this is likely pointing to a bug in XUSyncEngine,
 * but it may be a good idea to inform the user about this anyway.
 */
-(void)documentSyncManager:(nonnull XUDocumentSyncManager *)manager didFailToSaveSynchronizationContextWithError:(nonnull NSError *)error;


@optional

/** Optional method that informs the delegate that the manager has encountered
 * an error during synchronization and the error isn't fatal.
 */
-(void)documentSyncManager:(nonnull XUDocumentSyncManager *)manager didEncounterNonFatalErrorDuringSynchronization:(nonnull NSError *)error;

/** Optional method that informs the delegate that the manager has finished 
 * synchronization.
 */
-(void)documentSyncManagerDidSuccessfullyFinishSynchronization:(nonnull XUDocumentSyncManager *)manager;

@end


@interface XUDocumentSyncManager : NSObject

/** Synchronously downloads document with document ID to URL and returns error,
 * if the download wasn't successful.
 *
 * The returned NSURL points to the actual document.
 */
+(nullable NSURL *)downloadDocumentWithID:(nonnull NSString *)documentID forApplicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager toURL:(nonnull NSURL *)fileURL andReturnError:(NSError * __nullable * __nullable)error;

/** This method goes through all the whole store uploads and looks for the newest
 * whole store upload. Note that this method uses NSFileCoordinator to read the
 * metadata which is likely to block the thread for some while if the file isn't
 * downloaded yet. Hence do not call this from main thread.
 *
 * The most common usage for this is from XUApplicationSyncManager when downloading
 * a document with certain UUID.
 *
 * computerIDPtr contains the ID of the computer from which we're downloading the
 * document. Nil if not successful.
 */
+(nullable NSURL *)URLOfNewestEntireDocumentWithUUID:(nonnull NSString *)UUID forApplicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager andReturnComputerID:(NSString * __nullable * __nullable)computerIDPtr;


/** Inits the document sync manager with fileURL, appSyncManager and UUID. */
-(nonnull instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)managedObjectContext applicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager andUUID:(nonnull NSString *)UUID;

/** Starts synchronization with other devices. */
-(void)startSynchronizingWithCompletionHandler:(nonnull void(^)(BOOL success, NSError * __nullable error))completionHandler;

/** Uploads the entire document to the cloud. */
-(void)uploadEntireDocumentFromURL:(nonnull NSURL *)fileURL withCompletionHandler:(nonnull void(^)(BOOL success, NSError * __nullable error))completionHandler;


/** The app sync manager this document is tied to. This connection is required 
 * since we need to know where to put the sync data.
 */
@property (readonly, strong, nonnull, nonatomic) XUApplicationSyncManager *applicationSyncManager;

/** Delegate. */
@property (readwrite, weak, nullable, nonatomic) id<XUDocumentSyncManagerDelegate> delegate;

/** URL of the folder designated for sync data for this particular device. */
//@property (readonly, strong, nullable, nonatomic) NSURL *deviceSpecificUbiquityFolderURL;

/** URL of the folder designated for sync data. */
//@property (readonly, strong, nullable, nonatomic) NSURL *documentUbiquityFolderURL;

/** URL of the folder designated for storing the entire document on iCloud. */
//@property (readonly, strong, nullable, nonatomic) NSURL *entireDocumentUbiquityFolderURL;

/** Main object context that was passed in the initializer. */
@property (readonly, strong, nonnull, nonatomic) NSManagedObjectContext *managedObjectContext;

/** MOC used for sync changes. */
@property (readonly, strong, nonnull, nonatomic) NSManagedObjectContext *syncManagedObjectContext;

/** UUID of the document. */
@property (readonly, strong, nonnull, nonatomic) NSString *UUID;

@end


@interface NSManagedObjectContext (XUSync)

/** Sync manager. */
@property (readwrite, weak, nullable, nonatomic) XUDocumentSyncManager *documentSyncManager;

@end


