/*
IPOfflineQueue.h
Created by Marco Arment on 8/30/11.

If this is useful to you, please consider integrating send-to-Instapaper support
in your app if it makes sense to do so. Details: http://www.instapaper.com/api

Copyright (c) 2011, Marco Arment
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Marco Arment nor the names of any contributors may 
      be used to endorse or promote products derived from this software without 
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL MARCO ARMENT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(You may know this as the New BSD License.)

*/

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <sqlite3.h>

typedef enum {
   IPOfflineQueueResultSuccess = 0,
   IPOfflineQueueResultFailureShouldPauseQueue
} IPOfflineQueueResult;

@class IPOfflineQueue;


@protocol IPOfflineQueueDelegate <NSObject>

// This method will always be called on a thread that's NOT the main thread. So don't call UIKit from it.
// Feel free to block the thread until synchronous NSURLConnections, etc. are completed.
//
// Returning IPOfflineQueueResultSuccess will delete the task.
// Returning IPOfflineQueueResultFailureShouldPauseQueue will pause the queue and the same task will be retried when the queue is resumed.
//  Typically, you'd only return this if the internet connection is offline or some other global condition prevents ALL queued tasks from executing.
- (IPOfflineQueueResult)offlineQueue:(IPOfflineQueue *)queue executeActionWithUserInfo:(NSDictionary *)userInfo;

// Called before auto-resuming upon Reachability changes, app reactivation, or autoResumeInterval elapsed
- (BOOL)offlineQueueShouldAutomaticallyResume:(IPOfflineQueue *)queue;

@end

@interface IPOfflineQueue : NSObject {
    NSString *name;
    sqlite3 *db;
    dispatch_queue_t insertQueue;
    NSConditionLock *updateThreadEmptyLock;
    NSConditionLock *updateThreadPausedLock;
    NSConditionLock *updateThreadTerminatingLock;
    NSTimeInterval autoResumeInterval;
    NSTimer *autoResumeTimer;
    BOOL halt;
    BOOL halted;
}

// name must be unique among all current queue instances, and must be valid as part of a filename, e.g. "downloads" or "main"
- (id)initWithName:(NSString *)name delegate:(id<IPOfflineQueueDelegate>)delegate;

// owner MUST call halt before releasing, otherwise it'll stick around
- (void)halt;

// userInfo must be serializable
- (void)enqueueActionWithUserInfo:(NSDictionary *)userInfo;

- (void)pause;
- (void)resume;
- (void)clear;

@property (nonatomic, retain) id<IPOfflineQueueDelegate> delegate;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, assign) NSTimeInterval autoResumeInterval;

@end
