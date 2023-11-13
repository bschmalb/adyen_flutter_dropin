#import "FlutterAdyenPlugin.h"
#import <adyen_flutter_dropin/adyen_flutter_dropin-Swift.h>

@implementation FlutterAdyenPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    [SwiftFlutterAdyenPlugin registerWithRegistrar:registrar];
}
@end
