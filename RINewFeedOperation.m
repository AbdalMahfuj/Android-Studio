//
//  RIFeedOperation.m
//  ringID
//
//  Created by Md. Mamun-Ur-Rashid on 5/4/15.
//  Copyright (c) 2015 IPVision Canada Inc. All rights reserved.
//

#import "RINewFeedOperation.h"
#import "RIFeedManager.h"
#import "ActionManager.h"
#import "MakePacket.h"
#import "RIFriendManager.h"
#import "IDMetaTagParser.h"
#import "IDURLMetaData.h"
#import "RIFeed+Private.h"
#import "RIMediaUploadOperation.h"
#import "RIMediaUploader.h"
#import "RIMediaUploadOperation.h"

#import "RISharedFeed.h"
#import "RIUserMe.h"

#import "RINewsFeed.h"
#import "RIAuthenticationManager.h"

NSString * const kRICreateFeedErrorDomain = @"com.ringid.create.feed.error.domain";
NSString * const kRIFetchLinkInformationErrorDomain = @"com.ringid.fetch.linkinformation.error.domain";;

NSString * const kFeedCreationOperationStartedNotification = @"kFeedCreationOperationStartedNotification";
NSString * const kFeedCreationOperationFinishedNotification = @"kFeedCreationOperationFinishedNotification";
NSString * const kFeedCreationOperationFailedNotification = @"kFeedCreationOperationFailedNotification";

@interface RINewFeedOperation()<RIMediaUploadOperationDelegate>{

    dispatch_group_t group;
    
}

@property(nonatomic, strong) RIDAlertView *alertView;
@property(nonatomic, strong) NSMutableArray *failedOperations;

@property(nonatomic, assign) BOOL isUploadFinshedWithError;
@property(nonatomic, assign) NSInteger operationCount;

@property (nonatomic, assign) NSInteger totalProgressSegment;
@property (nonatomic, assign) NSInteger maximumProgressValuePerSegment;
@property (nonatomic, assign) NSInteger completedProgresssegment;
@property (nonatomic, assign) RIServiceType serviceType;
@end

@implementation RINewFeedOperation

- (instancetype)initWithFeed:(RINewsFeed *)feed withServiceType:(RIServiceType)serviceType
{
    self = [super init];
    
    if (self) {
        self.serviceType = serviceType;
        _completeTask = NO;
        _feed = feed;
        _feedValidity = -30; // default values
        _mediaUploadQueue = [[NSOperationQueue alloc] init];
        _mediaUploadQueue.maxConcurrentOperationCount = 1;
        _failedOperations = [[NSMutableArray alloc] initWithCapacity:0];
    }
    
    return self;
}

- (void)dealloc
{
    self.failedOperations = nil;
    self.alertView = nil;
    self.mediaUploadQueue = nil;
    self.feed = nil;
    self.onCompletionBlock = nil;
	group = nil;
}

- (void)main {
    
    group = dispatch_group_create();

    dispatch_async(dispatch_get_main_queue(), ^{
        [[RIFeedManager sharedInstance] sendDataToServer:5.0f];
    });
    
    [self calculateProgressParams];
    self.completedProgresssegment = 0;
    
    if (self.feed.photoAlbum.albumImages.count) {
        [self addMediaOperationToQueueFromArray:self.feed.photoAlbum.albumImages];
    }
    
    if ([[self.feed.mediaAlbum getAllAlbumItems] count] > 0) {
        [self addMediaOperationToQueueFromArray:[self.feed.mediaAlbum getAllAlbumItems]];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationStartedNotification object:self];
    });
                   
    [self.mediaUploadQueue waitUntilAllOperationsAreFinished];
    
    if ([self isCancelled]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[RIFeedManager sharedInstance] sendDataToServer:100];
        });
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationFailedNotification object:self];
            [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationFinishedNotification object:self];
        });
        
        return;
    }
    
