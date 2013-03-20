//
//  WebDAVManager.h
//
//  Created by Raphael Bartolome on 21.01.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//
//  This code is inspired and may inlcude code snippets from August Muellers (@ccgus) WebDav implementation at https://github.com/ccgus/flycode
//

#import <Foundation/Foundation.h>

typedef enum {
    kWebDAVManagerRequestPROPFIND,
    kWebDAVManagerRequestMKCOL,
    kWebDAVManagerRequestPUT,
    kWebDAVManagerRequestGET,
    kWebDAVManagerRequestDELETE,
    kWebDAVManagerRequestCOPY,
    kWebDAVManagerRequestMOVE
} WebDAVManagerRequestType;


typedef void (^WebDAVManagerCompletionBlock)(NSURL *url, WebDAVManagerRequestType requestType, NSDictionary *userinfo, NSInteger responseStatusCode, NSError *error, BOOL success);

@interface WebDAVManager : NSObject

@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;
@property (nonatomic, retain) NSURL *remoteURL;
@property (nonatomic, retain) NSURL *localURL;

- (void)createDirectoryAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
- (void)directoryListingAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
- (void)writeData: (NSData *)data toURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
- (void)dataWithContentsOfURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
- (void)removeItemAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
- (void)copyItemAtURL: (NSURL *)url toURL: (NSURL *)destination completion: (WebDAVManagerCompletionBlock)completion;
- (void)moveItemAtURL: (NSURL *)url  toURL: (NSURL *)destination completion: (WebDAVManagerCompletionBlock)completion;

+ (BOOL)contentTypeIsDirectory: (NSString *)contentType;

@end
