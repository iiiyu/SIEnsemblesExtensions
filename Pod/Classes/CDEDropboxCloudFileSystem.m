//
//  CDEDropboxCloudFileSystem.m
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import "CDEDropboxCloudFileSystem.h"

#if TARGET_OS_IPHONE
#import <Dropbox-iOS-SDK/DBMetadata.h>
#import <Dropbox-iOS-SDK/DBRestClient.h>
#elif TARGET_OS_MAC
#import <Dropbox-OSX-SDK/DropboxOSX/DBMetadata.h>
#import <Dropbox-OSX-SDK/DropboxOSX/DBRestClient.h>
#endif

NSString * const CDEDropboxSyncCloudFileSystemDidDownloadFilesNotification = @"CDEDropboxSyncCloudFileSystemDidDownloadFilesNotification";
NSString * const CDEDropboxSyncCloudFileSystemDidMakeDownloadProgressNotification = @"CDEDropboxSyncCloudFileSystemDidMakeDownloadProgressNotification";


@interface CDEDropboxSyncCloudFileSystem ()

@property (atomic, readwrite) unsigned long long bytesRemainingToDownload;

@end


@implementation CDEDropboxSyncCloudFileSystem {
  DBFilesystem *filesystem;
  NSOperationQueue *operationQueue;
  BOOL updatingBytes;
}

@synthesize accountManager;

- (instancetype)initWithAccountManager:(DBAccountManager *)newManager
{
  self = [super init];
  if (self) {
    accountManager = newManager;
    [DBAccountManager setSharedManager:newManager];
    filesystem = [DBFilesystem sharedFilesystem];
    operationQueue = [[NSOperationQueue alloc] init];
    operationQueue.maxConcurrentOperationCount = 1;
    [self updateFilesystem];
  }
  return self;
}

- (void)dealloc
{
  [self.class cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireDownloadNotification) object:nil];
  if (filesystem) [filesystem removeObserver:self];
  [operationQueue cancelAllOperations];
}

#pragma mark Connecting

- (BOOL)isConnected
{
  return self.accountManager.linkedAccount != nil;
}

- (void)connect:(CDECompletionBlock)completion
{
  filesystem = nil;

  CDECompletionBlock block = ^(NSError *error) {
    [self updateFilesystem];
    [self dispatchCompletion:completion withError:error];
  };

  if (self.isConnected) {
    if (block) block(nil);
  }
  else if ([self.delegate respondsToSelector:@selector(linkAccountManagerForDropboxSyncCloudFileSystem:completion:)]) {
    [self.delegate linkAccountManagerForDropboxSyncCloudFileSystem:self completion:block];
  }
  else {
    NSError *error = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeConnectionError userInfo:nil];
    if (block) block(error);
  }
}

#pragma mark User Identity

- (void)fetchUserIdentityWithCompletion:(CDEFetchUserIdentityCallback)completion
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (completion) completion(self.accountManager.linkedAccount.userId, nil);
  });
}

#pragma mark File System

- (void)updateFilesystem
{
  if (accountManager.linkedAccount) {
    if (accountManager.linkedAccount != filesystem.account) {
      __weak typeof(self) weakSelf = self;
      filesystem = [[DBFilesystem alloc] initWithAccount:accountManager.linkedAccount];
      [filesystem addObserver:self forPathAndDescendants:[DBPath root] block:^{
        typeof (self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf updateBytesRemainingToDownload];
        if (strongSelf.bytesRemainingToDownload > 0) [strongSelf scheduleDownloadNotification];
      }];
    }
  }
  else {
    if (filesystem) [filesystem removeObserver:self];
    filesystem = nil;
  }
}

- (void)updateBytesRemainingToDownload
{
  [self.class cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateBytesRemainingToDownload) object:nil];

  if (updatingBytes) return;
  updatingBytes = YES;

  [operationQueue addOperationWithBlock:^{
    @try {
      unsigned long long count = [self bytesRemainingToDownloadInPath:[DBPath root]];
      [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        self.bytesRemainingToDownload = count;
        [[NSNotificationCenter defaultCenter] postNotificationName:CDEDropboxSyncCloudFileSystemDidMakeDownloadProgressNotification object:self];
        if (count > 0) {
          [self performSelector:@selector(updateBytesRemainingToDownload) withObject:nil afterDelay:10.0];
        }
        updatingBytes = NO;
      }];
    }
    @catch ( NSException *exception ) {}
  }];
}

