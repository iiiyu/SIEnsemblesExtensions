//
//  CDEDropboxCloudFileSystem.h
//
//  Created by Drew McCormack on 4/12/13.
//  Copyright (c) 2013 The Mental Faculty B.V. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Ensembles/Ensembles.h>

#if TARGET_OS_IPHONE
#import <Dropbox-iOS-SDK/DBRestClient.h>
#elif TARGET_OS_MAC
#import <Dropbox-OSX-SDK/DropboxOSX/DBRestClient.h>
#endif

@class CDEDropboxSyncCloudFileSystem;

extern NSString * const CDEDropboxSyncCloudFileSystemDidDownloadFilesNotification;
extern NSString * const CDEDropboxSyncCloudFileSystemDidMakeDownloadProgressNotification;

@protocol CDEDropboxSyncCloudFileSystemDelegate <NSObject>

- (void)linkAccountManagerForDropboxSyncCloudFileSystem:(CDEDropboxSyncCloudFileSystem *)fileSystem completion:(CDECompletionBlock)completion;

@end


@interface CDEDropboxSyncCloudFileSystem : NSObject <CDECloudFileSystem>

@property (readonly) DBAccountManager *accountManager;
@property (readwrite, weak) id <CDEDropboxSyncCloudFileSystemDelegate> delegate;
@property (atomic, readonly) unsigned long long bytesRemainingToDownload;

- (instancetype)initWithAccountManager:(DBAccountManager *)newManager;

@end
