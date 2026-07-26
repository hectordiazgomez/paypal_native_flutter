/// PayPal environment.
enum PayPalEnvironment { sandbox, live }

/// Strong Customer Authentication behavior for card payments (3DS).
enum Sca { scaWhenRequired, scaAlways }

/// Funding source for the PayPal web checkout flow.
enum PayPalFundingSource { paypal, payLater, credit }

/// Card details collected by YOUR native Flutter UI.
/// Never log them, never persist them, never send them to your own server.
class PayPalCard {
  const PayPalCard({
    required this.number,
    required this.expirationMonth,
    required this.expirationYear,
    required this.securityCode,
    this.cardholderName,
    this.billingAddress,
  });

  final String number;

  /// "01".."12"
  final String expirationMonth;

  /// Four digits, e.g. "2028"
  final String expirationYear;
  final String securityCode;
  final String? cardholderName;

  /// Optional but recommended: reduces the probability of a 3DS challenge.
  final PayPalBillingAddress? billingAddress;

  Map<String, dynamic> toMap() => {
        'number': number,
        'expirationMonth': expirationMonth,
        'expirationYear': expirationYear,
        'securityCode': securityCode,
        if (cardholderName != null) 'cardholderName': cardholderName,
        if (billingAddress != null) 'billingAddress': billingAddress!.toMap(),
      };
}

class PayPalBillingAddress {
  const PayPalBillingAddress({
    this.streetAddress,
    this.extendedAddress,
    this.locality,
    this.region,
    this.postalCode,
    this.countryCode,
  });

  final String? streetAddress;
  final String? extendedAddress;
  final String? locality; // city
  final String? region; // state/province
  final String? postalCode;
  final String? countryCode; // ISO-3166-1 alpha-2

  Map<String, dynamic> toMap() => {
        if (streetAddress != null) 'streetAddress': streetAddress,
        if (extendedAddress != null) 'extendedAddress': extendedAddress,
        if (locality != null) 'locality': locality,
        if (region != null) 'region': region,
        if (postalCode != null) 'postalCode': postalCode,
        if (countryCode != null) 'countryCode': countryCode,
      };
}

/// Approval of a payment source for an order. This is NOT payment success.
/// Money moves only when your backend captures or authorizes the order.
/// Mark orders paid only on confirmed capture (webhook or order-status check).
class PayPalPaymentSourceApproval {
  const PayPalPaymentSourceApproval({
    required this.orderId,
    this.payerId,
    this.status,
    this.didAttemptThreeDSecure = false,
  });

  final String orderId;
  final String? payerId; // set for PayPal web checkout flow
  final String? status;
  final bool didAttemptThreeDSecure;

  factory PayPalPaymentSourceApproval.fromMap(Map<dynamic, dynamic> map) =>
      PayPalPaymentSourceApproval(
        orderId: map['orderId'] as String,
        payerId: map['payerId'] as String?,
        status: map['status'] as String?,
        didAttemptThreeDSecure:
            (map['didAttemptThreeDSecure'] as bool?) ?? false,
      );
}

/// Returned by recoverPendingPayment() when the app was killed mid-flow.
class PendingPaymentRecovery {
  const PendingPaymentRecovery({required this.orderId, required this.flow});
  final String orderId;
  final String flow; // 'card' | 'paypal'
}

/// Thrown when the buyer cancels (3DS sheet or PayPal browser flow).
class PayPalCanceledException implements Exception {
  const PayPalCanceledException([this.message = 'Buyer canceled the flow.']);
  final String message;
  @override
  String toString() => 'PayPalCanceledException: $message';
}

/// Any non-cancellation failure from the native SDKs.
class PayPalException implements Exception {
  const PayPalException(this.code, this.message, [this.details]);
  final String code;
  final String message;
  final Object? details;
  @override
  String toString() => 'PayPalException($code): $message';
}
