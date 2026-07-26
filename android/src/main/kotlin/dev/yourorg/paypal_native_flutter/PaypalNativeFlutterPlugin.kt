package dev.yourorg.paypal_native_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import com.paypal.android.cardpayments.*
import com.paypal.android.cardpayments.threedsecure.SCA
import com.paypal.android.corepayments.Address
import com.paypal.android.corepayments.CoreConfig
import com.paypal.android.corepayments.Environment
import com.paypal.android.corepayments.PayPalSDKError
import com.paypal.android.paypalwebpayments.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

class PaypalNativeFlutterPlugin :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, NewIntentListener {

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var coreConfig: CoreConfig? = null
    private var returnUrl: String? = null
    private var cardClient: CardClient? = null
    private var payPalClient: PayPalWebCheckoutClient? = null

    private var pendingResult: Result? = null

    private val prefs: SharedPreferences
        get() = appContext.getSharedPreferences("paypal_native_flutter", Context.MODE_PRIVATE)

    private companion object {
        const val KEY_FLOW = "pending_flow"
        const val KEY_ORDER_ID = "pending_order_id"
        const val KEY_CARD_STATE = "card_instance_state"
        const val KEY_PAYPAL_STATE = "paypal_instance_state"
    }

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        appContext = b.applicationContext
        channel = MethodChannel(b.binaryMessenger, "paypal_native_flutter")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        activity = b.activity
        activityBinding = b
        b.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
        onAttachedToActivity(b)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> init(call, result)
            "approveOrderWithCard" -> approveOrderWithCard(call, result)
            "approveOrderWithPayPal" -> approveOrderWithPayPal(call, result)
            "recoverPendingPayment" -> recoverPendingPayment(result)
            else -> result.notImplemented()
        }
    }

    private fun init(call: MethodCall, result: Result) {
        val clientId = call.argument<String>("clientId")!!
        val env = if (call.argument<String>("environment") == "live")
            Environment.LIVE else Environment.SANDBOX
        returnUrl = call.argument<String>("returnUrl")
        if (returnUrl.isNullOrBlank()) {
            result.error("INIT_ERROR",
                "returnUrl is required on Android (deep link for 3DS/PayPal return).", null)
            return
        }
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Plugin not attached to an Activity.", null)
            return
        }
        coreConfig = CoreConfig(clientId, environment = env)
        cardClient = CardClient(appContext, coreConfig!!)
        payPalClient = PayPalWebCheckoutClient(act, coreConfig!!, urlScheme(returnUrl!!))

        prefs.getString(KEY_CARD_STATE, null)?.let { cardClient?.restore(it) }
        prefs.getString(KEY_PAYPAL_STATE, null)?.let { payPalClient?.restore(it) }
        act.intent?.let { tryFinish(it) }

        result.success(null)
    }

    private fun urlScheme(url: String) = url.substringBefore("://")

    private fun approveOrderWithCard(call: MethodCall, result: Result) {
        val client = cardClient
            ?: return result.error("NOT_INITIALIZED", "Call init() first.", null)
        if (pendingResult != null || hasPersistedPending())
            return result.error("BUSY",
                "A payment flow is in progress. Call recoverPendingPayment() if recovering from a restart.", null)

        val cardMap = call.argument<Map<String, Any?>>("card")!!
        val billing = (cardMap["billingAddress"] as? Map<*, *>)?.let {
            Address(
                streetAddress = it["streetAddress"] as? String,
                extendedAddress = it["extendedAddress"] as? String,
                locality = it["locality"] as? String,
                region = it["region"] as? String,
                postalCode = it["postalCode"] as? String,
                countryCode = it["countryCode"] as? String ?: ""
            )
        }
        val card = Card(
            number = cardMap["number"] as String,
            expirationMonth = cardMap["expirationMonth"] as String,
            expirationYear = cardMap["expirationYear"] as String,
            securityCode = cardMap["securityCode"] as String,
            cardholderName = cardMap["cardholderName"] as? String,
            billingAddress = billing
        )
        val sca = if (call.argument<String>("sca") == "scaAlways")
            SCA.SCA_ALWAYS else SCA.SCA_WHEN_REQUIRED
        val orderId = call.argument<String>("orderId")!!
        val request = CardRequest(orderId, card, returnUrl!!, sca)

        pendingResult = result
        persistPending("card", orderId)

        client.approveOrder(request) { approveResult ->
            when (approveResult) {
                is CardApproveOrderResult.Success -> finishSuccess(
                    orderId = approveResult.orderId,
                    status = approveResult.status?.toString(),
                    threeDS = approveResult.didAttemptThreeDSecureAuthentication
                )
                is CardApproveOrderResult.Failure ->
                    finishError("SDK_ERROR", approveResult.error)
                is CardApproveOrderResult.AuthorizationRequired -> {
                    val a = activity ?: return@approveOrder finishErrorMsg(
                        "NO_ACTIVITY", "Activity lost before 3DS challenge.")
                    when (val p = client.presentAuthChallenge(a, approveResult.authChallenge)) {
                        is CardPresentAuthChallengeResult.Success ->
                            prefs.edit().putString(KEY_CARD_STATE, client.instanceState).apply()
                        is CardPresentAuthChallengeResult.Failure ->
                            finishError("3DS_LAUNCH_ERROR", p.error)
                    }
                }
            }
        }
    }

    private fun approveOrderWithPayPal(call: MethodCall, result: Result) {
        val client = payPalClient
            ?: return result.error("NOT_INITIALIZED", "Call init() first.", null)
        val act = activity ?: return result.error("NO_ACTIVITY", "No activity.", null)
        if (pendingResult != null || hasPersistedPending())
            return result.error("BUSY",
                "A payment flow is in progress. Call recoverPendingPayment() if recovering from a restart.", null)

        val funding = when (call.argument<String>("fundingSource")) {
            "payLater" -> PayPalWebCheckoutFundingSource.PAY_LATER
            "credit" -> PayPalWebCheckoutFundingSource.PAYPAL_CREDIT
            else -> PayPalWebCheckoutFundingSource.PAYPAL
        }
        val orderId = call.argument<String>("orderId")!!
        val request = PayPalWebCheckoutRequest(orderId, fundingSource = funding)

        pendingResult = result
        persistPending("paypal", orderId)

        client.start(act, request) { startResult ->
            when (startResult) {
                is PayPalPresentAuthChallengeResult.Success ->
                    prefs.edit().putString(KEY_PAYPAL_STATE, client.instanceState).apply()
                is PayPalPresentAuthChallengeResult.Failure ->
                    finishError("LAUNCH_ERROR", startResult.error)
            }
        }
    }

    override fun onNewIntent(intent: Intent): Boolean = tryFinish(intent)

    private fun tryFinish(intent: Intent): Boolean {
        when (prefs.getString(KEY_FLOW, null)) {
            "card" -> {
                when (val r = cardClient?.finishApproveOrder(intent)) {
                    is CardFinishApproveOrderResult.Success -> finishSuccess(
                        orderId = r.orderId,
                        status = r.status?.toString(),
                        threeDS = r.didAttemptThreeDSecureAuthentication)
                    is CardFinishApproveOrderResult.Failure -> finishError("SDK_ERROR", r.error)
                    is CardFinishApproveOrderResult.Canceled -> finishCanceled()
                    else -> return false
                }
            }
            "paypal" -> {
                when (val r = payPalClient?.finishStart(intent)) {
                    is PayPalWebCheckoutFinishStartResult.Success -> finishSuccess(
                        orderId = r.orderId ?: "", payerId = r.payerId)
                    is PayPalWebCheckoutFinishStartResult.Failure -> finishError("SDK_ERROR", r.error)
                    is PayPalWebCheckoutFinishStartResult.Canceled -> finishCanceled()
                    else -> return false
                }
            }
            else -> return false
        }
        return true
    }

    private fun recoverPendingPayment(result: Result) {
        val flow = prefs.getString(KEY_FLOW, null)
        val orderId = prefs.getString(KEY_ORDER_ID, null)
        if (flow == null || orderId == null) {
            result.success(null)
            return
        }
        clearPersisted()
        result.success(mapOf("orderId" to orderId, "flow" to flow))
    }

    private fun finishSuccess(
        orderId: String, payerId: String? = null,
        status: String? = null, threeDS: Boolean = false
    ) {
        pendingResult?.success(mapOf(
            "orderId" to orderId,
            "payerId" to payerId,
            "status" to status,
            "didAttemptThreeDSecure" to threeDS,
        ))
        clearAll()
    }

    private fun finishError(code: String, error: PayPalSDKError?) {
        pendingResult?.error(code,
            error?.errorDescription ?: "Unknown PayPal SDK error", error?.code)
        clearAll()
    }

    private fun finishErrorMsg(code: String, msg: String) {
        pendingResult?.error(code, msg, null); clearAll()
    }

    private fun finishCanceled() {
        pendingResult?.error("CANCELED", "Buyer canceled the flow.", null)
        clearAll()
    }

    private fun persistPending(flow: String, orderId: String) {
        prefs.edit().putString(KEY_FLOW, flow).putString(KEY_ORDER_ID, orderId).apply()
    }

    private fun hasPersistedPending() = prefs.getString(KEY_FLOW, null) != null

    private fun clearPersisted() {
        prefs.edit()
            .remove(KEY_FLOW).remove(KEY_ORDER_ID)
            .remove(KEY_CARD_STATE).remove(KEY_PAYPAL_STATE)
            .apply()
    }

    private fun clearAll() {
        pendingResult = null
        clearPersisted()
    }
}
