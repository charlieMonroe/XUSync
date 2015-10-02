//
//  XUApplicationSyncManager.m
//  XUSyncEngine
//
//  Created by Charlie Monroe on 8/25/15.
//  Copyright (c) 2015 Charlie Monroe Software. All rights reserved.
//

#import "XUApplicationSyncManager.h"
#import "XUDocumentSyncManager.h"


static inline void _XULogFileAtURL(NSURL *rootURL, NSURL *fileURL, NSUInteger level) {
	for (NSUInteger i = 0; i < level; ++i){
		printf("|\t");
	}
	// Just print relative path
	NSString *path = [fileURL lastPathComponent];
	printf("- %s\n", [path UTF8String]);
	
	// Don't care if the URL isn't a folder - file mananger will simple return
	// nothing
	for (NSURL *aURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:fileURL includingPropertiesForKeys:nil options:0 error:NULL]) {
		_XULogFileAtURL(rootURL, aURL, level + 1);
	}
	
}
static inline void _XULogUbiquityFolderContentsStartingAtURL(NSURL *rootURL) {
	if (rootURL == nil){
		printf("====================================================\n");
		printf("| Ubiquity folder == nil -> iCloud is not enabled. |\n");
		printf("====================================================\n");
		return;
	}
	
	printf("====== Printing Ubiquity Contents ======\n");
	_XULogFileAtURL(rootURL, rootURL, 0);
}


static NSString *const XUApplicationSyncManagerDownloadedDocumentIDsDefaultsKey = @"XUApplicationSyncManagerDownloadedDocumentIDs";

static NSString *const XUApplicationSyncManagerErrorDomain = @"XUApplicationSyncManagerErrorDomain";

@implementation XUApplicationSyncManager {
	/** UUIDs of documents that have been downloaded or up for download. */
	NSMutableArray *_availableDocumentUUIDs;
	
	/** Timer that checks for new documents every 30 seconds. */
	NSTimer *_documentCheckerTimer;
	
	/** UUIDs of documents that have been downloaded. */
	NSArray *_downloadedDocumentUUIDs;
	
	/** URL of the folder that contains the documents for this sync manager.
	 * The folder mustn't be created until whole store upload in order to eliminate
	 * any potential duplicates.
	 */
	NSURL *_ubiquityFolderURL;
}

@synthesize availableDocumentUUIDs = _availableDocumentUUIDs;
@synthesize ubiquityFolderURL = _ubiquityFolderURL;

-(void)_checkForNewDocuments{
	if (_ubiquityFolderURL == nil){
		return;
	}
	
	for (NSURL *fileURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_ubiquityFolderURL includingPropertiesForKeys:nil options:0 error:NULL]) {
		NSString *documentUUID = [fileURL lastPathComponent];
		if ([documentUUID isEqualToString:@".DS_Store"]) {
			continue; // Just a precaution
		}
		
		/** If the _availableDocumentUUIDs contains documentUUID, the document
		 * either has been already downloaded, or it has already been announced
		 * to the delegate.
		 */
		if ([_availableDocumentUUIDs containsObject:documentUUID]) {
			continue;
		}
		
		[_availableDocumentUUIDs addObject:documentUUID];
		[_delegate applicationSyncManager:self didFindNewDocumentWithID:documentUUID];
	}
}
-(void)_startDownloadingUbiquitousItemAtURL:(NSURL *)url{
	if (url == nil) {
		return;
	}
	
	NSNumber *directory;
	[url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
	if ([directory boolValue]){
		for (NSURL *fileURL in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:NULL]){
			[self _startDownloadingUbiquitousItemAtURL:fileURL];
		}
	}else{
		[[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:url error:NULL];
	}
}
-(void)_updateUbiquityFolderURL{
	_ubiquityFolderURL = [[[NSFileManager defaultManager] URLForUbiquityContainerIdentifier:nil] URLByAppendingPathComponent:_name];
	[self _startDownloadingUbiquitousItemAtURL:_ubiquityFolderURL];
}


-(void)downloadDocumentWithID:(nonnull NSString *)documentID toURL:(nonnull NSURL *)fileURL withCompletionHandler:(nonnull void (^)(BOOL, NSURL *, NSError * __nonnull))completionHandler{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSError *err;
		NSURL *documentURL = [XUDocumentSyncManager downloadDocumentWithID:documentID forApplicationSyncManager:self toURL:fileURL andReturnError:&err];
		dispatch_sync(dispatch_get_main_queue(), ^{
			// Remove document ID from available, since the download failed
			if (documentURL == nil){
				[_availableDocumentUUIDs removeObject:documentID];
			}
			completionHandler(documentURL != nil, documentURL, err);
		});
	});
}
-(instancetype)initWithName:(nonnull NSString *)name andDelegate:(nonnull id<XUApplicationSyncManagerDelegate>)delegate{
	if ((self = [super init]) != nil) {
		_name = name;
		_delegate = delegate;
		
		_downloadedDocumentUUIDs = [[NSUserDefaults standardUserDefaults] arrayForKey:XUApplicationSyncManagerDownloadedDocumentIDsDefaultsKey];
		if (_downloadedDocumentUUIDs == nil){
			_downloadedDocumentUUIDs = @[ ];
		}
		
		_availableDocumentUUIDs = [_downloadedDocumentUUIDs mutableCopy];
		
		[self _updateUbiquityFolderURL];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateUbiquityFolderURL) name:NSUbiquityIdentityDidChangeNotification object:nil];
		[NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(_checkForNewDocuments) userInfo:nil repeats:YES];
		
		[self _checkForNewDocuments];
		
		[self logUbiquityFolderContents];
	}
	return self;
}
-(void)logUbiquityFolderContents{
	_XULogUbiquityFolderContentsStartingAtURL([_ubiquityFolderURL URLByDeletingLastPathComponent]);
}

@end
