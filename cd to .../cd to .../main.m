//
//  main.m
//  cd to ...
//
//  Created by James Tuley on 10/9/19.
//  Copyright © 2019 Jay Tuley. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <ScriptingBridge/ScriptingBridge.h>

#import "Finder.h"
#import "Terminal.h"
#import "iTerm.h"

void openInTerminal(NSURL* url) {
    TerminalApplication* terminal = [SBApplication applicationWithBundleIdentifier:@"com.apple.Terminal"];

    // Check before any SB call to avoid launching Terminal prematurely
    bool wasRunning = [terminal isRunning];

    NSString* path = [url path];
    NSString* escapedPath = [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString* cdCommand = [NSString stringWithFormat:@"cd '%@'", escapedPath];

    TerminalTab* tab;
    if (!wasRunning) {
        // Terminal is not running. Launching it creates a default startup window.
        // Reuse that window instead of opening another one.
        [terminal activate];
        TerminalWindow* win = [[terminal windows] objectAtLocation:@1];
        win = [[terminal windows] objectWithID:[NSNumber numberWithInteger:win.id]];
        tab = [[win tabs] objectAtLocation:@1];
        [terminal doScript:cdCommand in:tab];
    } else {
        // Terminal is already running - open a new window
        [terminal open:@[url]];
        TerminalWindow* newWin = [[terminal windows] objectAtLocation:@1];
        newWin = [[terminal windows] objectWithID:[NSNumber numberWithInteger:newWin.id]];
        tab = [[newWin tabs] objectAtLocation:@1];
    }

    NSString* setName = [[NSUserDefaults standardUserDefaults] stringForKey:@"cdto-new-window-setting"];
    if(setName != nil && ![setName isEqualToString:@""]) {
        TerminalSettingsSet* chosenSet = nil;
        for (TerminalSettingsSet *set in [terminal settingsSets]) {
            if([[set name] isEqualToString:setName]){
                chosenSet = set;
            }
        }
        if(chosenSet != nil){
            tab.currentSettings = chosenSet;
        }
    }

    [terminal activate];
}

void openIniTerm(NSURL* url) {
    NSString* path = [url path];

    // Escape single quotes in the path for AppleScript
    NSString* escapedPath = [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];

    // Check if iTerm is running before launching it
    bool wasRunning = [[SBApplication applicationWithBundleIdentifier:@"com.googlecode.iterm2"] isRunning];

    NSString* script;
    if (!wasRunning) {
        // iTerm is not running. Launching it creates a default startup window.
        // Reuse that window instead of creating another one.
        script = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
            @"    activate\n"
            @"    tell current window\n"
            @"        tell current session\n"
            @"            write text \"cd '%@'; clear\"\n"
            @"        end tell\n"
            @"    end tell\n"
            @"end tell", escapedPath];
    } else {
        // iTerm is already running - create a new window
        script = [NSString stringWithFormat:
            @"tell application \"iTerm\"\n"
            @"    activate\n"
            @"    set newWindow to (create window with default profile)\n"
            @"    tell current session of newWindow\n"
            @"        write text \"cd '%@'; clear\"\n"
            @"    end tell\n"
            @"end tell", escapedPath];
    }

    NSAppleScript* appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary* errorInfo = nil;
    [appleScript executeAndReturnError:&errorInfo];

    if (errorInfo) {
        NSLog(@"iTerm failed, falling back to Terminal: %@", errorInfo);
        openInTerminal(url);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        FinderApplication* finder = [SBApplication applicationWithBundleIdentifier:@"com.apple.Finder"];

        FinderItem *target = [(NSArray*)[[finder selection] get] firstObject];
        FinderFinderWindow* findWin = [[finder FinderWindows] objectAtLocation:@1];
        findWin = [[finder FinderWindows] objectWithID:[NSNumber numberWithInteger: findWin.id]];
        bool selected = true;
        if (target == nil){
            target = [[findWin target] get];
            selected = false;
        }

        NSDictionary* itemProperties = [target properties];
        id originalItem = [itemProperties objectForKey:@"originalItem"];
        if (originalItem != nil && originalItem != [NSNull null]){
            target = originalItem;
        }

        NSString* fileUrl = [target URL];
        if(fileUrl != nil && ![fileUrl hasSuffix:@"/"] && selected){
            fileUrl = [fileUrl stringByDeletingLastPathComponent];
        }

        NSURL* url = [NSURL URLWithString:fileUrl];
        if (url != nil){
            // Get terminal preference from defaults
            NSString* terminalApp = [[NSUserDefaults standardUserDefaults] stringForKey:@"cdto-terminal-app"];

            // Normalize the terminal app identifier
            if (terminalApp == nil || [terminalApp isEqualToString:@""]) {
                terminalApp = @"com.apple.Terminal"; // Default to Terminal.app
            } else if ([terminalApp caseInsensitiveCompare:@"Terminal"] == NSOrderedSame) {
                terminalApp = @"com.apple.Terminal";
            } else if ([terminalApp caseInsensitiveCompare:@"iTerm"] == NSOrderedSame ||
                       [terminalApp caseInsensitiveCompare:@"iTerm2"] == NSOrderedSame) {
                terminalApp = @"com.googlecode.iterm2";
            }

            // Open in the appropriate terminal
            if ([terminalApp isEqualToString:@"com.googlecode.iterm2"]) {
                openIniTerm(url);
            } else {
                // Default to Terminal.app for any unknown values
                openInTerminal(url);
            }
        }
    }
}
