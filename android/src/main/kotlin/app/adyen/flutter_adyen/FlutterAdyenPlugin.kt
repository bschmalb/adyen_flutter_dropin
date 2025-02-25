package app.adyen.flutter_adyen

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.util.Log
import com.adyen.checkout.card.CardConfiguration
import com.adyen.checkout.components.model.PaymentMethodsApiResponse
import com.adyen.checkout.components.model.payments.Amount
import com.adyen.checkout.components.model.payments.request.PaymentComponentData
import com.adyen.checkout.components.model.payments.request.PaymentMethodDetails
import com.adyen.checkout.core.api.Environment
import com.adyen.checkout.core.util.LocaleUtil
import com.adyen.checkout.dropin.DropIn
import com.adyen.checkout.dropin.DropInConfiguration
import com.adyen.checkout.dropin.service.DropInService
import com.adyen.checkout.dropin.service.DropInServiceResult
import com.adyen.checkout.googlepay.GooglePayConfiguration
import com.adyen.checkout.redirect.RedirectComponent
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException
import com.google.gson.reflect.TypeToken
import com.squareup.moshi.Moshi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.io.IOException
import java.io.Serializable
import java.util.*
import okhttp3.MediaType
import okhttp3.RequestBody
import org.json.JSONObject

/// Android implementation for the FlutterAdyenPlugin
class FlutterAdyenPlugin :
        MethodCallHandler, PluginRegistry.ActivityResultListener, FlutterPlugin, ActivityAware {

    private var methodChannel: MethodChannel? = null

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    var flutterResult: Result? = null

    companion object {

        const val CHANNEL_NAME = "flutter_adyen"

        /// For v1 embedding
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            FlutterAdyenPlugin().apply {
                onAttachedToEngine(registrar.messenger())
                activity = registrar.activity()
                addActivityResultListener(registrar)
            }
        }
    }

    /// Method that handles the method calls from Flutter
    override fun onMethodCall(call: MethodCall, res: Result) {
        when (call.method) {
            "openDropIn" -> {

                if (activity == null) {
                    res.error("1", "Activity is null", "The activity is probably not attached")
                    return
                }

                val nonNullActivity = activity!!

                Log.i("[Flutter Adyen]", "Opening Drop In")

                /// Get the arguments from the method call
                val additionalData =
                        call.argument<Map<String, String>>("additionalData") ?: emptyMap()
                val paymentMethods = call.argument<String>("paymentMethods")
                val baseUrl = call.argument<String>("baseUrl")
                val clientKey = call.argument<String>("clientKey")
                val amount = call.argument<String>("amount")
                val currency = call.argument<String>("currency")
                val env = call.argument<String>("environment")
                val lineItem = call.argument<Map<String, String>>("lineItem")
                val shopperReference = call.argument<String>("shopperReference")
                val headers = call.argument<Map<String, String>>("headers")
                val googlePayMerchantId = call.argument<String?>("googlePayMerchantId")

                // Retrieve backgroundColor and accentColor arguments
                val backgroundColorValue = call.argument<Int>("backgroundColor")
                val accentColorValue = call.argument<Int>("accentColor")

                // Provide fallback colors if not provided
                val backgroundColor =
                        backgroundColorValue?.let { Color.valueOf(it.toLong()) } ?: Color.WHITE
                val accentColor =
                        accentColorValue?.let { Color.valueOf(it.toLong()) } ?: Color.rgb(0, 0, 0)

                @Suppress("NULLABILITY_MISMATCH_BASED_ON_JAVA_ANNOTATIONS")
                val lineItemString = JSONObject(lineItem).toString()
                val additionalDataString = JSONObject(additionalData).toString()
                val localeString = call.argument<String>("locale") ?: "de_DE"
                val headersString = JSONObject(headers).toString()
                val localeParts = localeString.split("_")
                val countryCode = localeParts.last()
                var locale = Locale(countryCode)

                if (localeParts.size > 1) {
                    locale = Locale(localeParts[0], localeParts[1])
                }

                /// Set the given adyen environment
                val environment =
                        when (env) {
                            "LIVE_US" -> Environment.UNITED_STATES
                            "LIVE_AUSTRALIA" -> Environment.AUSTRALIA
                            "LIVE_EUROPE" -> Environment.EUROPE
                            else -> Environment.TEST
                        }

                /// Try to create the payment methods response from the given json
                try {
                    val jsonObject = JSONObject(paymentMethods ?: "")
                    val paymentMethodsApiResponse =
                            PaymentMethodsApiResponse.SERIALIZER.deserialize(jsonObject)

                    val shopperLocale =
                            if (LocaleUtil.isValidLocale(locale)) locale
                            else LocaleUtil.getLocale(nonNullActivity)
                    val cardConfiguration =
                            CardConfiguration.Builder(nonNullActivity, clientKey!!)
                                    .setHolderNameRequired(true)
                                    .setShopperLocale(shopperLocale)
                                    .setEnvironment(environment)
                                    .build()

                    val sharedPref =
                            nonNullActivity.getSharedPreferences("ADYEN", Context.MODE_PRIVATE)
                    with(sharedPref.edit()) {
                        remove("AdyenResultCode")
                        putString("baseUrl", baseUrl)
                        putString("amount", "$amount")
                        putString("countryCode", countryCode)
                        putString("currency", currency)
                        putString("lineItem", lineItemString)
                        putString("additionalData", additionalDataString)
                        putString("shopperReference", shopperReference)
                        putString("headers", headersString)
                        commit()
                    }

                    /// Create the drop in configuration
                    val dropInConfigurationBuilder =
                            DropInConfiguration.Builder(
                                            nonNullActivity,
                                            AdyenDropinService::class.java,
                                            clientKey
                                    )
                                    .addCardConfiguration(cardConfiguration)
                                    .setShopperLocale(shopperLocale)
                                    .setEnvironment(environment)

                    if (googlePayMerchantId != null) {
                        val googlePayConfiguration =
                                GooglePayConfiguration.Builder(nonNullActivity, clientKey)
                                        .setAmount(getAmount(amount ?: "0", currency ?: "EUR"))
                                        .setEnvironment(environment)
                                        .setMerchantAccount(googlePayMerchantId)
                                        .build()
                        dropInConfigurationBuilder.addGooglePayConfiguration(googlePayConfiguration)
                    }

                    /// Start the drop in and show the UI to the user
                    DropIn.startPayment(
                            nonNullActivity,
                            paymentMethodsApiResponse,
                            dropInConfigurationBuilder.build()
                    )

                    flutterResult = res
                } catch (e: Throwable) {
                    res.error("PAYMENT_ERROR", "${e.printStackTrace()}", "")
                }
            }
            else -> {
                res.notImplemented()
            }
        }
    }

    /// Method that handles the result from the drop in
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (activity == null) return false

        val sharedPref = activity!!.getSharedPreferences("ADYEN", Context.MODE_PRIVATE)
        val storedResultCode = sharedPref.getString("AdyenResultCode", "PAYMENT_CANCELLED")
        flutterResult?.success(storedResultCode)
        flutterResult = null
        return true
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        onAttachedToEngine(binding.binaryMessenger)
    }

    private fun onAttachedToEngine(messenger: BinaryMessenger) {
        this.methodChannel = MethodChannel(messenger, CHANNEL_NAME)
        this.methodChannel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unbindActivityBinding()
        this.methodChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        bindActivityBinding(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unbindActivityBinding()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        bindActivityBinding(binding)
    }

    override fun onDetachedFromActivity() {
        unbindActivityBinding()
    }

    /// Function that binds the activity to the plugin
    private fun bindActivityBinding(binding: ActivityPluginBinding) {
        this.activity = binding.activity
        this.activityBinding = binding
        addActivityResultListener(binding)
    }

    /// Function that unbinds the activity from the plugin
    private fun unbindActivityBinding() {
        activityBinding?.removeActivityResultListener(this)
        this.activity = null
        this.activityBinding = null
    }

    private fun addActivityResultListener(activityBinding: ActivityPluginBinding) {
        activityBinding.addActivityResultListener(this)
    }

    private fun addActivityResultListener(registrar: PluginRegistry.Registrar) {
        registrar.addActivityResultListener(this)
    }
}

