// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "AppDelegate.h"
#import "GeneratedPluginRegistrant.h"

// The pinned file_picker iOS saver stages plaintext in Documents. This small
// owned adapter instead stages only an explicitly requested export in protected,
// backup-excluded temporary storage. It never returns paths or document bytes.
@interface ProvidentiaExportSaver : NSObject <UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate>
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, strong) UIDocumentPickerViewController *picker;
@property(nonatomic, copy) FlutterResult pending;
@property(nonatomic, strong) NSURL *directory;
- (instancetype)initWithHost:(UIViewController *)host;
- (void)handle:(FlutterMethodCall *)call result:(FlutterResult)result;
@end

@implementation ProvidentiaExportSaver
- (instancetype)initWithHost:(UIViewController *)host {
  self = [super init];
  if (self) {
    self.host = host;
    self.directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ProvidentiaExports"] isDirectory:YES];
    // Recover cleanup after process death, without touching user-saved copies.
    [[NSFileManager defaultManager] removeItemAtURL:self.directory error:NULL];
  }
  return self;
}

- (void)finish:(BOOL)saved {
  FlutterResult callback = self.pending;
  self.pending = nil;
  self.picker = nil;
  [[NSFileManager defaultManager] removeItemAtURL:self.directory error:NULL];
  if (callback) callback(@(saved));
}

- (void)handle:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"discard"]) {
    UIDocumentPickerViewController *picker = self.picker;
    [self finish:NO];
    [picker dismissViewControllerAnimated:NO completion:nil];
    result(nil);
    return;
  }
  if (![call.method isEqualToString:@"save"]) {
    result(FlutterMethodNotImplemented);
    return;
  }
  if (self.pending != nil || self.host == nil) {
    result([FlutterError errorWithCode:@"export_unavailable" message:@"An export dialog is unavailable." details:nil]);
    return;
  }
  NSDictionary *arguments = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : nil;
  NSString *filename = arguments[@"filename"];
  FlutterStandardTypedData *bytes = arguments[@"bytes"];
  NSRegularExpression *namePattern = [NSRegularExpression regularExpressionWithPattern:@"^providentia-(account|home)-export-[0-9a-fA-F-]{36}\\.json$" options:0 error:NULL];
  if (![filename isKindOfClass:[NSString class]] ||
      [namePattern numberOfMatchesInString:filename options:0 range:NSMakeRange(0, filename.length)] != 1 ||
      ![bytes isKindOfClass:[FlutterStandardTypedData class]] || bytes.data.length == 0) {
    result([FlutterError errorWithCode:@"export_invalid" message:@"The export could not be saved." details:nil]);
    return;
  }
  NSError *error = nil;
  NSFileManager *files = [NSFileManager defaultManager];
  [files createDirectoryAtURL:self.directory withIntermediateDirectories:YES
                  attributes:@{NSFileProtectionKey: NSFileProtectionComplete} error:&error];
  if (!error) [self.directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error];
  NSURL *temporary = [self.directory URLByAppendingPathComponent:filename isDirectory:NO];
  if (!error) [bytes.data writeToURL:temporary options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error];
  if (error) {
    [files removeItemAtURL:self.directory error:NULL];
    // Native NSError descriptions may contain a private path. Do not return or log them.
    result([FlutterError errorWithCode:@"export_storage" message:@"The export could not be saved." details:nil]);
    return;
  }
  self.pending = result;
  if (@available(iOS 14.0, *)) {
    self.picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[temporary] asCopy:YES];
  } else {
    self.picker = [[UIDocumentPickerViewController alloc] initWithURL:temporary inMode:UIDocumentPickerModeExportToService];
  }
  self.picker.delegate = self;
  self.picker.presentationController.delegate = self;
  UIViewController *presenter = self.host;
  while (presenter.presentedViewController != nil) presenter = presenter.presentedViewController;
  [presenter presentViewController:self.picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  if (controller == self.picker) [self finish:urls.count > 0];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
  if (controller == self.picker) [self finish:NO];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController {
  if (presentationController.presentedViewController == self.picker) [self finish:NO];
}
@end

@interface AppDelegate ()
@property(nonatomic, strong) ProvidentiaExportSaver *exportSaver;
@property(nonatomic, strong) FlutterMethodChannel *exportChannel;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [GeneratedPluginRegistrant registerWithRegistry:self];
  BOOL launched = [super application:application didFinishLaunchingWithOptions:launchOptions];
  FlutterViewController *controller = (FlutterViewController *)self.window.rootViewController;
  self.exportSaver = [[ProvidentiaExportSaver alloc] initWithHost:controller];
  self.exportChannel = [FlutterMethodChannel methodChannelWithName:@"providentia/data-export" binaryMessenger:controller.binaryMessenger];
  __weak AppDelegate *weakSelf = self;
  [self.exportChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    [weakSelf.exportSaver handle:call result:result];
  }];
  return launched;
}
@end
