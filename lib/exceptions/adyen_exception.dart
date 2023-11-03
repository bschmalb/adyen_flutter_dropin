import 'package:adyen_flutter_dropin/enums/adyen_error.dart';

class AdyenException implements Exception {
  AdyenError error;
  String? message = 'Something went wrong';

  AdyenException(this.error, this.message);
}