//    if (!self.feed.feedStatus.length && !self.feed.mediaAlbum.albumItems.count && !self.feed.images.count && !self.feed.location && !self.feed.linkURL && !(self.feed.friendTagList.count || self.feed.recentAddedTagFriends.count|| self.feed.removedTagFriends.count) && !self.feed.moodList.count && self.feed.feedType != RIFeedTypeStatusShare) {
//        [[RIFeedManager sharedInstance] sendDataToServer:100];
//        return;
//    }
    
    switch (self.feed.feedType) {
        case RIFeedTypeImage:
            [self sendRegularFeedUpdateCreationRequest];
            break;
            
        case RIFeedTypeText:
            [self sendRegularFeedUpdateCreationRequest];
            break;
        
        case RIFeedTypeAlbumUpdated:
            //skip now
            break;
            
        case RIFeedTypeAudio:
            [self sendRegularFeedUpdateCreationRequest];
            break;
            
        case RIFeedTypeVideo:
            [self sendRegularFeedUpdateCreationRequest];
            break;
        case RIFeedTypeStatusShare:
            [self sendShareFeedInformationToServer];
            break;

        default:
            break;
    }
    
    // make a wait until get response from server
    if ([self isCancelled])
        return;

    [self applyGroupWait];
    

}

- (void)addMediaOperationToQueueFromArray:(NSArray *)items
{
    BlockWeakSelf weakSelf = self;

    // add upload operation as dependency
    for (id media in items) {
        if ([media isKindOfClass:[RIImage class]]) {
            if ([(RIImage *)media imageId] == 0 && ![self isCancelled]) {
                [(RIImage *)media setPrefferedUploadURL:[RIAppConfigurationManager albumImageUploadApiURL]];
                RIMediaUploadOperation *operation = [[RIMediaUploadOperation alloc] initWithImageMedia:media withServiceType:self.serviceType];
                [operation setDelegate:self];
                [self addDependency:operation];
                [self.mediaUploadQueue addOperation:operation];
            }
        } else if ([media isKindOfClass:[RIMediaAlbumItem class]]) {
            RIMediaAlbumItem *item = (RIMediaAlbumItem *)media;
            if ([item identifier] == 0 && ![self isCancelled]) {
                
                if (item.mediaType == RIMediaTypeAudio) {
                    [item setPrefferedUploadURL:[RIAppConfigurationManager audioFileUploadApiURL]];
                } else {
                    [item setPrefferedUploadURL:[RIAppConfigurationManager videoFileUploadApiURL]];
                }
                
                RIMediaUploadOperation *mediaOperation = [[RIMediaUploadOperation alloc] initWithMediaAlbumItem:item withServiceType:self.serviceType];
                [mediaOperation setDelegate:self];
                
                if ([item thumbImage] && item.mediaType == RIMediaTypeAudio) {
                    [item.thumbImage setPrefferedUploadURL:[RIAppConfigurationManager audioFileThumbImageUploadApiURL]];
                    
                    RIMediaUploadOperation *thumbOperation = [[RIMediaUploadOperation alloc] initWithImageMedia:[item thumbImage] withServiceType:self.serviceType];
					__weak __typeof(RIMediaUploadOperation) *weakThumbOperation = thumbOperation;

					[thumbOperation setCompletionBlock:^{
						weakSelf.completedProgresssegment ++;
						__strong RIMediaUploadOperation *strongThumbOperation = weakThumbOperation;

						if (strongThumbOperation) {
							item.thumbImgeURL = [[strongThumbOperation.image imageURLString] copy];;
							[mediaOperation removeDependency:strongThumbOperation];
						}
                    }];
                    
                    [mediaOperation addDependency:thumbOperation];
                    [self addDependency:mediaOperation];
                    [self.mediaUploadQueue addOperation:thumbOperation];
                    [self.mediaUploadQueue addOperation:mediaOperation];
                    
                } else {
                    [self addDependency:mediaOperation];
                    [self.mediaUploadQueue addOperation:mediaOperation];
                }
            }
        }
    }
}

- (void)applyGroupWait
{
    if (group == nil) {
        group = dispatch_group_create() ;
    }
    
    dispatch_group_enter(group);
    dispatch_group_wait(group,DISPATCH_TIME_FOREVER);
}

