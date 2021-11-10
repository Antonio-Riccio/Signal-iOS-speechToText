//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import PassKit
import ZKGroup

public class SubscriptionLevel: Comparable {
    public let level: UInt
    public let name: String
    public let badge: ProfileBadge
    public let currency: [String: NSDecimalNumber]
    
    public init(level: UInt, jsonDictionary: [String : Any]) throws {
        self.level = level
        let params = ParamParser(dictionary: jsonDictionary)
        name = try params.required(key: "name")
        let badgeDict: [String: Any] = try params.required(key: "badge")
        badge = try ProfileBadge(jsonDictionary: badgeDict)
        let currencyDict: [String: Any] = try params.required(key: "currencies")
        currency = currencyDict.compactMapValues {
            guard let int64Currency = $0 as? Int64 else {
                owsFailDebug("Failed to convert currency value")
                return nil
            }
            return NSDecimalNumber(value: int64Currency)
        }
    }
    
    // MARK: Comparable
    
    public static func < (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level < rhs.level
    }
    
    public static func == (lhs: SubscriptionLevel, rhs: SubscriptionLevel) -> Bool {
        return lhs.level == rhs.level
    }
}

public class SubscriptionManager: NSObject {

    private static let subscriptionKVS = SDSKeyValueStore(collection: "SubscriptionKeyValueStore")
    private static let subscriberIDKey = "subscriberID"
    private static let subscriberCurrencyCodeKey = "subscriberCurrencyCode"
    
    //MARK: Subscription levels
    
    public class func getSubscriptions() -> Promise<[SubscriptionLevel]> {
        let request = OWSRequestFactory.subscriptionLevelsRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            
            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }

            do {
                let subscriptionDicts: [String: Any] = try parser.required(key: "levels")
                let subscriptions: [SubscriptionLevel] = try subscriptionDicts.compactMap { (subscriptionKey: String, value: Any) in
                    guard let subscriptionDict = value as? [String: Any] else {
                        return nil
                    }
                    
                    guard let level = UInt(subscriptionKey) else {
                        throw OWSAssertionError("Unable to determine subscription level")
                    }

                    return try SubscriptionLevel(level: level, jsonDictionary: subscriptionDict)
                }
                return subscriptions.sorted()
            } catch {
                owsFailDebug("Unable to parse subscription levels, \(error)")
            }

