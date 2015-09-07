# XUSync

## What is XUSync

Simply said, XUSync is a simple-to-use, lightweight CoreData sync framework. Sync over iCloud to be precise - but other sync options should be fairly easy to add.

## Why XUSync?

Sure, there are existing solutions - but have you actually tried using them?

- Apple's iCloud documents - whoa, are you crazy? Just iOS, hence no OS X support. Also very buggy.
- TICDS - https://github.com/nothirst/TICoreDataSync - fairly nice (main inspiration taken from there), but has a lot of issues, branch with iCloud sync is still considered experimental, users have been reporting some data not syncing through, unnecessarily complicated, spawns way too many threads, etc, etc.
- other libraries - mostly not working at all, or not well

## Limitations

As I mentioned, the framework is meant to be lightweight. It should be easy to use, not a lot of setting things up. This comes with some limitations:

- to prevent race conditions and so on, all the syncing stuff happens on the main thread. It usually shouldn't be a big deal unless there is a lot of changes. But this shouldn't be the regular scenario.
- it's document-based, i.e. you always need to have something that's called a document in the framework. If you're dealing with a simple CoreData database, just consider it a single document with a fixed ID.

## How to use?

### XUApplicationSyncManager

This class handles discovering and downloading documents from the iCloud. To begin, instantiate this class with a name of your iCloud store and a delegate. The name of the iCloud store can be anything, usually the name of your app, though. This naming thing allows you to have multiple separate databases, all syncing over iCloud.

The delegate should only have one method implemented:

```
-(void)applicationSyncManager:(nonnull XUApplicationSyncManager *)manager didFindNewDocumentWithID:(nonnull NSString *)documentID;
```

You can check against deleted/hidden documents and ignore this, or call

```
-(void)downloadDocumentWithID:(nonnull NSString *)documentID toURL:(nonnull NSURL *)fileURL withCompletionHandler:(nonnull void(^)(BOOL success, NSURL * __nullable documentURL, NSError * __nullable error))completionHandler;
```

This will download the document to specific fileURL and you will be notified how it went via the `completionHandler` - always on the main thread.

### XUDocumentSyncManager

Once you're done with the app sync manager, you need to create an instance of `XUDocumentSyncManager` for each document (or just one in case of a single-document app).

```
-(nonnull instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)managedObjectContext applicationSyncManager:(nonnull XUApplicationSyncManager *)appSyncManager andUUID:(nonnull NSString *)UUID;
```

Pass in the MOC, that you want to sync, the `appSyncManager` that this document sync manager should be owned by and a UUID of the document (unique per document).

The document sync manager will sync periodically (or you can force the sync via a method); and it will automatically create sync changes when your MOC gets to be saved.

That's it! Almost.

### XUManagedDocument

In order for this to work, you need to base all your classes with `XUManagedObject`. The framework also includes a `TICDSSynchronizedManagedObject` for compatibility with TICDS. Due to backward compatibility with TICDS, your data model's root classes must always include the `ticdsSyncID` attribute, instead of the `syncUUID` which is exposed via the header file.

Due to how things work, it is absolutely forbidden to implement anything in `-awakeFromInsert`. Use `XUManagedObject`'s `-awakeFromNonSyncInsert` - see `XUManagedObject.h` for more info.


## Summarization:

- in your data model, each root class must include the `ticdsSyncID` attribute (String)
- all your CoreData classes must inherit from `XUManagedObject`
- never create anything in `-awakeFromInsert`. Use `XUManagedObject`'s `-awakeFromNonSyncInsert` - see `XUManagedObject.h` for more info.
- create app sync manager
- crete doc sync manager per document

Unlike TICDS, you don't need to include any data models, since it's all included in the framework.