- (void)leaveGroupWait
{
    if (group) {
        dispatch_group_leave(group);
    }
}

- (void)calculateProgressParams
{
    self.totalProgressSegment = 1;
    self.totalProgressSegment += self.feed.photoAlbum.albumImages.count;
    
    for (RIMediaAlbumItem *item in [self.feed.mediaAlbum getAllAlbumItems]) {
        if ([item identifier] == 0) {
            if ([item thumbImage]) {
                self.totalProgressSegment ++;
            }
            self.totalProgressSegment ++;
        }
    }
    self.maximumProgressValuePerSegment = 100.0/self.totalProgressSegment;
}

- (void)cancel
{
    [super cancel];
    [self.mediaUploadQueue cancelAllOperations];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationFinishedNotification object:self];
    });
}

- (void)setCompleteTask:(BOOL)completeTask
{
    if (completeTask) {
        [self leaveGroupWait];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (self.onCompletionBlock) {
            self.onCompletionBlock(self.feed, nil);
        }
        
        [[RIFeedManager sharedInstance] sendDataToServer:100];
        [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationFinishedNotification object:self];
    });
}

- (void)didFinished:(RIMediaUploadOperation *)operation uploadedImage:(RIImage *)image withServiceType:(RIServiceType)type
{
    [self removeDependency:operation];
    
    if (self.mediaUploadQueue.operationCount <= 0) {
        // means we have completed upload
        // send feed creation request
//        [self.mediaUploadQueue cancelAllOperations];
        self.isUploadFinshedWithError = NO;
    }
    
    self.completedProgresssegment ++;
}

- (void)didFinished:(RIMediaUploadOperation *)operation uploadedMedia:(RIMediaAlbumItem *)albumItem withServiceType:(RIServiceType)type
{
    [self removeDependency:operation];

    if (self.mediaUploadQueue.operationCount <= 0) {
        // means we have completed upload
        self.isUploadFinshedWithError = NO;
    }
    
    self.completedProgresssegment ++;
}

- (void)didChangedProgress:(RIMediaUploadOperation *)operation percentageUploaded:(CGFloat)percentage withServiceType:(RIServiceType)type
{
    NSInteger progress = 5.0 + (self.completedProgresssegment*self.maximumProgressValuePerSegment)+(self.maximumProgressValuePerSegment*percentage/100);
//    RILog(@"percentage %f, progress: %d",percentage,progress);

    dispatch_async(dispatch_get_main_queue(), ^{
        [[RIFeedManager sharedInstance] sendDataToServer:progress];

    });
    
    if ([self isCancelled]) {
        [self didFailed:operation withError:[NSError errorWithDomain:kRICreateFeedErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : @"Status publish operation cancelled."}] withServiceType:type];
    }
}

- (void)didFailed:(RIMediaUploadOperation *)operation withError:(NSError *)error withServiceType:(RIServiceType)type
{
    // abort pending upload operations and mark as failed
    self.isUploadFinshedWithError = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[RIFeedManager sharedInstance] sendDataToServer:100];
        
        if (self.onCompletionBlock) {
            self.onCompletionBlock(self.feed, error);
        }
        
        if (![operation isCancelled]) {
            [self showFailedMessageWithOperation:operation error:error];
        }
    });
    
    if (![operation isCancelled]) {
        [self.failedOperations addObject:operation];
    }
}


