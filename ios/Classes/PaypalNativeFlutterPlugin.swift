import Flutter
import UIKit
import PayPal

public class PaypalNativeFlutterPlugin: NSObject, FlutterPlugin {

    private var coreConfig: CoreConfig?
    private var cardClient: CardClient?
    private var webClient: PayPalWebCheckoutClient?
    private var busy = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "paypal_native_flutter",
            binaryMessenger: registrar.messenger())
        let instance = PaypalNativeFlutterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            initSdk(call, result)
        case "approveOrderWithCard":
            approveOrderWithCard(call, result)
        case "approveOrderWithPayPal":
            approveOrderWithPayPal(call, result)
        case "recoverPendingPayment":
            result(nil) // iOS runs flows in-process; Android-style recovery not needed
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initSdk(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let clientId = args["clientId"] as? String else {
            result(FlutterError(code: "INIT_ERROR", message: "clientId required", details: nil))
            return
        }
        let env: Environment = (args["environment"] as? String) == "live" ? .live : .sandbox
        let config = CoreConfig(clientID: clientId, environment: env)
        coreConfig = config
        cardClient = CardClient(config: config)
        webClient = PayPalWebCheckoutClient(config: config)
        result(nil)
    }

    private func approveOrderWithCard(_ call: FlutterMethodCall,
                                      _ result: @escaping FlutterResult) {
        guard let client = cardClient else {
            return result(FlutterError(code: "NOT_INITIALIZED",
                                       message: "Call init() first.", details: nil))
        }
        guard !busy else {
            return result(FlutterError(code: "BUSY",
                                       message: "A payment flow is already in progress.",
                                       details: nil))
        }
        guard let args = call.arguments as? [String: Any],
              let orderId = args["orderId"] as? String,
              let cardMap = args["card"] as? [String: Any],
              let number = cardMap["number"] as? String,
              let expMonth = cardMap["expirationMonth"] as? String,
              let expYear = cardMap["expirationYear"] as? String,
              let cvv = cardMap["securityCode"] as? String else {
            return result(FlutterError(code: "BAD_ARGS",
                                       message: "Missing card fields.", details: nil))
        }

        var billingAddress: Address? = nil
        if let b = cardMap["billingAddress"] as? [String: Any] {
            billingAddress = Address(
                addressLine1: b["streetAddress"] as? String,
                addressLine2: b["extendedAddress"] as? String,
                locality: b["locality"] as? String,
                region: b["region"] as? String,
                postalCode: b["postalCode"] as? String,
                countryCode: b["countryCode"] as? String ?? ""
            )
        }

        let card = Card(
            number: number,
            expirationMonth: expMonth,
            expirationYear: expYear,
            securityCode: cvv,
            cardholderName: cardMap["cardholderName"] as? String,
            billingAddress: billingAddress
        )
        let sca: SCA = (args["sca"] as? String) == "scaAlways" ? .scaAlways : .scaWhenRequired
        let request = CardRequest(orderID: orderId, card: card, sca: sca)

        busy = true
        client.approveOrder(request: request) { [weak self] approveResult in
            DispatchQueue.main.async {
                self?.busy = false
                switch approveResult {
                case .success(let cardResult):
                    result([
                        "orderId": cardResult.orderID,
                        "status": cardResult.status as Any,
                        "didAttemptThreeDSecure":
                            cardResult.didAttemptThreeDSecureAuthentication,
                    ])
                case .failure(let error):
                    if CardError.isThreeDSecureCanceled(error) {
                        result(FlutterError(code: "CANCELED",
                                            message: "Buyer canceled 3DS.",
                                            details: nil))
                    } else {
                        result(FlutterError(code: "SDK_ERROR",
                                            message: error.localizedDescription,
                                            details: error.code))
                    }
                }
            }
        }
    }

    private func approveOrderWithPayPal(_ call: FlutterMethodCall,
                                        _ result: @escaping FlutterResult) {
        guard let client = webClient else {
            return result(FlutterError(code: "NOT_INITIALIZED",
                                       message: "Call init() first.", details: nil))
        }
        guard !busy else {
            return result(FlutterError(code: "BUSY",
                                       message: "A payment flow is already in progress.",
                                       details: nil))
        }
        guard let args = call.arguments as? [String: Any],
              let orderId = args["orderId"] as? String else {
            return result(FlutterError(code: "BAD_ARGS",
                                       message: "orderId required.", details: nil))
        }
        let funding: PayPalWebCheckoutFundingSource
        switch args["fundingSource"] as? String {
        case "payLater": funding = .paylater
        case "credit": funding = .paypalCredit
        default: funding = .paypal
        }
        let request = PayPalWebCheckoutRequest(orderID: orderId, fundingSource: funding)

        busy = true
        client.start(request: request) { [weak self] checkoutResult in
            DispatchQueue.main.async {
                self?.busy = false
                switch checkoutResult {
                case .success(let checkout):
                    result([
                        "orderId": checkout.orderID,
                        "payerId": checkout.payerID,
                    ])
                case .failure(let error):
                    if PayPalError.isCheckoutCanceled(error) {
                        result(FlutterError(code: "CANCELED",
                                            message: "Buyer canceled PayPal checkout.",
                                            details: nil))
                    } else {
                        result(FlutterError(code: "SDK_ERROR",
                                            message: error.localizedDescription,
                                            details: error.code))
                    }
                }
            }
        }
    }
}
