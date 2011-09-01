IPOfflineQueue is a persistent, serial task queue for iOS. It's especially ideal for queuing actions that require an internet connection that may be slow or absent.

* You enqueue tasks to it, and they run whenever they can in a background thread.
* Tasks are always executed in the order in which they were added (FIFO).
* Tasks are __not__ executed in parallel, although you are free to run parallel operations in your task-execution handler.
* Queued tasks persist between application launches.
* The application will remain running in the background until the queue completes or until iOS kills it (after no more than 10 minutes).
* You're welcome to operate multiple queue instances if you'd like to run different tasks.
* GCD is used extensively to prevent blocking the main thread.

If this is useful to you, please consider integrating send-to-Instapaper support in your app if it makes sense to do so. Details: http://www.instapaper.com/api

# Status: extremely alpha

Really. Not even I'm using this in any shipping apps yet. Use at your own risk.

# Usage

* Requires iOS 4.0 or greater.
* __You must link `libsqlite3.dylib` with your project.__

See `ViewController.m` in the sample project for a more detailed example, but it goes like this:

    IPOfflineQueue *queue = [[IPOfflineQueue alloc] initWithName:@"main" delegate:self];

...

    [queue enqueueActionWithUserInfo:myTaskDictionary];

...

    - (IPOfflineQueueResult)offlineQueue:(IPOfflineQueue *)queue executeActionWithUserInfo:(NSDictionary *)userInfo
    {
        // (try to do something)
        
        if (/* internet connection failed */) {
            return IPOfflineQueueResultFailureShouldPauseQueue;
        } else {
            return IPOfflineQueueResultSuccess;
        }
    }

That's all you need to know about, really. (I hope.)

# License

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