- (void)sendRegularFeedUpdateCreationRequest
{
    
    NSMutableDictionary *information = [NSMutableDictionary dictionary];
    
    // session & request IDs
    [information setValue:[MakePacket randomNumber] forKey:kCommandRequestIDKey];
    [information setValue:[[RingManager sharedInstance] getSessionId] forKey:kCommandSessionIDKey];
    
    if(self.serviceType != RIUserProfileTypeDefaultUser){
        [information setValue:[[RIAuthenticationManager sharedInstance] myPageIDInNumber] forKey:KEY_SERVICE_UTID];
    }
    // add feed entities
    [information addEntriesFromDictionary:[self.feed elementDictionary]];

    // add requesting action no. & type

    
    if (self.feed.feedId) {
        
        [information setValue:[NSNumber numberWithInt:TYPE_EDIT_STATUS] forKey:KEY_ACTION];
        [information setValue:self.feed.feedId forKey:KEY_NEWS_FEED_ID];
        
        if (self.feed.moodList) {
            [information setValue:self.feed.moodList forKey:KEY_MOOD_IDS];
        }
    } else {
        
        if(self.feed.photoAlbum.albumImages.count) {
            [information setValue:[NSNumber numberWithInt:TYPE_UPLOAD_STATUS_TEXT] forKey:KEY_ACTION];
        }else {
            if ([[self.feed.mediaAlbum getAllAlbumItems] count]) {
                [information setValue:[NSNumber numberWithInt:TYPE_UPLOAD_STATUS_TEXT] forKey:KEY_ACTION];
            } else {
                [information setValue:[NSNumber numberWithInt:TYPE_UPLOAD_STATUS_TEXT] forKey:KEY_ACTION];
            }
        }
        
        if (self.feed.moodList.count) {
            [information setValue:self.feed.moodList forKey:KEY_MOOD_IDS];
        }
    }
    
    [information setValue:@(self.feed.feedValidity) forKey:KEY_VALIDITY];

    [[ActionManager sharedInstance] addCommand:@"RICreateFeed_CMD" params:information withFeedbackBlock:^(id responseDict)
     {

         if (responseDict != nil && [responseDict[KEY_SUCCESS] integerValue]) {
             
             NSMutableDictionary *mutableResponse = [NSMutableDictionary dictionaryWithDictionary:responseDict[KEY_NEWS_FEED]];
             [mutableResponse setValue:[RIProfileManager userMe].profileImageURLPath forKey:kRIFeedKeyUserProfileImage];
          
             
             if (self.feed.feedId) {
                 
                [mutableResponse setValue:@(self.serviceType) forKey:KEY_SERVICE_TYPE];
                [self.feed performSelectorOnMainThread:@selector(updateFromServerResponse:) withObject:mutableResponse waitUntilDone:YES];
                [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(updateFeedForFeedManager:) withObject:@[self.feed,mutableResponse] waitUntilDone:NO];
                 
             } else {
                 self.feed = [[[self.feed class] alloc] initWithDictionary:mutableResponse withServiceType:self.serviceType];
                 NSString *pvtUUID = @"";
                 [self addAlbumIfAlbumUserIsOwner:mutableResponse];
                 
                 if ([self.feed isLinkIsLiveFeed]) {
                     
                     if ([[RIFeedManager sharedInstance] deleteLiveLinkFeedFromFeedManagerForUserTableID:[self.feed feedOwnerUserTableID] withServiceType:self.serviceType]) {
                       
                        
                         [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(addFeedToFeedManager:) withObject:@[self.feed,@(FetchTypeNone),@(FeedInfoTypeNewFeed),pvtUUID] waitUntilDone:NO];
                         
                     } else {
                       
                           [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(addFeedToFeedManager:) withObject:@[self.feed,@(FetchTypeNone),@(FeedInfoTypeNewFeed),pvtUUID] waitUntilDone:NO];
                         
                     }
                 } else {
                     
                       [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(addFeedToFeedManager:) withObject:@[self.feed,@(FetchTypeNone),@(FeedInfoTypeNewFeed),pvtUUID] waitUntilDone:NO];
                    
                 }

             }
             
             if ([[self.feed liveSchedule] timeStamp]) {
                 [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(addLiveScheduleInToScheduleList:) withObject:[[self.feed liveSchedule] copy] waitUntilDone:NO];
             }
             
         } else {
             if (self.onCompletionBlock) {
                 if (responseDict[KEY_MESSAGE]) {
                     self.onCompletionBlock(self.feed, [NSError errorWithDomain:kRICreateFeedErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey :  responseDict[KEY_MESSAGE]}]);
                 } else {
                     self.onCompletionBlock(self.feed, [NSError errorWithDomain:kRICreateFeedErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey :  @"Unknown exception happend."}]);
                 }
             }
         }
         
         [self setCompleteTask:YES];
     }];
}

