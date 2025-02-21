import Flutter
import UIKit
import Adyen
import Adyen3DS2
import Foundation
import AdyenNetworking
import PassKit

// Define a custom error struct for payment-related errors
struct PaymentError: Error {
    var message: String
}

// Define a custom error struct for canceled payments
struct PaymentCancelled: Error {}

// Create a public class named SwiftFlutterAdyenPlugin that conforms to the FlutterPlugin protocol
public class SwiftFlutterAdyenPlugin: NSObject, FlutterPlugin {
    // Initialize the plugin
    override
    public init() {}

    // Register the plugin with Flutter
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Create a method channel for communication with Flutter
        let channel = FlutterMethodChannel(name: "flutter_adyen", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterAdyenPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }

    // Declare properties to store various configuration settings and data
    var dropInComponent: DropInComponent?
    var baseURL: String?
    var clientKey: String?
    var applePayMerchantId: String?
    var applePayMerchantName: String?
    var currency: String?
    var amountString: String?
    var amount: Amount?
    var returnUrl: String?
    var mResult: FlutterResult?
    var topController: UIViewController?
    var environment: String?
    var shopperReference: String?
    var lineItemJson: [String: String]?
    var shopperLocale: String?
    var additionalData: [String: String]?
    var headers: [String: String]?
     var backgroundColor: UIColor = .white
    var accentColor: UIColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1.0)

    // Handle incoming Flutter method calls
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Check if the method call is for opening the payment drop-in
        guard call.method.elementsEqual("openDropIn") else { return }

        // Parse arguments from the Flutter method call
        let arguments = call.arguments as? [String: Any]
        let paymentMethodsResponse = arguments?["paymentMethods"] as? String
        baseURL = arguments?["baseUrl"] as? String
        additionalData = arguments?["additionalData"] as? [String: String]
        clientKey = arguments?["clientKey"] as? String
        applePayMerchantId = arguments?["applePayMerchantId"] as? String
        applePayMerchantName = arguments?["applePayMerchantName"] as? String
        currency = arguments?["currency"] as? String
        amountString = arguments?["amount"] as? String
        amount = Amount(value: Int(amountString ?? "0") ?? 0, currencyCode: currency ?? "EUR")
        lineItemJson = arguments?["lineItem"] as? [String: String]
        environment = arguments?["environment"] as? String
        returnUrl = arguments?["returnUrl"] as? String
        shopperReference = arguments?["shopperReference"] as? String
        shopperLocale = String((arguments?["locale"] as? String)?.split(separator: "_").last ?? "DE")
        headers = arguments?["headers"] as? [String: String]
        mResult = result


        if let backgroundColorValue = arguments?["backgroundColor"] as? Int {
            backgroundColor = UIColor(argb: backgroundColorValue)
        }

        if let accentColorValue = arguments?["accentColor"] as? Int {
            accentColor = UIColor(argb: accentColorValue)
        }

        
        // Handle the payment flow and user interactions
        do {
            // Decode payment methods response and configure the drop-in component
            guard let paymentData = paymentMethodsResponse?.data(using: .utf8) else {
                NSLog("payment data is nil")
                return
            }
            
            let paymentMethods = try JSONDecoder().decode(PaymentMethods.self, from: paymentData)
            
            var ctx = Environment.test
            if(environment == "LIVE_US") {
                ctx = Environment.liveUnitedStates
            } else if (environment == "LIVE_AUSTRALIA"){
                ctx = Environment.liveAustralia
            } else if (environment == "LIVE_EUROPE"){
                ctx = Environment.liveEurope
            }

            var dropInComponentStyle = DropInComponent.Style(tintColor: .darkGray)
            dropInComponentStyle.navigation.backgroundColor = backgroundColor
            dropInComponentStyle.navigation.barTitle = TextStyle(font: .systemFont(ofSize: 24, weight: .semibold), color: .white, textAlignment: .natural)
            dropInComponentStyle.navigation.cornerRadius = 16
            
            dropInComponentStyle.navigation.toolbarMode = ToolbarMode.leftCancel
            
            dropInComponentStyle.listComponent.backgroundColor = backgroundColor
            dropInComponentStyle.listComponent.listItem.backgroundColor = backgroundColor
            dropInComponentStyle.listComponent.listItem.title = TextStyle(font: .preferredFont(forTextStyle: .body), color: .white, textAlignment: .natural)
            dropInComponentStyle.listComponent.listItem.image = ImageStyle(borderColor: .black, borderWidth: 1.0 / UIScreen.main.nativeScale, cornerRadius: 4.0, clipsToBounds: true, contentMode: .scaleAspectFit)
            
            dropInComponentStyle.formComponent.backgroundColor = backgroundColor
            dropInComponentStyle.formComponent.textField.title = TextStyle(font: .preferredFont(forTextStyle: .footnote), color: UIColor(red: 1, green: 1, blue:1 , alpha: 0.6), textAlignment: .natural)
            dropInComponentStyle.formComponent.textField.text = TextStyle(font: UIFont(name: "Courier", size: 18)!, color: .white, textAlignment: .natural)
            dropInComponentStyle.formComponent.textField.placeholderText = TextStyle(font: UIFont(name: "Courier", size: 18)!, color: UIColor(red: 1, green: 1, blue:1 , alpha: 0.2), textAlignment: .natural)
            dropInComponentStyle.formComponent.textField.tintColor = .white
            
            dropInComponentStyle.formComponent.toggle.title = TextStyle(font: .preferredFont(forTextStyle: .body), color: .white, textAlignment: .natural)
            dropInComponentStyle.formComponent.toggle.tintColor = accentColor
            
            dropInComponentStyle.formComponent.mainButtonItem = .main(font: .preferredFont(forTextStyle: .headline), textColor: .black, mainColor: accentColor, cornerRadius: 16)

            // Create and configure the drop-in component
            let configuration = DropInComponent.Configuration()
            
            let payment = Payment(amount: amount!, countryCode: shopperLocale ?? "DE")
            
            if let merchantId = applePayMerchantId, !merchantId.isEmpty {
                if let applePayPayment = try? ApplePayPayment(payment: payment, brand: applePayMerchantName ?? "") {
                    configuration.applePay = .init(payment: applePayPayment, merchantIdentifier: merchantId)
                    configuration.applePay?.allowOnboarding = true
                }
            }
            
            configuration.card.showsHolderNameField = true
            configuration.style = dropInComponentStyle
            
            let apiContext = try APIContext(environment: ctx, clientKey: clientKey!)
            
            let adyenContext = AdyenContext(apiContext: apiContext, payment: payment)
            
            dropInComponent = DropInComponent(paymentMethods: paymentMethods, context: adyenContext, configuration: configuration)
            dropInComponent?.delegate = self

            // Present the drop-in component to the user
            if var topController = UIApplication.shared.keyWindow?.rootViewController, let dropIn = dropInComponent {
                self.topController = topController
                while let presentedViewController = topController.presentedViewController{
                    topController = presentedViewController
                }
                topController.present(dropIn.viewController, animated: true)
            }
        } catch let error {
            NSLog("Payment error with: \(error.localizedDescription)")
        }
    }

    // Handle URL callback from external sources (e.g., redirect)
    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        RedirectComponent.applicationDidOpen(from: url)
        return true
    }
}

