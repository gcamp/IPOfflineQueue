/*
ViewController.m
Created by Marco Arment on 8/30/11.

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

#import "ViewController.h"

@implementation ViewController
@synthesize queue;
@synthesize succeedSwitch;

#pragma mark - IPOfflineQueueDelegate

- (BOOL)offlineQueueShouldAutomaticallyResume:(IPOfflineQueue *)queue
{
    return YES;
}

- (IPOfflineQueueResult)offlineQueue:(IPOfflineQueue *)queue executeActionWithUserInfo:(NSDictionary *)userInfo
{
    NSLog(@"Executing task: %@", [userInfo valueForKey:@"taskID"]);
    [NSThread sleepForTimeInterval:0.5];
    NSLog(@"     done task: %@", [userInfo valueForKey:@"taskID"]);
    return succeedSwitch.on ? IPOfflineQueueResultSuccess : IPOfflineQueueResultFailureShouldPauseQueue;
}

#pragma mark - Test interface

- (IBAction)enqueueMoreTasksButtonTapped:(id)sender
{
    int i;
    for (i = lastTaskID; i < lastTaskID + 10; i++) {
        [self.queue enqueueActionWithUserInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"task%d", i] forKey:@"taskID"]];
    }
    lastTaskID += 10;
}

- (IBAction)emptyQueueButtonTapped:(id)sender
{
    [self.queue clear];
}

- (IBAction)releaseQueueButtonTapped:(id)sender
{
    [self.queue halt];
    self.queue = nil;
}

- (IBAction)newQueueButtonTapped:(id)sender
{
    self.queue = [[[IPOfflineQueue alloc] initWithName:@"test" delegate:self] autorelease];
}

- (IBAction)queueRunningSwitchChanged:(UISwitch *)sender
{
    if (sender.on) {
        [self.queue resume];
    } else {
        [self.queue pause];
    }
}

- (IBAction)enableTimerButtonTapped:(UIButton *)sender
{
    if (self.queue.autoResumeInterval) {
        self.queue.autoResumeInterval = 0;
        [sender setTitle:@"Enable auto-resume timer" forState:UIControlStateNormal];
    } else {
        self.queue.autoResumeInterval = 5;
        [sender setTitle:@"Disable auto-resume timer" forState:UIControlStateNormal];
    }
}

#pragma mark - View fluff

- (void)viewDidLoad
{
    [super viewDidLoad];
    lastTaskID = 0;
    self.queue = [[[IPOfflineQueue alloc] initWithName:@"test" delegate:self] autorelease];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    self.succeedSwitch = nil;
    self.queue = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