- (void)addAlbumIfAlbumUserIsOwner:(id)value
{
    if ([value isKindOfClass:[NSDictionary class]]) {
        
        NSDictionary *contentDictionary = value[kRIFeedAlbumDetails];
        
        if ([contentDictionary isKindOfClass:[NSDictionary class]]) {
            
            RIMediaAlbum *mediaAlbum = [[RIMediaAlbum alloc] initWithDictionary:contentDictionary withServiceType:self.serviceType];
            
            if([mediaAlbum.albumOwner isEqualToString:[[RingManager sharedInstance] getUserTableID]] == YES) {
                
                
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_MEDIA_ALBUM_ADDED object:mediaAlbum];
                
                for ( RIMediaAlbumItem *item in [mediaAlbum getAllAlbumItems]) {
                 NSDictionary *notificationDictionary = [NSMutableDictionary dictionaryWithCapacity:0];
                 [notificationDictionary setValue:mediaAlbum.identifier forKey:KEY_ALBUM_ID];
                 [notificationDictionary setValue:[NSNumber numberWithInteger:item.mediaType] forKey:kRIMediaAlbumItemMediaType];
                 [notificationDictionary setValue:item.identifier forKey:KEY_MEDIA_CONTENT_ID];
                 [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_MEDIA_ALBUM_ITEM_ADDED object:notificationDictionary];
                }
                
            }
        }
    }
}


- (void)sendShareFeedInformationToServer
{
    
    NSMutableDictionary *information = [NSMutableDictionary dictionary];
    
    // session & request IDs
    
    [information setValue:[MakePacket randomNumber] forKey:kCommandRequestIDKey];
    [information setValue:[[RingManager sharedInstance] getSessionId] forKey:kCommandSessionIDKey];
    [information setValue:@(TYPE_FEED_SHARE) forKey:KEY_ACTION];
 
    if (self.serviceType != RIUserProfileTypeDefaultUser ) {
        [information setValue:[[RIAuthenticationManager sharedInstance] myPageIDInNumber] forKey:KEY_SERVICE_UTID];
    }
    
    // add feed entities
    
    RISharedFeed *shareFeed = (RISharedFeed *)self.feed;
    [information addEntriesFromDictionary:[shareFeed elementDictionary]];
    
    if (self.feed.moodList) {
        [information setValue:self.feed.moodList forKey:KEY_MOOD_IDS];
    }

    
    [[ActionManager sharedInstance] addCommand:@"RIShareFeed_CMD" params:information withFeedbackBlock:^(id responseDict) {
        
        NSMutableDictionary *feedInfo = [responseDict[KEY_NEWS_FEED] mutableCopy];
        if (feedInfo == nil) {
            feedInfo = responseDict ;
        }
        if (responseDict != nil && [responseDict[KEY_SUCCESS] integerValue]) {
            if (self.feed.feedId.length) {
                [feedInfo setValue:@(self.serviceType) forKey:KEY_SERVICE_TYPE];
                [self.feed updateFromServerResponse:feedInfo];
            } else {
                
                self.feed = (RISharedFeed *)[[RIFeedManager sharedInstance] getFeedModelFromDictionary:feedInfo withServiceType:self.serviceType];
               
            }
            
            [[RIFeedManager sharedInstance] performSelectorOnMainThread:@selector(newSharedFeedPostStatusToFeedManager:) withObject:@[self.feed,[NSNumber numberWithInteger:FetchTypeNone],[NSNumber numberWithInteger:FeedInfoTypeNewFeed]] waitUntilDone:NO];
        }else{
            
            NSString *message =  ([responseDict[KEY_MESSAGE] length]) ? responseDict[KEY_MESSAGE] : @"You can't share this status!";
            [TSMessage showNotificationWithTitle:nil subtitle:NSLocalizedString(message, @"Message") type:TSMessageNotificationTypeMessage];
        
        }
        
        [self setCompleteTask:YES];
        
    }];
    
}