// Implement delegate methods for the DropInComponent
extension SwiftFlutterAdyenPlugin: DropInComponentDelegate {
    // Handle completion of a payment action
    public func didComplete(from component: ActionComponent, in dropInComponent: AnyDropInComponent) {
        component.stopLoadingIfNeeded()
    }

    // Handle cancellation of a payment
    public func didCancel(component: PaymentComponent, from dropInComponent: AnyDropInComponent) {
        self.didFail(with: PaymentCancelled(), from: dropInComponent)
    }

    // Handle submission of payment data
    public func didSubmit(_ data: PaymentComponentData, from component: PaymentComponent, in dropInComponent: AnyDropInComponent) {
        NSLog("[SwiftFlutterAdyenPlugin] didSubmit")
        guard let baseURL = baseURL, let url = URL(string: baseURL + "payments") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in headers ?? [:] {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // prepare json data
        let paymentMethod = data.paymentMethod.encodable
        
        guard let lineItem = try? JSONDecoder().decode(LineItem.self, from: JSONSerialization.data(withJSONObject: lineItemJson ?? ["":""]) )
        else {
            self.didFail(with: PaymentError(message: "LineItem parsing failed"), from: dropInComponent)
            return
        }
        
        let paymentRequest = PaymentRequest(
            paymentData: PaymentData(
                paymentMethod: paymentMethod,
                lineItem: lineItem,
                currency: currency ?? "",
                amount: amount!,
                returnUrl: returnUrl ?? "",
                storePayment: data.storePaymentMethod ?? false,
                shopperReference: shopperReference,
                countryCode: shopperLocale ?? "DE"
            ),
            additionalData:additionalData ?? [String: String]()
        )
        
        do {
            let jsonData = try JSONEncoder().encode(paymentRequest)
            
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data {
                    if let dataString = String(data: data, encoding: .utf8) {
                        NSLog("[SwiftFlutterAdyenPlugin] POST /payments - DATA: \(dataString)")
                    }
                    self.finish(data: data, component: dropInComponent)
                }
                if error != nil {
                    NSLog("[SwiftFlutterAdyenPlugin] POST /payments - ERROR: \(error?.localizedDescription ?? "Unknown error")")
                    self.didFail(with: PaymentError(message: error?.localizedDescription ?? "Payments request error"), from: dropInComponent)
                }
            }.resume()
        } catch let error {
            didFail(with: PaymentError(message: error.localizedDescription), from: dropInComponent)
        }
        
    }
    
