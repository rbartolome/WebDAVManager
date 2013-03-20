//
//  WebDAVManager.m
//
//  Created by Raphael Bartolome on 21.01.13.
//  Copyright (c) 2013 Raphael Bartolome. All rights reserved.
//
//  This code is inspired and may inlcude code snippets from August Muellers (@ccgus) WebDav implementation at https://github.com/ccgus/flycode
//

#import "WebDAVManager.h"

NSString *WebDAVContentTypeKey   = @"contenttype";
NSString *WebDAVETagKey          = @"etag";
NSString *WebDAVHREFKey          = @"href";
NSString *WebDAVURIKey           = @"uri";

static NSInteger successResponseCodeRangeBegin = 100;
static NSInteger successResponseCodeRangeEnds = 299;


@interface WebDAVManagerRequest : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate, NSXMLParserDelegate>

@property(atomic) BOOL success;

@property (nonatomic, retain) NSError *requestError;
@property(nonatomic, retain) NSMutableURLRequest *request;
@property(nonatomic, retain) NSURL *url;
@property(atomic) WebDAVManagerRequestType type;
@property(nonatomic, copy) WebDAVManagerCompletionBlock completionBlock;
@property(nonatomic, retain) NSString *username;
@property(nonatomic, retain) NSString *password;
@property(nonatomic, retain) NSMutableData *responseData;
@property(atomic) NSInteger responseStatusCode;

@property (nonatomic, retain) NSOperationQueue *connectionQueue;

- (void)startRequest;

@end

@implementation WebDAVManagerRequest
{
    NSMutableString *_xmlChars;
    NSMutableDictionary *_xmlBucket;
    NSMutableArray *_directoryBucket;

    NSUInteger _parseState;    
    NSUInteger _uriLength;
    
    NSURLConnection *_connection;
}

@synthesize request;
@synthesize url;
@synthesize type;
@synthesize completionBlock;
@synthesize username = _username;
@synthesize password = _password;

- (void)dealloc;
{
    [self setRequest: nil];
    [self setUrl: nil];
    [self setUsername: nil];
    [self setPassword: nil];
    [self setCompletionBlock: nil];
    
    _xmlChars = nil;
    _xmlBucket = nil;
    _directoryBucket = nil;
}
- (id)init;
{
    if((self = [super init]))
    {
        [self setConnectionQueue: [[NSOperationQueue alloc] init]];
    }
    
    return self;
}

- (void)_startRequest: (id)sender;
{
    _directoryBucket = [[NSMutableArray alloc] init];
    [[self request] setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    
    _uriLength = [[[[self url] path] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] length] + 1;
    if([NSURLConnection canHandleRequest: [self request]])
    {
        _connection = [[NSURLConnection alloc] initWithRequest:[self request]
                                                      delegate: self
                                              startImmediately: NO];
        
        [_connection setDelegateQueue: [self connectionQueue]];
        
        [_connection start];
    }
    else
    {        
        [self setSuccess: NO];
        [self requestFinished: nil];
    }
}

- (void)startRequest;
{
    [self _startRequest: nil];
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError: (NSError *)error;
{
    [self setSuccess: NO];
    [self setRequestError: error];
    [self requestFinished: nil];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    
    if(_username && _password && ([challenge previousFailureCount] == 0))
    {
        NSURLCredential *cred = [NSURLCredential credentialWithUser: _username
                                                           password: _password
                                                        persistence: NSURLCredentialPersistenceForSession];
        
        [[challenge sender] useCredential: cred forAuthenticationChallenge: challenge];
    }
    else
    {
        [self setResponseStatusCode: 401];
        [self setSuccess: NO];
        [self requestFinished: nil];
    }
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return ![[protectionSpace authenticationMethod] isEqualToString: NSURLAuthenticationMethodClientCertificate];
}

#pragma mark - NSURLConnectionDataChallenge

- (void)connection:(NSURLConnection *)connection didReceiveResponse: (NSURLResponse *)URLresponse
{    
    [_responseData setLength: 0];
    
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)URLresponse;
    
    if(![httpResponse isKindOfClass: [NSHTTPURLResponse class]])
    {
        NSLog(@"%s:%d", __FUNCTION__, __LINE__);
        NSLog(@"Unknown response type: %@", URLresponse);
        return;
    }
    
    _responseStatusCode = [httpResponse statusCode];
    
    if(_responseStatusCode >= 400)
    {
        [connection cancel];
        
        [self setSuccess: NO];
        [self requestFinished: nil];
    }
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{    
    if(!_responseData)
    {
        [self setResponseData: [NSMutableData data]];
    }
    
    [_responseData appendData:data];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self setSuccess: NO];
    
    if([self responseStatusCode] >= successResponseCodeRangeBegin && [self responseStatusCode] <= successResponseCodeRangeEnds)
        [self setSuccess: YES];
    
    
    if([self type] == kWebDAVManagerRequestPROPFIND)
    {        
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData: _responseData];
        [parser setDelegate: self];
        [parser parse];
        
        [self requestFinished: _directoryBucket ? @{@"responseData": _directoryBucket} : nil];
    }
    else
    {
        [self requestFinished: [self responseData] ? @{@"responseData": [self responseData]} : nil];
    }
}