- (void)cancelMediaOperationForItem:(RIMediaAlbumItem *)mediaItem
{
    RIMediaUploadOperation *mediaUploadOPeration = nil;

    for (RIMediaUploadOperation *uploadOpt in [self.mediaUploadQueue operations]) {
        if([self.feed.mediaAlbum getAllAlbumItems]) {
            if (uploadOpt.albumItem == mediaItem) {
                mediaUploadOPeration = uploadOpt;
                break;
            }
        }
    }

    if (mediaUploadOPeration) {
        [mediaUploadOPeration cancelUploadOperation];
        [self removeDependency:mediaUploadOPeration];
    }
    
    if (mediaItem.uploadStatus != RIMediaAlbumItemDownloadStateCompleted) {
        [self.feed.mediaAlbum removeItem:mediaItem];
        [self calculateProgressParams];
    }
}

- (void)alertView:(RIDAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if ([alertView firstOtherButtonIndex] == buttonIndex) {
        //just continue to publish
        for (RIMediaUploadOperation *mediaOperation in self.failedOperations) {
            if (mediaOperation.image) {
                [self.feed.photoAlbum removeItem:mediaOperation.image];
            } else if(mediaOperation.albumItem){
                [self.feed.mediaAlbum removeItem:mediaOperation.albumItem];
            }
            
            [mediaOperation cancelUploadOperation];
        }
    } else {
        // try again
        for (RIMediaUploadOperation *mediaOperation in self.failedOperations) {
            NSMutableArray *items = [NSMutableArray array];
            
            if (mediaOperation.image) {
                [items addObject:mediaOperation.image];
            } else if(mediaOperation.albumItem){
                [items addObject:mediaOperation.albumItem];
            }
            
            [self addMediaOperationToQueueFromArray:items];
            [mediaOperation cancelUploadOperation];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kFeedCreationOperationStartedNotification object:self];
        });
    }
    
    [self.failedOperations removeAllObjects];
}

- (void)showFailedMessageWithOperation:(RIMediaUploadOperation *)operation error:(NSError *)error;
{
    NSMutableString *title = [[NSMutableString alloc] init];
    NSString *buttonTitle = @"";
    
    [title appendString:@"Network Error. "];
    
    if (operation.image) {
        [title appendString:@"image"];
        buttonTitle = @"Skip this image";
    } else if(operation.albumItem.mediaType == RIMediaTypeAudio) {
        [title appendString:@"audio file"];
        buttonTitle = @"Skip this audio";

    } else if(operation.albumItem.mediaType == RIMediaTypeVideo) {
        [title appendString:@"video file"];
        buttonTitle = @"Skip this video";
    }
    
    [title appendString:@" could not be uploaded."];
    self.alertView = [[RIDAlertView alloc] initWithTitle:title message:error.localizedDescription delegate:self cancelButtonTitle:nil otherButtonTitles:buttonTitle,@"Try again", nil];
    
    CGSize size = [UIScreen mainScreen].bounds.size;
//    UIView *contentView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, size.width * 0.6f, size.height * 0.6f)];
    
    UIImageView* imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, size.width * 0.6f, size.height * 0.35f)];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    
    if (operation.image) {
        [operation.image imageFromAssetWithCompletion:^(UIImage *image) {
            [imageView setImage:[image resizedImageWithScaleToHeight:size.height * 0.35f]];
        }];
    } else {
        [imageView setImage:[[operation.albumItem.thumbImage image] resizedImageWithScaleToHeight:size.height * 0.35f]];
    }
    
//    [contentView addSubview:imageView];
//    
//    UILabel *message = [[[UILabel alloc] initWithFrame:CGRectMake(0, size.height * 0.3f, size.width * 0.6f, size.height * 0.1f)];
//    message.text = @"Would you like to continue publish your status?";
//    message.textAlignment = NSTextAlignmentCenter;
//    [contentView addSubview:message];
    
    [self.alertView setValue:imageView forKey:@"accessoryView"];
    
    [self.alertView show];
}


@end
