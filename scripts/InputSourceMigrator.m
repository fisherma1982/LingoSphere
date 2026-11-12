#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

static NSString *InputSourceID(TISInputSourceRef source) {
  const void *value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
  return value ? (__bridge NSString *)value : nil;
}

static BOOL InputSourceEnabled(TISInputSourceRef source) {
  const void *value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled);
  return value && CFBooleanGetValue((CFBooleanRef)value);
}

static NSArray *AllInputSources(void) {
  CFArrayRef sources = TISCreateInputSourceList(NULL, true);
  return sources ? CFBridgingRelease(sources) : @[];
}

static TISInputSourceRef FindInputSource(NSString *identifier) {
  for (id object in AllInputSources()) {
    TISInputSourceRef source = (__bridge TISInputSourceRef)object;
    if ([InputSourceID(source) isEqualToString:identifier]) {
      return (TISInputSourceRef)CFRetain(source);
    }
  }
  return NULL;
}

static BOOL SelectSafeFallbackIfNeeded(NSSet<NSString *> *targetIdentifiers) {
  TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
  if (!current) return YES;
  NSString *currentID = InputSourceID(current);
  BOOL needsFallback = currentID && [targetIdentifiers containsObject:currentID];
  CFRelease(current);
  if (!needsFallback) return YES;

  TISInputSourceRef fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
  if (!fallback) return NO;
  OSStatus status = TISSelectInputSource(fallback);
  CFRelease(fallback);
  return status == noErr;
}

static int RegisterBundle(NSString *path) {
  NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
  OSStatus status = TISRegisterInputSource((__bridge CFURLRef)url);
  printf("register %s: %d\n", path.fileSystemRepresentation, (int)status);
  return status == noErr ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int DisableInputSources(NSArray<NSString *> *identifiers) {
  NSSet<NSString *> *targets = [NSSet setWithArray:identifiers];
  if (!SelectSafeFallbackIfNeeded(targets)) {
    fprintf(stderr, "could not select a safe keyboard-layout fallback\n");
    return EXIT_FAILURE;
  }

  BOOL succeeded = YES;
  // Callers pass child modes first and the mode-enabled parent last, which is
  // the order required to remove a whole input-method family cleanly.
  for (NSString *identifier in identifiers) {
    TISInputSourceRef source = FindInputSource(identifier);
    if (!source) {
      printf("source not present: %s\n", identifier.UTF8String);
      continue;
    }
    if (!InputSourceEnabled(source)) {
      printf("source already disabled: %s\n", identifier.UTF8String);
      CFRelease(source);
      continue;
    }
    OSStatus status = TISDisableInputSource(source);
    printf("disable %s: %d\n", identifier.UTF8String, (int)status);
    succeeded = succeeded && status == noErr;
    CFRelease(source);
  }
  return succeeded ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int PrintStatus(NSArray<NSString *> *identifiers) {
  for (NSString *identifier in identifiers) {
    TISInputSourceRef source = FindInputSource(identifier);
    if (!source) {
      printf("%s missing\n", identifier.UTF8String);
    } else {
      printf("%s enabled=%s\n", identifier.UTF8String,
             InputSourceEnabled(source) ? "true" : "false");
      CFRelease(source);
    }
  }
  return EXIT_SUCCESS;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc < 3) {
      fprintf(stderr, "usage: input-source-migrator register <app> | disable/status <id...>\n");
      return EXIT_FAILURE;
    }
    NSString *command = [NSString stringWithUTF8String:argv[1]];
    if ([command isEqualToString:@"register"] && argc == 3) {
      return RegisterBundle([NSString stringWithUTF8String:argv[2]]);
    }

    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (int index = 2; index < argc; ++index) {
      [arguments addObject:[NSString stringWithUTF8String:argv[index]]];
    }
    if ([command isEqualToString:@"disable"]) {
      return DisableInputSources(arguments);
    }
    if ([command isEqualToString:@"status"]) {
      return PrintStatus(arguments);
    }
    fprintf(stderr, "unknown command: %s\n", command.UTF8String);
    return EXIT_FAILURE;
  }
}
