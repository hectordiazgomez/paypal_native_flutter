# paypal_native_flutter

Unofficial Flutter bindings for PayPal's official [paypal-android](https://github.com/paypal/paypal-android) and [paypal-ios](https://github.com/paypal/paypal-ios) SDKs.

Build a **fully native card checkout with your own Flutter UI** — no webview for card entry — plus SDK-managed PayPal web checkout. Think of it as what `flutter_stripe` is for Stripe, but for PayPal.

> This package is not affiliated with or endorsed by PayPal. "PayPal" is a trademark of PayPal, Inc.

## Features

- **Native card payments**: collect card details in your own Flutter widgets and approve orders through PayPal's `CardPayments` module. 3D Secure handled natively.
- **PayPal web checkout**: launches PayPal's browser-based flow (PayPal deprecated their native paysheet in 2024 — the browser flow is the officially supported path) and returns the result as a single Dart `Future`.
- **Server-first security**: the plugin takes only your **public** client ID and a backend-created order ID. Your PayPal secret never touches the app — by design, there is no parameter for it.
- **Android process-death recovery**: `recoverPendingPayment()` returns orders orphaned when Android kills your app mid-flow.
- Direct PayPal integration — no Braintree gateway or merchant account needed. (PayPal's own Android SDK internally uses a Braintree browser-switch library; that's an implementation detail of PayPal's SDK, not a gateway integration.)

## Requirements

- **Android**: minSdk 23, Kotlin, `launchMode="singleTop"` on your MainActivity
- **iOS**: 14.0+
- A PayPal Business account **approved for Advanced Credit and Debit Card Payments** (card fields will fail without this — check your account in the PayPal Developer Dashboard)
- A backend that creates and captures orders via [Orders v2](https://developer.paypal.com/docs/api/orders/v2/)

## How it works

Payment happens in three steps — this is the same architecture Stripe and every serious processor uses:

1. **Your backend creates the order** (Orders v2, with your secret) and returns the `orderId` to the app. Amounts are decided server-side — never trust a client-supplied amount.
2. **The app approves it** with this plugin — native card fields or the PayPal button.
3. **Your backend captures the order.** Approval is NOT payment: money moves only on capture, and capture can still fail. Mark orders paid only on confirmed capture (webhook or order-status check). Use a unique `PayPal-Request-Id` header for idempotent capture retries.

## Usage

```dart
import 'package:paypal_native_flutter/paypal_native_flutter.dart';

// Once at startup:
await PaypalNativeFlutter.init(
  clientId: 'YOUR_PUBLIC_CLIENT_ID',
  environment: PayPalEnvironment.sandbox,
  returnUrl: 'com.example.myapp://paypal-return', // Android only
);

// Android: check for payments orphaned by process death:
final pending = await PaypalNativeFlutter.recoverPendingPayment();
if (pending != null) {
  // Ask your backend for the real status of pending.orderId
}

// Card payment with your own UI:
try {
  final approval = await PaypalNativeFlutter.approveOrderWithCard(
    orderId: orderIdFromYourBackend,
    card: PayPalCard(
      number: number, expirationMonth: '09', expirationYear: '2028',
      securityCode: cvv,
      billingAddress: PayPalBillingAddress(postalCode: '94103', countryCode: 'US'),
    ),
  );
  await yourBackend.captureOrder(approval.orderId); // money moves HERE
} on PayPalCanceledException {
  // buyer backed out
} on PayPalException catch (e) {
  // e.code, e.message
}

// Or the PayPal button:
final approval = await PaypalNativeFlutter.approveOrderWithPayPal(
  orderId: orderIdFromYourBackend,
);
```

## Android setup

1. `minSdk 23` in `android/app/build.gradle`.
2. `android:launchMode="singleTop"` on your MainActivity (Flutter's default).
3. Add BOTH deep-link filters inside your MainActivity's `<activity>` — the second path is hardcoded inside PayPal's SDK:

```xml
<!-- Card / 3DS return -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.myapp" android:host="paypal-return" />
</intent-filter>
<!-- PayPal web checkout return -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.example.myapp"
          android:host="x-callback-url"
          android:pathPrefix="/paypal-sdk/paypal-checkout" />
</intent-filter>
```

The scheme must match the `returnUrl` you pass to `init()`.

## iOS setup

Set `platform :ios, '14.0'` in your Podfile and iOS deployment target 14.0 in Xcode.

## Testing

Use sandbox credentials from [developer.paypal.com](https://developer.paypal.com). Test card: `4111 1111 1111 1111`, any future expiry, any CVV. Create test orders with the Orders v2 API. Each order can be approved only once.

## Important disclaimers

**PCI**: This integration handles raw cardholder data in the mobile application — card fields exist as Dart strings, cross the Flutter platform channel, and are passed to PayPal's SDK. This package makes no claim about your SAQ classification or PCI scope; merchants are responsible for determining and satisfying their applicable PCI DSS requirements. Never include card fields in crash reports, analytics, logs, or persisted state.

**Risk & liability**: PayPal processes payments and runs automatic fraud detection and 3DS, but responsibility for chargebacks, Seller Protection eligibility, and taxes remains with the merchant per your PayPal account terms. This is a payment processor integration, not a merchant-of-record service.

**App store policies**: Payment rules for digital goods depend on platform, storefront, user region, and program enrollment, and have been changing rapidly. Verify current Apple App Store and Google Play requirements before enabling this package for digital content. Physical goods and real-world services are generally unaffected.

## Versioning note

This package pins exact PayPal SDK versions (`paypal-android 2.3.0`, `paypal-ios 2.0.1`) because PayPal has shipped breaking changes between minor versions. SDK bumps will be released as new package versions.

## License

MIT
