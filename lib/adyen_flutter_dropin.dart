import 'dart:async';

import 'package:adyen_flutter_dropin/enums/adyen_error.dart';
import 'package:adyen_flutter_dropin/enums/adyen_response.dart';
import 'package:adyen_flutter_dropin/exceptions/adyen_exception.dart';
import 'package:flutter/services.dart';

class FlutterAdyen {
  static const MethodChannel _channel = const MethodChannel('flutter_adyen');

  static Future<AdyenResponse> openDropIn({
    /// The payment methods to be used in the payment.
    paymentMethods,

    /// The base URL of your back-end server.
    /// This is used to retrieve the payment methods and make payments.
    /// Example: https://your-company.com/api/ or https://your-company.com/
    required String baseUrl,

    /// The client key used to communicate with the Adyen API.
    required String clientKey,

    /// The line item to be used in the payment.
    /// This contains information about the item purchased.
    lineItem,
    required String locale,

    /// The amount of the payment in cents.
    required String amount,
    required String currency,

    /// The URL the backend will redirect to after a payment result is received.
    /// This URL needs to be able to handle the payment result and return to the app.
    /// The scheme of the URL needs to be registered in the app's Info.plist under URL types.
    /// adyencheckout://com.example.app/payment
    required String returnUrl,

    /// The shopper reference to be used in the payment.
    /// This can be the user ID, or any other unique string that identifies the user.
    required String shopperReference,

    /// The additional data to be used in the payment.
    /// This can be used to send any additional data to the server.
    required Map<String, String> additionalData,

    /// The apple pay pay merchant id to be used in the payment for apple pay.
    String? applePayMerchantId,

    /// The apple pay pay merchant name that is shown on the pay modal.
    String? applePayMerchantName,

    /// The google pay merchant id to be used in the payment for google pay.
    String? googlePayMerchantId,

    ///
    Map<String, String>? headers,

    /// The environment to be used in the payment.
    /// Only currently available environments are TEST and LIVE_EUROPE, LIVE_US, LIVE_AUSTRALIA.
    environment = 'TEST',
  }) async {
    Map<String, dynamic> args = {
      'paymentMethods': paymentMethods,
      'additionalData': additionalData,
      'baseUrl': baseUrl,
      'clientKey': clientKey,
      'amount': amount,
      'locale': locale,
      'currency': currency,
      'lineItem': lineItem,
      'returnUrl': returnUrl,
      'environment': environment,
      'shopperReference': shopperReference,
      'headers': headers,
      'googlePayMerchantId': googlePayMerchantId,
      'applePayMerchantId': applePayMerchantId,
      'applePayMerchantName': applePayMerchantName,
    };

    final response = await _channel.invokeMethod<String>('openDropIn', args);

    switch (response) {
      case 'PAYMENT_ERROR':
        throw AdyenException(AdyenError.PAYMENT_ERROR, response);
      case 'PAYMENT_CANCELLED':
        throw AdyenException(AdyenError.PAYMENT_CANCELLED, response);
    }

    return AdyenResponse.values.firstWhere((element) {
      return element.name.toLowerCase() == response?.toLowerCase();
    }, orElse: () => throw AdyenException(AdyenError.PAYMENT_ERROR, response));
  }
}
