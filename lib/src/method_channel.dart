import 'package:flutter/services.dart';
import 'models.dart';

class PaypalNativeFlutter {
  PaypalNativeFlutter._();

  static const MethodChannel _channel = MethodChannel('paypal_native_flutter');

  static bool _initialized = false;

  /// [clientId] is your PUBLIC PayPal client ID — safe to ship in the app.
  /// Orders are created on your server; this plugin never sees your secret.
  ///
  /// [returnUrl] (Android only, required there) must match the deep links
  /// registered in your AndroidManifest, e.g. "com.example.app://paypal-return".
  static Future<void> init({
    required String clientId,
    required PayPalEnvironment environment,
    String? returnUrl,
  }) async {
    await _channel.invokeMethod<void>('init', {
      'clientId': clientId,
      'environment': environment.name,
      if (returnUrl != null) 'returnUrl': returnUrl,
    });
    _initialized = true;
  }

  /// Approves [orderId] (created by your backend via Orders v2) with card
  /// details collected by your own Flutter UI. Handles 3DS natively.
  /// On success, tell your backend to capture/authorize the order.
  static Future<PayPalPaymentSourceApproval> approveOrderWithCard({
    required String orderId,
    required PayPalCard card,
    Sca sca = Sca.scaWhenRequired,
  }) async {
    _assertInit();
    try {
      final result = await _channel
          .invokeMapMethod<dynamic, dynamic>('approveOrderWithCard', {
        'orderId': orderId,
        'card': card.toMap(),
        'sca': sca.name,
      });
      return PayPalPaymentSourceApproval.fromMap(result!);
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  /// Launches the PayPal web checkout (browser/custom-tab) for [orderId].
  static Future<PayPalPaymentSourceApproval> approveOrderWithPayPal({
    required String orderId,
    PayPalFundingSource fundingSource = PayPalFundingSource.paypal,
  }) async {
    _assertInit();
    try {
      final result = await _channel
          .invokeMapMethod<dynamic, dynamic>('approveOrderWithPayPal', {
        'orderId': orderId,
        'fundingSource': fundingSource.name,
      });
      return PayPalPaymentSourceApproval.fromMap(result!);
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  /// Call once at app startup, AFTER init() (Android). If the app was killed
  /// while a PayPal/3DS flow was open, this returns the orphaned order so you
  /// can reconcile its real status with your backend
  /// (GET /v2/checkout/orders/{id}). Returns null when nothing was pending.
  static Future<PendingPaymentRecovery?> recoverPendingPayment() async {
    final map = await _channel
        .invokeMapMethod<dynamic, dynamic>('recoverPendingPayment');
    if (map == null) return null;
    return PendingPaymentRecovery(
      orderId: map['orderId'] as String,
      flow: map['flow'] as String,
    );
  }

  static void _assertInit() {
    if (!_initialized) {
      throw StateError(
          'PaypalNativeFlutter.init() must be called before payments.');
    }
  }

  static Exception _translate(PlatformException e) {
    if (e.code == 'CANCELED') {
      return PayPalCanceledException(e.message ?? 'Buyer canceled.');
    }
    return PayPalException(e.code, e.message ?? 'Unknown error', e.details);
  }
}