- (unsigned long long)bytesRemainingToDownloadInPath:(DBPath *)path
{
  DBError *error = nil;
  DBFileInfo *info = [filesystem fileInfoForPath:path error:&error];
  if (!info) {
    CDELog(CDELoggingLevelError, @"Failed to get file info in Dropbox: %@", error);
    return 0;
  }

  if (!info.isFolder) {
    unsigned long long toDownload = 0;
    NSError *error = nil;
    DBFile *file = [filesystem openFile:path error:&error];
    if (!file)
      CDELog(CDELoggingLevelError, @"Couldn't open file: %@", file);
      else {
        toDownload = file.status.cached ? 0 : info.size;
        [file close];
      }
      return toDownload;
    }

    NSArray *children = [filesystem listFolder:path error:&error];
    if (!children) {
      CDELog(CDELoggingLevelError, @"Failed to list Dropbox folder: %@", error);
      return 0;
    }

    unsigned long long bytes = 0;
    for (DBFileInfo *child in children) {
      bytes += [self bytesRemainingToDownloadInPath:child.path];
    }

    return bytes;
  }

  #pragma mark Notifications

  - (void)scheduleDownloadNotification
  {
    [self.class cancelPreviousPerformRequestsWithTarget:self selector:@selector(fireDownloadNotification) object:nil];
    [self performSelector:@selector(fireDownloadNotification) withObject:nil afterDelay:5.0];

    [self updateBytesRemainingToDownload];
  }

  - (void)fireDownloadNotification
  {
    if (filesystem.status.download.inProgress) {
      [self scheduleDownloadNotification];
      return;
    }

    self.bytesRemainingToDownload = 0;
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEDropboxSyncCloudFileSystemDidMakeDownloadProgressNotification object:self];
    [[NSNotificationCenter defaultCenter] postNotificationName:CDEDropboxSyncCloudFileSystemDidDownloadFilesNotification object:self];
  }

  #pragma mark File Methods

  - (void)fileExistsAtPath:(NSString *)path completion:(CDEFileExistenceCallback)completion
  {
    DBError *error = nil;
    DBPath *root = [DBPath root];
    DBPath *dropboxPath = [root childPath:path];
    DBFileInfo *info = [filesystem fileInfoForPath:dropboxPath error:&error];
    if (info) {
      // Exists
      if (completion) completion(YES, info.isFolder, nil);
    }
    else if (!info && error.code == DBErrorNotFound) {
      // Doesn't exist
      if (completion) completion(NO, NO, nil);
    }
    else {
      // Error
      if (completion) completion(NO, NO, error);
    }
  }

  - (void)contentsOfDirectoryAtPath:(NSString *)path completion:(CDEDirectoryContentsCallback)completion
  {
    DBError *error = nil;
    DBPath *dropboxPath = [[DBPath root] childPath:path];
    NSArray *children = [filesystem listFolder:dropboxPath error:&error];

    if (children) {
      NSMutableArray *contents = [[NSMutableArray alloc] init];
      for (DBFileInfo *child in children) {
        NSString *name = child.path.name;
        if ([name rangeOfString:@")"].location != NSNotFound) continue;

        if (child.isFolder) {
          CDECloudDirectory *dir = [CDECloudDirectory new];
          dir.name = child.path.name;
          dir.path = child.path.stringValue;
          [contents addObject:dir];
        }
        else {
          CDECloudFile *file = [CDECloudFile new];
          file.name = child.path.name;
          file.path = child.path.stringValue;
          file.size = child.size;
          [contents addObject:file];
        }
      }

      if (completion) completion(contents, nil);
    }
    else {
      if (completion) completion(nil, error);
    }
  }

  - (void)createDirectoryAtPath:(NSString *)path completion:(CDECompletionBlock)completion
  {
    DBError *error = nil;
    DBPath *dropboxPath = [[DBPath root] childPath:path];
    BOOL success = [filesystem createFolder:dropboxPath error:&error];
    if (completion) completion(success ? nil : error);
  }

  - (void)removeItemAtPath:(NSString *)path completion:(CDECompletionBlock)completion
  {
    DBError *error = nil;
    DBPath *dropboxPath = [[DBPath root] childPath:path];
    BOOL success = [filesystem deletePath:dropboxPath error:&error];
    [self dispatchCompletion:completion withError:success ? nil : error];
  }

  - (void)uploadLocalFile:(NSString *)fromPath toPath:(NSString *)toPath completion:(CDECompletionBlock)completion
  {
    [operationQueue addOperationWithBlock:^{
      DBError *error = nil;
      DBPath *dropboxPath = [[DBPath root] childPath:toPath];
      DBFile *file = [filesystem createFile:dropboxPath error:&error];
      if (!file) {
        [self dispatchCompletion:completion withError:error];
        return;
      }

      BOOL success = [file writeContentsOfFile:fromPath shouldSteal:NO error:&error];
      [file close];

      [self dispatchCompletion:completion withError:success ? nil : error];
    }];
  }

  - (void)downloadFromPath:(NSString *)fromPath toLocalFile:(NSString *)toPath completion:(CDECompletionBlock)completion
  {
    [operationQueue addOperationWithBlock:^{
      DBError *error = nil;
      DBPath *dropboxPath = [[DBPath root] childPath:fromPath];
      DBFile *file = [filesystem openFile:dropboxPath error:&error];
      if (!file) {
        [self dispatchCompletion:completion withError:error];
        return;
      }

      NSData *data = [file readData:&error];
      if (!data) {
        [file close];
        [self dispatchCompletion:completion withError:error];
        return;
      }

      NSError *writeError = nil;
      BOOL success = [data writeToFile:toPath atomically:YES];
      if (!success) {
        NSDictionary *info = @{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Could not write file at path: %@", toPath]};
        writeError = [NSError errorWithDomain:CDEErrorDomain code:CDEErrorCodeFileAccessFailed userInfo:info];
      }
      [file close];

      [self dispatchCompletion:completion withError:writeError];
    }];
  }

  - (void)dispatchCompletion:(CDECompletionBlock)completion withError:(NSError *)error
  {
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
      if (completion) completion(error);
    }];
  }

@end
