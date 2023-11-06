import 'package:adyen_flutter_dropin/enums/adyen_error.dart';

/// The exception thrown when an error occurs in the Adyen Flutter Drop-in.
class AdyenException implements Exception {
  AdyenError error;
  String? message = 'Something went wrong';

  AdyenException(this.error, this.message);
}