- (void)requestFinished: (id)resultData;
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        completionBlock([self url],
                        [self type],
                        resultData,
                        [self responseStatusCode],
                        [self requestError],
                        [self success]);
    });
}

#pragma mark - NSXML parser

- (void)parserDidStartDocument:(NSXMLParser *)parser;
{
}

- (void)parserDidEndDocument:(NSXMLParser *)parser;
{
}

- (void)parser:(NSXMLParser *)parser validationErrorOccurred:(NSError *)validationError;
{
}

- (void)parser: (NSXMLParser *)parser didStartElement: (NSString *)elementName namespaceURI: (NSString *)namespaceURI qualifiedName: (NSString *)qName attributes: (NSDictionary *)attributeDict
{
    
    if (!_xmlChars)
    {
        _xmlChars = [NSMutableString string];
    }
    
    [_xmlChars setString: @""];
    
    if ([elementName isEqualToString: @"D:response"])
    {
        _xmlBucket = [NSMutableDictionary dictionary];
    }
}

+ (NSDate *)parseDateString: (NSString *)dateString
{
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    NSDate *date = [dateFormat dateFromString: dateString];

    if(!date)
    {
        NSLog(@"Could not parse %@", dateString);
    }
    else
    {
        NSTimeZone *tz = [NSTimeZone localTimeZone];
        NSInteger seconds = [tz secondsFromGMTForDate: date];
        date = [NSDate dateWithTimeInterval: seconds sinceDate: date];
    }
    
    return date;
}

+ (NSDate *)parseRFCDateString: (NSString *)dateString
{
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"EEE',' dd MMM yyyy HH':'mm':'ss z"];
    [dateFormat setTimeZone:[NSTimeZone timeZoneWithAbbreviation: @"GMT"]];
    dateFormat.locale=[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"];
    NSDate *date = [dateFormat dateFromString: dateString];
    
    if(!date)
    {
        NSLog(@"Could not parse RFC Date %@", dateString);
    }
    else
    {
        NSTimeZone *tz = [NSTimeZone localTimeZone];
        NSInteger seconds = [tz secondsFromGMTForDate: date];
        date = [NSDate dateWithTimeInterval: seconds sinceDate: date];
    }
    
    return date;
}


- (void)parser: (NSXMLParser *)parser didEndElement: (NSString *)elementName namespaceURI: (NSString *)namespaceURI qualifiedName: (NSString *)qName
{    
        if([elementName isEqualToString: @"D:href"])
        {
            if([_xmlChars length] < _uriLength)
            {
                // whoa, problemo.
                NSLog(@"PROBLEMO");
                return;
            }
            
            if([_xmlChars hasPrefix: @"http"])
            {
                NSURL *junk = [NSURL URLWithString: _xmlChars];
                BOOL trailingSlash = [_xmlChars hasSuffix:@"/"];
                [_xmlChars setString: [junk path]];
                if(trailingSlash)
                {
                    [_xmlChars appendString: @"/"];
                }
            }
            
            if([_xmlChars length])
            {
                [_xmlBucket setObject: [_xmlChars copy] forKey: WebDAVURIKey];
            }
            
            NSString *lastBit = [_xmlChars substringFromIndex: _uriLength];
            if ([lastBit length])
            {
                [_xmlBucket setObject: lastBit forKey: WebDAVHREFKey];
            }
        }
        else if([elementName hasSuffix: @":creationdate"] || [elementName hasSuffix: @":modificationdate"])
        {            
            if([_xmlChars length])
            {    
                NSDate *d = [[self class] parseDateString: _xmlChars];
                
                if(d)
                {
                    NSInteger colIdx = [elementName rangeOfString: @":"].location;
                    
                    [_xmlBucket setObject: d forKey: [elementName substringFromIndex: colIdx + 1]];
                }
                else
                {
                    NSLog(@"Could not parse date string '%@' for '%@'", _xmlChars, elementName);
                }
            }
        }
        else if([elementName hasSuffix: @":getlastmodified"])
        {
            if([_xmlChars length])
            {
                NSDate *d = [[self class] parseRFCDateString: _xmlChars];
                
                if(d)
                {
                    NSInteger colIdx = [elementName rangeOfString: @":"].location;
                    
                    [_xmlBucket setObject: d forKey: [elementName substringFromIndex: colIdx + 1]];
                }
                else
                {
                    NSLog(@"Could not parse RFC date string '%@' for '%@'", _xmlChars, elementName);
                }
            }
        }
        else if([elementName hasSuffix: @":getetag"] && [_xmlChars length])
        {
            [_xmlBucket setObject: [_xmlChars copy] forKey: WebDAVETagKey];
        }
        else if([elementName hasSuffix: @":getcontenttype"] && [_xmlChars length])
        {
            [_xmlBucket setObject: [_xmlChars copy] forKey: WebDAVContentTypeKey];
        }
        else if([elementName isEqualToString: @"D:response"])
        {
            if([_xmlBucket objectForKey: @"href"])
            {
                [_directoryBucket addObject: _xmlBucket];
            }

            _xmlBucket = nil;
        }
}

