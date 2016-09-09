/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "ABI10_0_0RCTNetworkTask.h"

#import "ABI10_0_0RCTLog.h"
#import "ABI10_0_0RCTUtils.h"

@implementation ABI10_0_0RCTNetworkTask
{
  NSMutableData *_data;
  id<ABI10_0_0RCTURLRequestHandler> _handler;
  dispatch_queue_t _callbackQueue;

  ABI10_0_0RCTNetworkTask *_selfReference;
}

- (instancetype)initWithRequest:(NSURLRequest *)request
                        handler:(id<ABI10_0_0RCTURLRequestHandler>)handler
                  callbackQueue:(dispatch_queue_t)callbackQueue
{
  ABI10_0_0RCTAssertParam(request);
  ABI10_0_0RCTAssertParam(handler);
  ABI10_0_0RCTAssertParam(callbackQueue);

  static NSUInteger requestID = 0;

  if ((self = [super init])) {
    _requestID = @(requestID++);
    _request = request;
    _handler = handler;
    _callbackQueue = callbackQueue;
    _status = ABI10_0_0RCTNetworkTaskPending;

    dispatch_queue_set_specific(callbackQueue, (__bridge void *)self, (__bridge void *)self, NULL);
  }
  return self;
}

ABI10_0_0RCT_NOT_IMPLEMENTED(- (instancetype)init)

- (void)invalidate
{
  _selfReference = nil;
  _completionBlock = nil;
  _downloadProgressBlock = nil;
  _incrementalDataBlock = nil;
  _responseBlock = nil;
  _uploadProgressBlock = nil;
}

- (void)dispatchCallback:(dispatch_block_t)callback
{
  if (dispatch_get_specific((__bridge void *)self) == (__bridge void *)self) {
    callback();
  } else {
    dispatch_async(_callbackQueue, callback);
  }
}

- (void)start
{
  if (_requestToken == nil) {
    id token = [_handler sendRequest:_request withDelegate:self];
    if ([self validateRequestToken:token]) {
      _selfReference = self;
      _status = ABI10_0_0RCTNetworkTaskInProgress;
    }
  }
}

- (void)cancel
{
  _status = ABI10_0_0RCTNetworkTaskFinished;
  id token = _requestToken;
  if (token && [_handler respondsToSelector:@selector(cancelRequest:)]) {
    [_handler cancelRequest:token];
  }
  [self invalidate];
}

- (BOOL)validateRequestToken:(id)requestToken
{
  BOOL valid = YES;
  if (_requestToken == nil) {
    if (requestToken == nil) {
      if (ABI10_0_0RCT_DEBUG) {
        ABI10_0_0RCTLogError(@"Missing request token for request: %@", _request);
      }
      valid = NO;
    }
    _requestToken = requestToken;
  } else if (![requestToken isEqual:_requestToken]) {
    if (ABI10_0_0RCT_DEBUG) {
      ABI10_0_0RCTLogError(@"Unrecognized request token: %@ expected: %@", requestToken, _requestToken);
    }
    valid = NO;
  }

  if (!valid) {
    _status = ABI10_0_0RCTNetworkTaskFinished;
    if (_completionBlock) {
      ABI10_0_0RCTURLRequestCompletionBlock completionBlock = _completionBlock;
      [self dispatchCallback:^{
        completionBlock(self->_response, nil, ABI10_0_0RCTErrorWithMessage(@"Invalid request token."));
      }];
    }
    [self invalidate];
  }
  return valid;
}

- (void)URLRequest:(id)requestToken didSendDataWithProgress:(int64_t)bytesSent
{
  if (![self validateRequestToken:requestToken]) {
    return;
  }

  if (_uploadProgressBlock) {
    ABI10_0_0RCTURLRequestProgressBlock uploadProgressBlock = _uploadProgressBlock;
    int64_t length = _request.HTTPBody.length;
    [self dispatchCallback:^{
      uploadProgressBlock(bytesSent, length);
    }];
  }
}

- (void)URLRequest:(id)requestToken didReceiveResponse:(NSURLResponse *)response
{
  if (![self validateRequestToken:requestToken]) {
    return;
  }

  _response = response;
  if (_responseBlock) {
    ABI10_0_0RCTURLRequestResponseBlock responseBlock = _responseBlock;
    [self dispatchCallback:^{
      responseBlock(response);
    }];
  }
}

- (void)URLRequest:(id)requestToken didReceiveData:(NSData *)data
{
  if (![self validateRequestToken:requestToken]) {
    return;
  }

  if (!_data) {
    _data = [NSMutableData new];
  }
  [_data appendData:data];

  int64_t length = _data.length;
  int64_t total = _response.expectedContentLength;

  if (_incrementalDataBlock) {
    ABI10_0_0RCTURLRequestIncrementalDataBlock incrementalDataBlock = _incrementalDataBlock;
    [self dispatchCallback:^{
      incrementalDataBlock(data, length, total);
    }];
  }
  if (_downloadProgressBlock && total > 0) {
    ABI10_0_0RCTURLRequestProgressBlock downloadProgressBlock = _downloadProgressBlock;
    [self dispatchCallback:^{
      downloadProgressBlock(length, total);
    }];
  }
}

- (void)URLRequest:(id)requestToken didCompleteWithError:(NSError *)error
{
  if (![self validateRequestToken:requestToken]) {
    return;
  }

  _status = ABI10_0_0RCTNetworkTaskFinished;
  if (_completionBlock) {
    ABI10_0_0RCTURLRequestCompletionBlock completionBlock = _completionBlock;
    [self dispatchCallback:^{
      completionBlock(self->_response, self->_data, error);
    }];
  }
  [self invalidate];
}

@end
