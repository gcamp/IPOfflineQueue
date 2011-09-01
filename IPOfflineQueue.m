/*
IPOfflineQueue.m
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

#import "IPOfflineQueue.h"
#define kMaxRetrySeconds 10

// Debug logging: change to #if 1 to enable
#if 0
#define IPOfflineQueueDebugLog( s, ... ) NSLog(s, ##__VA_ARGS__ )
#else
#define IPOfflineQueueDebugLog( s, ... )
#endif

static NSMutableDictionary *_activeQueues = nil;

@implementation IPOfflineQueue
@synthesize delegate;
@synthesize name;

#pragma mark - SQLite utilities

- (int)stepQuery:(sqlite3_stmt *)stmt
{
   	int ret;	
	// Try direct first
	ret = sqlite3_step(stmt);
	if (ret != SQLITE_BUSY && ret != SQLITE_LOCKED) return ret;
	
    int max_seconds = kMaxRetrySeconds;
	while (max_seconds > 0) {
		IPOfflineQueueDebugLog(@"[IPOfflineQueue] SQLITE BUSY - retrying...");
		sleep(1);
		max_seconds--;
		ret = sqlite3_step(stmt);
		if (ret != SQLITE_BUSY && ret != SQLITE_LOCKED) return ret;
	}
    
	[[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
		reason:@"SQLITE BUSY for too long" userInfo:nil
	] raise];
    
	return ret;
}

- (void)executeRawQuery:(NSString *)query
{
    const char *query_cstr = [query cStringUsingEncoding:NSUTF8StringEncoding];
	int ret = sqlite3_exec(db, query_cstr, NULL, NULL, NULL);
	if (ret != SQLITE_BUSY && ret != SQLITE_LOCKED) return;

	IPOfflineQueueDebugLog(@"[IPOfflineQueue] SQLITE BUSY - retrying...");
	[NSThread sleepForTimeInterval:0.1];
	ret = sqlite3_exec(db, query_cstr, NULL, NULL, NULL);
	if (ret != SQLITE_BUSY && ret != SQLITE_LOCKED) return;
	
    int max_seconds = kMaxRetrySeconds;
	while (max_seconds > 0) {
		IPOfflineQueueDebugLog(@"[IPOfflineQueue] SQLITE BUSY - retrying in 1 second...");
		
		sleep(1);
		max_seconds--;
        ret = sqlite3_exec(db, query_cstr, NULL, NULL, NULL);
		if (ret != SQLITE_BUSY && ret != SQLITE_LOCKED) return;
	}

	[[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
		reason:@"SQLITE BUSY for too long" userInfo:nil
	] raise];
}

#pragma mark - Initialization and schema management

- (id)initWithName:(NSString *)n delegate:(id<IPOfflineQueueDelegate>)d
{
    if ( (self = [super init]) ) {
        @synchronized([self class]) {
            if (_activeQueues) {
                if ([_activeQueues objectForKey:n]) {
               		[[NSException exceptionWithName:@"IPOfflineQueueDuplicateNameException" 
                        reason:[NSString stringWithFormat:@"[IPOfflineQueue] Queue already exists with name: %@", n] userInfo:nil
                    ] raise];
                }
                
                [_activeQueues setObject:n forKey:n];
            } else {
                _activeQueues = [[NSMutableDictionary alloc] initWithObjectsAndKeys:n, n, nil];
            }
        }
        
        halt = NO;
        halted = NO;
        autoResumeInterval = 0;
        name = [n retain];
        self.delegate = d;
        
   		NSString *dbPath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.queue", n]
        ];
        
       	if (sqlite3_open([dbPath cStringUsingEncoding:NSUTF8StringEncoding], &db) != SQLITE_OK) {
            [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                reason:@"Failed to open database" userInfo:nil
            ] raise];
        }

        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'queue'", -1, &stmt, NULL) != SQLITE_OK) {
            [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                reason:@"Failed to read table info from database" userInfo:nil
            ] raise];
        }

        int existingTables = [self stepQuery:stmt] == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : 0;
        sqlite3_finalize(stmt);
        
        if (existingTables < 1) {
            IPOfflineQueueDebugLog(@"[IPOfflineQueue] Creating new schema");
            [self executeRawQuery:@"CREATE TABLE queue (params BLOB NOT NULL)"];
        }
        
        insertQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@-ipofflinequeue-inserts", n] UTF8String], 0);
        updateThreadEmptyLock = [[NSConditionLock alloc] initWithCondition:0];
        updateThreadPausedLock = [[NSConditionLock alloc] initWithCondition:0];
        updateThreadTerminatingLock = [[NSConditionLock alloc] initWithCondition:0];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tryToAutoResume) name:@"kNetworkReachabilityChangedNotification" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tryToAutoResume) name:UIApplicationDidBecomeActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncInserts) name:UIApplicationWillResignActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(halt) name:UIApplicationWillTerminateNotification object:nil];
        
        [NSThread detachNewThreadSelector:@selector(queueThreadMain:) toTarget:self withObject:nil];
    }
    return self;
}

- (void)dealloc
{
    [self halt];

    IPOfflineQueueDebugLog(@"queue dealloc: cleaning up");
    sqlite3_close(db);
    [updateThreadEmptyLock release];
    [updateThreadPausedLock release];
    [updateThreadTerminatingLock release];

    @synchronized([self class]) { [_activeQueues removeObjectForKey:self.name]; }
    
    self.delegate = nil;
    [name release];
    [super dealloc];
}

- (void)tryToAutoResume
{
    if ([updateThreadPausedLock condition] && 
        (! self.delegate || [self.delegate offlineQueueShouldAutomaticallyResume:self])
    ) {
        // Don't want to block notification-handling, so dispatch this
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [updateThreadPausedLock lock];
            [updateThreadPausedLock unlockWithCondition:0];
        });
    }
}

- (void)autoResumeTimerFired:(NSTimer*)theTimer { [self tryToAutoResume]; }


#pragma mark - Queue control

- (void)enqueueActionWithUserInfo:(NSDictionary *)userInfo
{
    // This is done with GCD so queue-add operations return to the caller as quickly as possible.
    // Using the custom insertQueue ensures that actions are always inserted (and executed) in order.
    
    dispatch_async(insertQueue, ^{
        [updateThreadEmptyLock lock];
        NSMutableData *data = [[NSMutableData alloc] init];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [archiver encodeObject:userInfo forKey:@"userInfo"];
        [archiver finishEncoding];
        [archiver release];

        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, "INSERT INTO queue (params) VALUES (?)", -1, &stmt, NULL) != SQLITE_OK) {
            [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                reason:@"Failed to prepare enqueue-insert statement" userInfo:nil
            ] raise];
        }
        
        sqlite3_bind_blob(stmt, 1, [data bytes], [data length], SQLITE_TRANSIENT);
        if ([self stepQuery:stmt] != SQLITE_DONE) {
            [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                reason:@"Failed to insert new queued item" userInfo:nil
            ] raise];
        }
        sqlite3_finalize(stmt);
        
        [data release];
        
        [updateThreadEmptyLock unlockWithCondition:0];
    });
}

- (void)clear
{
    dispatch_sync(insertQueue, ^{
        [updateThreadEmptyLock lock];
        [self executeRawQuery:@"DELETE FROM queue"];
        [updateThreadEmptyLock unlockWithCondition:1];
    });
}

- (void)pause
{
    [updateThreadPausedLock lock];
    [updateThreadPausedLock unlockWithCondition:1];
}

- (void)resume
{
    [updateThreadPausedLock lock];
    [updateThreadPausedLock unlockWithCondition:0];
}

- (void)syncInserts
{
    // Ensure all inserts are written to database before application terminates
    
    UIApplication *application = [UIApplication sharedApplication];
    UIBackgroundTaskIdentifier backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    
    if ([UIDevice currentDevice].multitaskingSupported && (
            application.applicationState == UIApplicationStateInactive ||
            application.applicationState == UIApplicationStateBackground
        )
    ) {
		backgroundTaskIdentifier = [application beginBackgroundTaskWithExpirationHandler:^{ }];
    }
    
    dispatch_sync(insertQueue, ^{ });

    if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
}

- (NSTimeInterval)autoResumeInterval { return autoResumeInterval; }

- (void)setAutoResumeInterval:(NSTimeInterval)newInterval
{
    if (autoResumeInterval == newInterval) return;
    autoResumeInterval = newInterval;

    @synchronized(self) {
        if ([NSThread isMainThread]) {
            if (autoResumeTimer) {
                [autoResumeTimer invalidate];
                [autoResumeTimer release];
            }

            if (newInterval > 0) {
                autoResumeTimer = [[NSTimer scheduledTimerWithTimeInterval:newInterval target:self selector:@selector(autoResumeTimerFired:) userInfo:nil repeats:YES] retain];
            } else {
                autoResumeTimer = nil;
            }
        } else {
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (autoResumeTimer) {
                    [autoResumeTimer invalidate];
                    [autoResumeTimer release];
                }

                if (newInterval > 0) {
                    autoResumeTimer = [[NSTimer scheduledTimerWithTimeInterval:newInterval target:self selector:@selector(autoResumeTimerFired:) userInfo:nil repeats:YES] retain];
                } else {
                    autoResumeTimer = nil;
                }
            });
        }
    }
}

#pragma mark - Queue thread

- (void)queueThreadMain:(id)userInfo
{
    NSAutoreleasePool *threadPool = [[NSAutoreleasePool alloc] init];

    UIApplication *application = [UIApplication sharedApplication];
    BOOL canMultitask = [UIDevice currentDevice].multitaskingSupported;
    UIBackgroundTaskIdentifier backgroundTaskIdentifier = UIBackgroundTaskInvalid;
    sqlite3_stmt *selectStmt = NULL;
    sqlite3_stmt *deleteStmt = NULL;
    int queryResult;

    if (sqlite3_prepare_v2(db, "SELECT ROWID, params FROM queue ORDER BY ROWID LIMIT 1", -1, &selectStmt, NULL) != SQLITE_OK) {
        [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
            reason:@"Failed to prepare queue-item-select statement" userInfo:nil
        ] raise];
    }
    
    while (! halt) {    
        NSAutoreleasePool *loopPool = [[NSAutoreleasePool alloc] init];

        if (canMultitask) backgroundTaskIdentifier = [application beginBackgroundTaskWithExpirationHandler:^{ }];

        [updateThreadPausedLock lockWhenCondition:0];
        if (halt) {
            [updateThreadPausedLock unlock];
            if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
            [loopPool drain];
            break;
        }
        [updateThreadPausedLock unlock];
        
        [updateThreadEmptyLock lockWhenCondition:0];
        if (halt) {
            [updateThreadEmptyLock unlock];
            if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
            [loopPool drain];
            break;
        }
        
        if ( (queryResult = [self stepQuery:selectStmt]) != SQLITE_ROW) {
            if (queryResult == SQLITE_DONE) {
                // No more queued items
                sqlite3_reset(selectStmt);
                [updateThreadEmptyLock unlockWithCondition:1];
                if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
                [loopPool drain];
                continue;
            }
            
            // Some other error
           	[[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                reason:@"Failed to select next queued item" userInfo:nil
            ] raise];
        }        
        [updateThreadEmptyLock unlockWithCondition:0];
        
        if ([updateThreadPausedLock condition]) {
            // Updater was paused while it was waiting for the empty lock
            sqlite3_reset(selectStmt);
            if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
            [loopPool drain];
            continue;
        }

        sqlite_uint64 rowid = sqlite3_column_int64(selectStmt, 0);
        NSData *blobData = [NSData dataWithBytes:sqlite3_column_blob(selectStmt, 1) length:sqlite3_column_bytes(selectStmt, 1)];
        sqlite3_reset(selectStmt);
        
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:blobData];
        NSDictionary *userInfo = [unarchiver decodeObjectForKey:@"userInfo"];
        [unarchiver finishDecoding];
        [unarchiver release];

        IPOfflineQueueResult result = [self.delegate offlineQueue:self executeActionWithUserInfo:userInfo];
        if (result == IPOfflineQueueResultSuccess) {
            if (! deleteStmt && sqlite3_prepare_v2(db, "DELETE FROM queue WHERE ROWID = ?", -1, &deleteStmt, NULL) != SQLITE_OK) {
                [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                    reason:@"Failed to prepare queue-item-delete statement" userInfo:nil
                ] raise];
            }
            
            sqlite3_bind_int64(deleteStmt, 1, rowid);
            if ([self stepQuery:deleteStmt] != SQLITE_DONE) {
                [[NSException exceptionWithName:@"IPOfflineQueueDatabaseException" 
                    reason:@"Failed to delete queued item after execution" userInfo:nil
                ] raise];
            }
            sqlite3_reset(deleteStmt);

        } else if (result == IPOfflineQueueResultFailureShouldPauseQueue) {
            // Pause queue, retry action later
            [updateThreadPausedLock lock];
            [updateThreadPausedLock unlockWithCondition:1];
        }

        if (backgroundTaskIdentifier != UIBackgroundTaskInvalid) [application endBackgroundTask:backgroundTaskIdentifier];
        [loopPool drain];
    }
    
    IPOfflineQueueDebugLog(@"Queue thread halting");
    
    // Cleanup threadmain
    if (selectStmt) sqlite3_finalize(selectStmt);
    if (deleteStmt) sqlite3_finalize(deleteStmt);

    [updateThreadTerminatingLock lock];
    [updateThreadTerminatingLock unlockWithCondition:1];
    
    [threadPool drain];
}

- (void)halt
{
    @synchronized(self) {
        if (halted) return;
        halted = YES;

        dispatch_sync(dispatch_get_main_queue(), ^{
            if (autoResumeTimer) {
                [autoResumeTimer invalidate];
                [autoResumeTimer release];
                autoResumeTimer = nil;
             }
        });
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"kNetworkReachabilityChangedNotification" object:nil];    
    halt = YES;
    
    // Sync inserts
    [self syncInserts];
    dispatch_release(insertQueue);

    IPOfflineQueueDebugLog(@"halt: halting exec thread");
    // Halt queue-execution thread
    halt = YES;
    [updateThreadPausedLock lock];
    [updateThreadPausedLock unlockWithCondition:0];
    [updateThreadEmptyLock lock];
    [updateThreadEmptyLock unlockWithCondition:0];
    
    [updateThreadTerminatingLock lockWhenCondition:1];
    [updateThreadTerminatingLock unlock];
    
    IPOfflineQueueDebugLog(@"halt: done");
}

@end