@Throws(JsonSyntaxException::class)
inline fun <reified T> Gson.fromJson(json: String): T? =
        fromJson<T>(json, object : TypeToken<T>() {}.type)

class AdyenDropinService : DropInService() {

    /// payments call to initiate the payment with all required data
    override fun makePaymentsCall(paymentComponentJson: JSONObject): DropInServiceResult {
        val sharedPref = getSharedPreferences("ADYEN", Context.MODE_PRIVATE)
        val baseUrl = sharedPref.getString("baseUrl", "UNDEFINED_STR")
        val amount = sharedPref.getString("amount", "UNDEFINED_STR")
        val currency = sharedPref.getString("currency", "UNDEFINED_STR")
        val countryCode = sharedPref.getString("countryCode", "DE")
        val lineItemString = sharedPref.getString("lineItem", "UNDEFINED_STR")
        val additionalDataString = sharedPref.getString("additionalData", "UNDEFINED_STR")
        val uuid: UUID = UUID.randomUUID()
        val reference: String = uuid.toString()
        val shopperReference = sharedPref.getString("shopperReference", null)
        val headersString = sharedPref.getString("headers", null)

        val moshi = Moshi.Builder().build()
        val jsonAdapter = moshi.adapter(LineItem::class.java)
        val lineItem: LineItem? = jsonAdapter.fromJson(lineItemString ?: "")

        val gson = Gson()

        val additionalData =
                gson.fromJson<Map<String, String>>(additionalDataString ?: "") ?: emptyMap()
        val headers = gson.fromJson<Map<String, String>>(headersString ?: "") ?: emptyMap()
        val serializedPaymentComponentData =
                PaymentComponentData.SERIALIZER.deserialize(paymentComponentJson)

        if (serializedPaymentComponentData.paymentMethod == null)
                return DropInServiceResult.Error(errorMessage = "Empty payment data")

        val paymentsRequest =
                createPaymentsRequest(
                        context = this@AdyenDropinService,
                        lineItem,
                        serializedPaymentComponentData,
                        amount = amount ?: "",
                        currency = currency ?: "",
                        reference = reference,
                        shopperReference = shopperReference,
                        countryCode = countryCode ?: "DE",
                        additionalData = additionalData
                )
        val paymentsRequestJson = serializePaymentsRequest(paymentsRequest)

        val requestBody =
                RequestBody.create(
                        MediaType.parse("application/json"),
                        paymentsRequestJson.toString()
                )

        val call = getService(HashMap<String, String>(headers), baseUrl ?: "").payments(requestBody)
        call.request().headers()
        return try {
            val response = call.execute()
            val paymentsResponse = response.body()

            if (response.isSuccessful && paymentsResponse != null) {
                if (paymentsResponse.action != null) {
                    with(sharedPref.edit()) {
                        putString("AdyenResultCode", paymentsResponse.action.toString())
                        commit()
                    }
                    DropInServiceResult.Action(paymentsResponse.action)
                } else {
                    if (paymentsResponse.resultCode != null &&
                                    (paymentsResponse.resultCode == "Authorised" ||
                                            paymentsResponse.resultCode == "Received" ||
                                            paymentsResponse.resultCode == "Pending")
                    ) {
                        with(sharedPref.edit()) {
                            putString("AdyenResultCode", paymentsResponse.resultCode)
                            commit()
                        }
                        DropInServiceResult.Finished(paymentsResponse.resultCode)
                    } else {
                        with(sharedPref.edit()) {
                            putString("AdyenResultCode", paymentsResponse.resultCode ?: "EMPTY")
                            commit()
                        }
                        DropInServiceResult.Finished(paymentsResponse.resultCode ?: "EMPTY")
                    }
                }
            } else {
                with(sharedPref.edit()) {
                    putString("AdyenResultCode", "PAYMENT_ERROR")
                    commit()
                }
                DropInServiceResult.Finished("PAYMENT_ERROR")
            }
        } catch (e: IOException) {
            with(sharedPref.edit()) {
                putString("AdyenResultCode", "PAYMENT_ERROR")
                commit()
            }
            DropInServiceResult.Finished("PAYMENT_ERROR")
        }
    }