            return []
        }
    }
    
    //MARK: Subscription management
    
    public static func getSubscriberID(transaction: SDSAnyReadTransaction) -> Data? {
        guard let subscriberID = subscriptionKVS.getObject(
            forKey: subscriberIDKey,
            transaction: transaction
        ) as? Data else {
            return nil
        }
        return subscriberID
    }
    
    public static func setSubscriberID(_ subscriberID: Data?, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(subscriberID,
                                  key: subscriberIDKey,
                                  transaction: transaction)
    }
    
    public static func getSubscriberCurrencyCode(transaction: SDSAnyReadTransaction) -> String? {
        guard let subscriberCurrencyCode = subscriptionKVS.getObject(
            forKey: subscriberCurrencyCodeKey,
            transaction: transaction
        ) as? String else {
            return nil
        }
        return subscriberCurrencyCode
    }
    
    public static func setSubscriberCurrencyCode(_ currencyCode: String?, transaction: SDSAnyWriteTransaction) {
        subscriptionKVS.setObject(currencyCode,
                                  key: subscriberCurrencyCodeKey,
                                  transaction: transaction)
    }
    

    private class func setupNewSubscriberID() throws -> Promise<Data> {

        let newSubscriberID = generateSubscriberID()
        let request = OWSRequestFactory.setSubscriptionIDRequest(newSubscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            
            if let json = response.responseBodyJson as? [String: Any] {
                Logger.debug("Got response \(json)")
            }
            
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
            
            return newSubscriberID
        }
    }
    
    private class func generateSubscriberID() -> Data {
        return Cryptography.generateRandomBytes(UInt(32))
    }
    
    public class func setupNewSubscription(subscription: SubscriptionLevel, payment: PKPayment, currencyCode: String) throws -> Promise<Void> {

        var generatedSubscriberID = Data()
        var generatedClientSecret = ""
        var generatedPaymentID = ""

        return firstly {
            return try setupNewSubscriberID()

        // Create Stripe SetupIntent against new subscriberID
        }.then(on: .sharedUserInitiated) { subscriberID -> Promise<String> in

            generatedSubscriberID = subscriberID
            
            SDSDatabaseStorage.shared.write { transaction in
                self.setSubscriberID(subscriberID, transaction:transaction)
                self.setSubscriberCurrencyCode(currencyCode, transaction: transaction)
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
            
            return try createPaymentMethod(for: subscriberID)

        // Create new payment method
        }.then(on: .sharedUserInitiated) { clientSecret -> Promise<String> in

            generatedClientSecret = clientSecret
            return Stripe.createPaymentMethod(with: payment)

        // Bind payment method to SetupIntent, confirm SetupIntent
        }.then(on: .sharedUserInitiated) { paymentID -> Promise<HTTPResponse> in

            generatedPaymentID = paymentID
            return try Stripe.confirmSetupIntent(for: generatedPaymentID, clientSecret: generatedClientSecret)

        // Update payment on server
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in

            return try setDefaultPaymentMethod(for: generatedSubscriberID, paymentID: generatedPaymentID)

        // Select subscription level
        }.then(on: .sharedUserInitiated) { _ -> Promise<Void> in

            return setSubscription(for: generatedSubscriberID, subscription: subscription, currency: currencyCode)

        // Report success and dismiss sheet
        }
    }
    
    private class func createPaymentMethod(for subscriberID: Data) throws -> Promise<String> {
        let request = OWSRequestFactory.subscriptionCreatePaymentMethodRequest(subscriberID.asBase64Url)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode

            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
            
            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }
            
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }
            
            do {
                let clientSecret: String = try parser.required(key: "clientSecret")
                return clientSecret
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
        }
    }
    
    private class func setDefaultPaymentMethod(for subscriberID: Data, paymentID: String) throws -> Promise<Void> {
        let request = OWSRequestFactory.subscriptionSetDefaultPaymentMethodRequest(subscriberID.asBase64Url, paymentID: paymentID)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }
    
    private class func setSubscription(for subscriberID: Data, subscription: SubscriptionLevel, currency: String) -> Promise<Void> {
        
        let subscriberID = subscriberID.asBase64Url
        let key = Cryptography.generateRandomBytes(UInt(32)).asBase64Url
        let level = String(subscription.level)
        let request = OWSRequestFactory.subscriptionSetSubscriptionLevelRequest(subscriberID, level: level, currency: currency, idempotencyKey: key)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }
    
    public class func requestAndRedeemRecieptsIfNecessary(for subscriberID: Data, subscriptionLevel: SubscriptionLevel) throws -> Promise<Void> {
        return firstly {
            return try requestReceiptCredentialPresentation(for: subscriberID, subscriptionLevel: subscriptionLevel)
        }.then(on: .sharedUserInitiated) { presentation -> Promise<Void> in
            try redeemReceiptCredentialPresentation(receiptCredentialPresentation: presentation)
        }
    }
    
    private class func requestReceiptCredentialPresentation(for subscriberID: Data, subscriptionLevel: SubscriptionLevel) throws -> Promise<ReceiptCredentialPresentation> {
        let clientOperations = try clientZKReceiptOperations()
        let receiptSerial = try generateReceiptSerial()

        let receiptCredentialRequestContext = try clientOperations.createReceiptCredentialRequestContext(receiptSerial: receiptSerial)
        let receiptCredentialRequest = try receiptCredentialRequestContext.getRequest().serialize().asData.base64EncodedString()
        let request = OWSRequestFactory.subscriptionRecieptCredentialsRequest(subscriberID.asBase64Url, request: receiptCredentialRequest)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode == 200 {
                Logger.debug("Got valid receipt response")
            } else if statusCode == 204 {
                Logger.debug("User has no active subscriptions")
            } else {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
            
            guard let json = response.responseBodyJson as? [String: Any] else {
                throw OWSAssertionError("Unable to parse response body.")
            }
            
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }
            
            do {
                let receiptCredentialResponseString: String = try parser.required(key: "receiptCredentialResponse")
                guard let receiptCredentialResponseData = Data(base64Encoded: receiptCredentialResponseString) else {
                    throw OWSAssertionError("Unable to parse receiptCredentialResponse into data.")
                }

                let receiptCredentialResponse = try ReceiptCredentialResponse(contents: [UInt8](receiptCredentialResponseData))
                let receiptCredential = try clientOperations.receiveReceiptCredential(receiptCredentialRequestContext: receiptCredentialRequestContext, receiptCredentialResponse: receiptCredentialResponse)
                
                //TODO EB Allow prior level as well
                let level = try receiptCredential.getReceiptLevel()
                guard level == subscriptionLevel.level else {
                    throw OWSAssertionError("Unexpected receipt credential level")
                }
                
                let expiration = try receiptCredential.getReceiptExpirationTime()
                guard expiration % 86400 == 0 else {
                    throw OWSAssertionError("Invalid receipt credential expiration")
                }
                
                //TODO EB Check expiration is within 60 days
                
                let receiptCredentialPresentation = try clientOperations.createReceiptCredentialPresentation(receiptCredential: receiptCredential)
                

                
                return receiptCredentialPresentation
            } catch {
                throw OWSAssertionError("Missing clientID key")
            }
        }
    }
    
    private class func redeemReceiptCredentialPresentation(receiptCredentialPresentation: ReceiptCredentialPresentation) throws -> Promise<Void> {
        let receiptCredentialPresentationString = receiptCredentialPresentation.serialize().asData.base64EncodedString()
        let request = OWSRequestFactory.subscriptionRedeemRecieptCredential(receiptCredentialPresentationString, makePrimary: true)
        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            let statusCode = response.responseStatusCode
            if statusCode != 200 {
                throw OWSAssertionError("Got bad response code \(statusCode).")
            }
        }
    }
    
    private class func generateReceiptSerial() throws -> ReceiptSerial {
        let count = ReceiptSerial.SIZE
        let bytes = Cryptography.generateRandomBytes(UInt(count))
        return try ReceiptSerial(contents: [UInt8](bytes))
    }
    
    private class func clientZKReceiptOperations() throws -> ClientZkReceiptOperations {
        let params = try GroupsV2Protos.serverPublicParams()
        return ClientZkReceiptOperations(serverPublicParams: params)
    }
}