    func finish(data: Data, component: AnyDropInComponent) {
        DispatchQueue.main.async {
            guard let dataString = String(data: data, encoding: .utf8) else {
                self.didFail(with: PaymentError(message: "PaymentsResponse: failed to convert data to string"), from: component)
                return
            }

            guard let response = try? JSONDecoder().decode(PaymentsResponse.self, from: data) else {
                self.didFail(with: PaymentError(message: "PaymentsResponse: parsing to JSON failed for: \(dataString)"), from: component)
                return
            }
            if let action = response.action {
                self.dropInComponent?.stopLoadingIfNeeded()
                self.dropInComponent?.handle(action)
            } else {
                component.stopLoadingIfNeeded()
                if response.resultCode == .authorised || response.resultCode == .received || response.resultCode == .pending, let result = self.mResult {
                    result(response.resultCode.rawValue)
                    self.topController?.dismiss(animated: false, completion: nil)
                    
                } else if (response.resultCode == .error || response.resultCode == .refused) {
                    self.didFail(with: PaymentError(message: "Action from /payments response failed"), from: component)
                }
                else {
                    self.didFail(with: PaymentCancelled(), from: component)
                }
            }
        }
    }
    
    public func didProvide(_ data: ActionComponentData, from component: ActionComponent, in dropInComponent: AnyDropInComponent) {
        guard let baseURL = baseURL, let url = URL(string: baseURL + "payments/details") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers ?? [:] {
            request.addValue(value, forHTTPHeaderField: key)
        }
        let detailsRequest = DetailsRequest(paymentData: data.paymentData ?? "", details: data.details.encodable)
        do {
            let detailsRequestData = try JSONEncoder().encode(detailsRequest)
            request.httpBody = detailsRequestData
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let response = response as? HTTPURLResponse {
                    if (response.statusCode != 200) {
                        self.didFail(with: PaymentError(message: "Payment details endpoint status code error"), from: dropInComponent)
                    }
                }
                if let data = data {
                    self.finish(data: data, component: dropInComponent)
                }
                
            }.resume()
        } catch let error {
            self.didFail(with: PaymentError(message: error.localizedDescription), from: dropInComponent)
        }
    }
    
    public func didFail(with error: Error, from dropInComponent: AnyDropInComponent) {
        DispatchQueue.main.async {
            if (error is PaymentCancelled) {
                self.mResult?("PAYMENT_CANCELLED")
            } else if let componentError = error as? ComponentError, componentError == ComponentError.cancelled {
                self.mResult?("PAYMENT_CANCELLED")
            } else if (error is PaymentError) {
                if let paymentError = error as? PaymentError {
                    self.mResult?("PAYMENT_ERROR: \(paymentError.message)")
                }
            } else {
                self.mResult?("PAYMENT_ERROR \(error.localizedDescription)")
            }
            self.topController?.dismiss(animated: true, completion: nil)
        }
    }
    
    public func didFail(with error: Error, from component: ActionComponent, in dropInComponent: AnyDropInComponent) {}
    
    public func didFail(with error: Error, from component: PaymentComponent, in dropInComponent: AnyDropInComponent) {}
}

struct DetailsRequest: Encodable {
    let paymentData: String
    let details: AnyEncodable
}

struct PaymentRequest : Encodable {
    let paymentData: PaymentData
    let additionalData: [String: String]
}

struct PaymentData : Encodable {
    let paymentMethod: AnyEncodable
    let lineItems: [LineItem]
    let channel: String = "iOS"
    let additionalData = ["allow3DS2" : "true", "executeThreeD" : "true"]
    let amount: Amount
    let returnUrl: String
    let storePaymentMethod: Bool
    let shopperReference: String?
    let countryCode: String?
    
    init(paymentMethod: AnyEncodable, lineItem: LineItem, currency: String, amount: Amount, returnUrl: String, storePayment: Bool, shopperReference: String?, countryCode: String?) {
        self.paymentMethod = paymentMethod
        self.lineItems = [lineItem]
        self.amount = amount
        self.returnUrl = returnUrl
        self.shopperReference = shopperReference
        self.storePaymentMethod = storePayment
        self.countryCode = countryCode
    }
}

struct LineItem: Codable {
    let id: String?
    let description: String?
}

internal struct PaymentsResponse: Response {
    
    internal let resultCode: ResultCode
    
    internal let action: Action?
    
    internal init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.resultCode = try container.decode(ResultCode.self, forKey: .resultCode)
        self.action = try container.decodeIfPresent(Action.self, forKey: .action)
    }
    
    private enum CodingKeys: String, CodingKey {
        case resultCode
        case action
    }
    
}

internal extension PaymentsResponse {
    
    // swiftlint:disable:next explicit_acl
    enum ResultCode: String, Decodable {
        case authorised = "Authorised"
        case refused = "Refused"
        case pending = "Pending"
        case cancelled = "Cancelled"
        case error = "Error"
        case received = "Received"
        case redirectShopper = "RedirectShopper"
        case identifyShopper = "IdentifyShopper"
        case challengeShopper = "ChallengeShopper"
        case presentToShopper = "PresentToShopper"
    }
    
}
