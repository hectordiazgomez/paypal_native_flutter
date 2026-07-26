import 'package:flutter/material.dart';
import 'package:paypal_native_flutter/paypal_native_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CheckoutDemo());
  }
}

class CheckoutDemo extends StatefulWidget {
  const CheckoutDemo({super.key});

  @override
  State<CheckoutDemo> createState() => _CheckoutDemoState();
}

class _CheckoutDemoState extends State<CheckoutDemo> {
  String _status = 'Not initialized';
  bool _ready = false;

  // Card entry controllers — this is YOUR native UI, style it however you want.
  final _number = TextEditingController(text: '4111111111111111'); // sandbox test card
  final _expMonth = TextEditingController(text: '01');
  final _expYear = TextEditingController(text: '2030');
  final _cvv = TextEditingController(text: '123');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await PaypalNativeFlutter.init(
        // TODO: replace with your sandbox client ID from developer.paypal.com
        clientId: 'BAAjPPbk50JM-b4FCAyUWw9CG4e_fKnKu-mHaazD3D6KGYKCeJrrpE4zO8j4lwH0F2byLUa46cY29a733I',
        environment: PayPalEnvironment.sandbox,
        returnUrl: 'dev.yourorg.paypalnativeflutterexample://paypal-return',
      );
      // Check for a payment orphaned by process death (Android):
      final pending = await PaypalNativeFlutter.recoverPendingPayment();
      setState(() {
        _ready = true;
        _status = pending == null
            ? 'Initialized. Ready.'
            : 'Recovered pending order ${pending.orderId} — '
              'check its status with your backend.';
      });
    } catch (e) {
      setState(() => _status = 'Init failed: $e');
    }
  }

  Future<void> _payWithCard() async {
    // In a real app this orderId comes from YOUR BACKEND (Orders v2).
    // For a quick sandbox smoke test you can create one manually with curl
    // and paste it here — see the README.
    const orderId = '8HL57119LM2626501';
    setState(() => _status = 'Approving with card…');
    try {
      final approval = await PaypalNativeFlutter.approveOrderWithCard(
        orderId: orderId,
        card: PayPalCard(
          number: _number.text,
          expirationMonth: _expMonth.text,
          expirationYear: _expYear.text,
          securityCode: _cvv.text,
        ),
      );
      setState(() => _status =
          'APPROVED order ${approval.orderId} (3DS: ${approval.didAttemptThreeDSecure}). '
          'Now your backend must CAPTURE it — approval is not payment.');
    } on PayPalCanceledException {
      setState(() => _status = 'Buyer canceled.');
    } on PayPalException catch (e) {
      setState(() => _status = 'Error ${e.code}: ${e.message}');
    }
  }

  Future<void> _payWithPayPal() async {
    const orderId = '8HL57119LM2626501';
    setState(() => _status = 'Launching PayPal…');
    try {
      final approval = await PaypalNativeFlutter.approveOrderWithPayPal(
        orderId: orderId,
      );
      setState(() => _status =
          'APPROVED order ${approval.orderId}, payer ${approval.payerId}. '
          'Now your backend must CAPTURE it.');
    } on PayPalCanceledException {
      setState(() => _status = 'Buyer canceled.');
    } on PayPalException catch (e) {
      setState(() => _status = 'Error ${e.code}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('paypal_native_flutter demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 24),
            TextField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Card number'),
              keyboardType: TextInputType.number,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _expMonth,
                    decoration: const InputDecoration(labelText: 'MM'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _expYear,
                    decoration: const InputDecoration(labelText: 'YYYY'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cvv,
                    decoration: const InputDecoration(labelText: 'CVV'),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ready ? _payWithCard : null,
              child: const Text('Pay with card (native)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _ready ? _payWithPayPal : null,
              child: const Text('Pay with PayPal'),
            ),
          ],
        ),
      ),
    );
  }
}
