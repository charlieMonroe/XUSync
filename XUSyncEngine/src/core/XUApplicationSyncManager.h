//
//  XUApplicationSyncManager.h
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/25/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import <Foundation/Foundation.h>

@class XUApplicationSyncManager;

@protocol XUApplicationSyncManagerDelegate <NSObject>

/** Called when the manager found a new document. It might not be downloaded yet. */
-(void)applicationSyncManager:(nonnull XUApplicationSyncManager *)manager didFindNewDocumentWithID:(nonnull NSString *)documentID;

@end


@interface XUApplicationSyncManager : NSObject

/** Downloads or copies document with ID to URL and calls completion handler
 * upon completion. The handler is always called on the main thread.
 *
 * The documentURL within the response is nonnull upon success and contains a URL
 * to the document file.
 */
-(void)downloadDocumentWithID:(nonnull NSString *)documentID toURL:(nonnull NSURL *)fileURL withCompletionHandler:(nonnull void(^)(BOOL success, NSURL * __nullable documentURL, NSError * __nullable error))completionHandler;

/** Debugging method that logs all contents on the folder at ubiquityFolderURL. */
-(void)logUbiquityFolderContents;

/** Designated initialized. Name should be e.g. name of the app. */
-(nonnull instancetype)initWithName:(nonnull NSString *)name andDelegate:(nonnull id<XUApplicationSyncManagerDelegate>)delegate;


/** An array of UUIDs that are available. */
@property (readonly, nonnull, nonatomic) NSArray *availableDocumentUUIDs;

/** Delegate of the app sync manager. */
@property (readonly, weak, nullable, nonatomic) id<XUApplicationSyncManagerDelegate> delegate;

/** Name of the app, usually. Whatever passed in -initWithName:. */
@property (readonly, strong, nonnull, nonatomic) NSString *name;

/** URL of the folder that's designated for sync data for this manager. */
@property (readonly, strong, nullable, nonatomic) NSURL *ubiquityFolderURL;

@end