    /// payments/details call for further validation of the payment
    override fun makeDetailsCall(actionComponentJson: JSONObject): DropInServiceResult {
        val sharedPref = getSharedPreferences("ADYEN", Context.MODE_PRIVATE)
        val baseUrl = sharedPref.getString("baseUrl", "UNDEFINED_STR")
        val headersString = sharedPref.getString("headers", null)
        val requestBody =
                RequestBody.create(
                        MediaType.parse("application/json"),
                        actionComponentJson.toString()
                )

        val gson = Gson()

        val headers = gson.fromJson<Map<String, String>>(headersString ?: "") ?: emptyMap()

        val call = getService(HashMap<String, String>(headers), baseUrl ?: "").details(requestBody)
        return try {
            val response = call.execute()
            val detailsResponse = response.body()
            if (response.isSuccessful && detailsResponse != null) {
                if (detailsResponse.action != null) {
                    with(sharedPref.edit()) {
                        putString("AdyenResultCode", detailsResponse.action.toString())
                        commit()
                    }
                    DropInServiceResult.Action(detailsResponse.action)
                } else if (detailsResponse.resultCode != null &&
                                (detailsResponse.resultCode == "Authorised" ||
                                        detailsResponse.resultCode == "Received" ||
                                        detailsResponse.resultCode == "Pending")
                ) {
                    with(sharedPref.edit()) {
                        putString("AdyenResultCode", detailsResponse.resultCode)
                        commit()
                    }
                    DropInServiceResult.Finished(detailsResponse.resultCode)
                } else {
                    with(sharedPref.edit()) {
                        putString("AdyenResultCode", detailsResponse.resultCode ?: "EMPTY")
                        commit()
                    }
                    DropInServiceResult.Finished(detailsResponse.resultCode ?: "EMPTY")
                }
            } else {
                with(sharedPref.edit()) {
                    putString("AdyenResultCode", "PAYMENT_ERROR")
                    commit()
                }
                DropInServiceResult.Finished("PAYMENT_ERROR")
            }
        } catch (e: IOException) {
            with(sharedPref.edit()) {
                putString("AdyenResultCode", "PAYMENT_ERROR")
                commit()
            }
            DropInServiceResult.Finished("PAYMENT_ERROR")
        }
    }
}