- (void)parser: (NSXMLParser *)parser foundCharacters: (NSString *)string
{
    [_xmlChars appendString: string];
}


- (BOOL)xrespondsToSelector: (SEL)aSelector
{
    return [super respondsToSelector: aSelector];
}

@end

@implementation WebDAVManager
{
}

@synthesize username = _username;
@synthesize password = _password;
@synthesize remoteURL = _remoteURL;
@synthesize localURL = _localURL;

- (id)init;
{
    if((self = [super init]))
    {
    }
    
    return self;
}

- (void)createDirectoryAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"MKCOL"];

    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestMKCOL];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

- (void)writeData: (NSData *)data toURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"PUT"];
    [req setValue: @"application/octet-stream" forHTTPHeaderField: @"Content-Type"];
    [req setValue: [NSString stringWithFormat: @"%ld", (unsigned long)[data length]] forHTTPHeaderField: @"Content-Length"];
    [req setHTTPBody: data];
    
    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestPUT];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

- (void)dataWithContentsOfURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"GET"];

    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestGET];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

- (void)removeItemAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"DELETE"];

    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestDELETE];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

- (void)copyItemAtURL: (NSURL *)url toURL: (NSURL *)destination completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"COPY"];
    [req setValue: [destination absoluteString] forHTTPHeaderField: @"Destination"];

    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestCOPY];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

- (void)moveItemAtURL: (NSURL *)url  toURL: (NSURL *)destination completion: (WebDAVManagerCompletionBlock)completion;
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    [req setHTTPMethod: @"MOVE"];
    [req setValue: [destination absoluteString] forHTTPHeaderField: @"Destination"];

    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestMOVE];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}


- (void)directoryListingAtURL: (NSURL *)url completion: (WebDAVManagerCompletionBlock)completion;
{
    [self PROPFIND: url extras: nil completion: completion];
}

- (void)PROPFIND: (NSURL *)url extras: (NSString *)extra completion: (WebDAVManagerCompletionBlock)completion;
{
    if (!extra)
    {
        extra = @"";
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: url];
    
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalCacheData];
    [req setTimeoutInterval: 60 * 5];
    
    [req setHTTPMethod: @"PROPFIND"];
    
    NSString *xml = [NSString stringWithFormat: @"<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n<D:propfind xmlns:D=\"DAV:\"><D:allprop/>%@</D:propfind>", extra];
    
    [req setValue: @"1" forHTTPHeaderField: @"Depth"];
    [req setValue: @"application/xml" forHTTPHeaderField: @"Content-Type"];
    [req setHTTPBody: [xml dataUsingEncoding: NSUTF8StringEncoding]];
    
    @autoreleasepool {
        WebDAVManagerRequest *request = [[WebDAVManagerRequest alloc] init];
        [request setUsername: [self username]];
        [request setPassword: [self password]];
        [request setUrl: url];
        [request setRequest: req];
        [request setType: kWebDAVManagerRequestPROPFIND];
        [request setCompletionBlock: completion];
        [request startRequest];
    }
}

+ (BOOL)contentTypeIsDirectory: (NSString *)contentType;
{
    if(contentType && [[contentType lowercaseString] rangeOfString: @"directory"].location != NSNotFound)
        return YES;

    return NO;
}

@end
