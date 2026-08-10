#import "ObjCExceptionGuard.h"

NSException *_Nullable CardCoreCatchException(void (NS_NOESCAPE ^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  }
  return nil;
}