/// Function that creates the payments request that is sent to the backend to make the payment
fun createPaymentsRequest(
        context: Context,
        lineItem: LineItem?,
        paymentComponentData: PaymentComponentData<out PaymentMethodDetails>,
        amount: String,
        currency: String,
        reference: String,
        shopperReference: String?,
        countryCode: String,
        additionalData: Map<String, String>
): PaymentsRequest {
    @Suppress("UsePropertyAccessSyntax")
    return PaymentsRequest(
            payment =
                    Payment(
                            paymentComponentData.getPaymentMethod() as PaymentMethodDetails,
                            countryCode,
                            paymentComponentData.isStorePaymentMethodEnable,
                            getAmount(amount, currency),
                            reference,
                            RedirectComponent.getReturnUrl(context),
                            lineItems = listOf(lineItem),
                            shopperReference = shopperReference
                    ),
            additionalData = additionalData
    )
}

/// Extension function that creates an amount object from the given amount String and currency
private fun getAmount(amount: String, currency: String) = createAmount(amount.toInt(), currency)

/// Function that creates an amount object from the given value and currency
fun createAmount(value: Int, currency: String): Amount {
    val amount = Amount()
    amount.currency = currency
    amount.value = value
    return amount
}

/// Data classes that are used to create the payments request
data class Payment(
        val paymentMethod: PaymentMethodDetails,
        val countryCode: String = "DE",
        val storePaymentMethod: Boolean,
        val amount: Amount,
        val reference: String,
        val returnUrl: String,
        val channel: String = "Android",
        val lineItems: List<LineItem?>,
        val additionalData: AdditionalData =
                AdditionalData(allow3DS2 = "true", executeThreeD = "true"),
        val shopperReference: String?
) : Serializable

/// Data classes that are used to create the payments request
data class PaymentsRequest(val payment: Payment, val additionalData: Map<String, String>) :
        Serializable

/// Line item data class to show purchased items
data class LineItem(val id: String, val description: String) : Serializable

/// Additional data class that is used to send data to the backend
data class AdditionalData(val allow3DS2: String = "true", var executeThreeD: String = "true")

/// Function that serializes the payments request to a json object
private fun serializePaymentsRequest(paymentsRequest: PaymentsRequest): JSONObject {
    val gson = Gson()
    val jsonString = gson.toJson(paymentsRequest)
    val request = JSONObject(jsonString)
    print(request)
    return request
}
