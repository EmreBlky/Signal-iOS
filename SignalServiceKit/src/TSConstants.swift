//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: -

@objc
public class TSConstants: NSObject {

    private enum Environment {
        case production, staging
    }
    private static var environment: Environment {
        // You can set "USE_STAGING=1" in your Xcode Scheme. This allows you to
        // prepare a series of commits without accidentally committing the change
        // to the environment.
        #if DEBUG
        if ProcessInfo.processInfo.environment["USE_STAGING"] == "1" {
            return .staging
        }
        #endif

        // If you do want to make a build that will always connect to staging,
        // change this value. (Scheme environment variables are only set when
        // launching via Xcode, so this approach is still quite useful.)
        return .production
    }

    @objc
    public static var isUsingProductionService: Bool {
        return environment == .production
    }

    // Never instantiate this class.
    private override init() {}

    public static let legalTermsUrl = URL(string: "https://signal.org/legal/")!
    public static let donateUrl = URL(string: "https://signal.org/donate/")!
    public static var appStoreUpdateURL = URL(string: "https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8")!

    public static var mainServiceIdentifiedURL: String { shared.mainServiceIdentifiedURL }
    public static var mainServiceUnidentifiedURL: String { shared.mainServiceUnidentifiedURL }

    @objc
    public static var textSecureCDN0ServerURL: String { shared.textSecureCDN0ServerURL }
    @objc
    public static var textSecureCDN2ServerURL: String { shared.textSecureCDN2ServerURL }
    @objc
    public static var contactDiscoveryV2URL: String { shared.contactDiscoveryV2URL }
    @objc
    public static var keyBackupURL: String { shared.keyBackupURL }
    @objc
    public static var storageServiceURL: String { shared.storageServiceURL }
    @objc
    public static var sfuURL: String { shared.sfuURL }
    @objc
    public static var sfuTestURL: String { shared.sfuTestURL }
    @objc
    public static var registrationCaptchaURL: String { shared.registrationCaptchaURL }
    @objc
    public static var challengeCaptchaURL: String { shared.challengeCaptchaURL }
    @objc
    public static var kUDTrustRoot: String { shared.kUDTrustRoot }
    @objc
    public static var updatesURL: String { shared.updatesURL }
    @objc
    public static var updates2URL: String { shared.updates2URL }

    @objc
    public static var censorshipReflectorHost: String { shared.censorshipReflectorHost }

    public static var serviceCensorshipPrefix: String { shared.serviceCensorshipPrefix }
    public static var cdn0CensorshipPrefix: String { shared.cdn0CensorshipPrefix }
    public static var cdn2CensorshipPrefix: String { shared.cdn2CensorshipPrefix }
    public static var keyBackupCensorshipPrefix: String { shared.keyBackupCensorshipPrefix }
    public static var storageServiceCensorshipPrefix: String { shared.storageServiceCensorshipPrefix }
    public static var contactDiscoveryV2CensorshipPrefix: String { shared.contactDiscoveryV2CensorshipPrefix }

    static var contactDiscoveryV2MrEnclave: MrEnclave { shared.contactDiscoveryV2MrEnclave }

    static var keyBackupEnclave: KeyBackupEnclave { shared.keyBackupEnclave }
    static var keyBackupPreviousEnclaves: [KeyBackupEnclave] { shared.keyBackupPreviousEnclaves }

    @objc
    public static var applicationGroup: String { shared.applicationGroup }

    @objc
    public static var serverPublicParamsBase64: String { shared.serverPublicParamsBase64 }

    public static var shared: TSConstantsProtocol {
        switch environment {
        case .production:
            return TSConstantsProduction()
        case .staging:
            return TSConstantsStaging()
        }
    }
}

// MARK: -

public protocol TSConstantsProtocol: AnyObject {
    var mainServiceIdentifiedURL: String { get }
    var mainServiceUnidentifiedURL: String { get }
    var textSecureCDN0ServerURL: String { get }
    var textSecureCDN2ServerURL: String { get }
    var contactDiscoveryV2URL: String { get }
    var keyBackupURL: String { get }
    var storageServiceURL: String { get }
    var sfuURL: String { get }
    var sfuTestURL: String { get }
    var registrationCaptchaURL: String { get }
    var challengeCaptchaURL: String { get }
    var kUDTrustRoot: String { get }
    var updatesURL: String { get }
    var updates2URL: String { get }

    var censorshipReflectorHost: String { get }

    var serviceCensorshipPrefix: String { get }
    var cdn0CensorshipPrefix: String { get }
    var cdn2CensorshipPrefix: String { get }
    var keyBackupCensorshipPrefix: String { get }
    var storageServiceCensorshipPrefix: String { get }
    var contactDiscoveryV2CensorshipPrefix: String { get }

    var contactDiscoveryV2MrEnclave: MrEnclave { get }

    var keyBackupEnclave: KeyBackupEnclave { get }
    var keyBackupPreviousEnclaves: [KeyBackupEnclave] { get }

    var applicationGroup: String { get }

    var serverPublicParamsBase64: String { get }
}

public struct KeyBackupEnclave: Equatable {
    let name: String
    let mrenclave: MrEnclave
    let serviceId: String
}

public struct MrEnclave: Equatable {
    public let dataValue: Data
    public let stringValue: String

    init(_ stringValue: StaticString) {
        self.stringValue = stringValue.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
        // This is a constant -- it should never fail to parse.
        self.dataValue = Data.data(fromHex: self.stringValue)!
        // All of our MrEnclave values are currently 32 bytes.
        owsAssert(self.dataValue.count == 32)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.dataValue == rhs.dataValue
    }
}

// MARK: - Production

private class TSConstantsProduction: TSConstantsProtocol {

    public let mainServiceIdentifiedURL = "https://chat.signal.org"
    public let mainServiceUnidentifiedURL = "https://ud-chat.signal.org"
    public let textSecureCDN0ServerURL = "https://cdn.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2.signal.org"
    public let contactDiscoveryV2URL = "wss://cdsi.signal.org"
    public let keyBackupURL = "https://api.backup.signal.org"
    public let storageServiceURL = "https://storage.signal.org"
    public let sfuURL = "https://sfu.voip.signal.org"
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let registrationCaptchaURL = "https://signalcaptchas.org/registration/generate.html"
    public let challengeCaptchaURL = "https://signalcaptchas.org/challenge/generate.html"
    public let kUDTrustRoot = "BXu6QIKVz5MA8gstzfOgRQGqyLqOwNKHL6INkv3IHWMF"
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipReflectorHost = "reflector-nrgwuv7kwq-uc.a.run.app"

    public let serviceCensorshipPrefix = "service"
    public let cdn0CensorshipPrefix = "cdn"
    public let cdn2CensorshipPrefix = "cdn2"
    public let keyBackupCensorshipPrefix = "backup"
    public let storageServiceCensorshipPrefix = "storage"
    public let contactDiscoveryV2CensorshipPrefix = "cdsi"

    public let contactDiscoveryV2MrEnclave = MrEnclave("0f6fd79cdfdaa5b2e6337f534d3baf999318b0c462a7ac1f41297a3e4b424a57")

    public let keyBackupEnclave = KeyBackupEnclave(
        name: "e18376436159cda3ad7a45d9320e382e4a497f26b0dca34d8eab0bd0139483b5",
        mrenclave: MrEnclave("45627094b2ea4a66f4cf0b182858a8dcf4b8479122c3820fe7fd0551a6d4cf5c"),
        serviceId: "3a485adb56e2058ef7737764c738c4069dd62bc457637eafb6bbce1ce29ddb89"
    )

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let keyBackupPreviousEnclaves: [KeyBackupEnclave] = [
        // Add the current `keyBackupEnclave` value here when replacing it.
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".signal.group"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "AMhf5ywVwITZMsff/eCyudZx9JDmkkkbV6PInzG4p8x3VqVJSFiMvnvlEKWuRob/1eaIetR31IYeAbm0NdOuHH8Qi+Rexi1wLlpzIo1gstHWBfZzy1+qHRV5A4TqPp15YzBPm0WSggW6PbSn+F4lf57VCnHF7p8SvzAA2ZZJPYJURt8X7bbg+H3i+PEjH9DXItNEqs2sNcug37xZQDLm7X36nOoGPs54XsEGzPdEV+itQNGUFEjY6X9Uv+Acuks7NpyGvCoKxGwgKgE5XyJ+nNKlyHHOLb6N1NuHyBrZrgtY/JYJHRooo5CEqYKBqdFnmbTVGEkCvJKxLnjwKWf+fEPoWeQFj5ObDjcKMZf2Jm2Ae69x+ikU5gBXsRmoF94GXTLfN0/vLt98KDPnxwAQL9j5V1jGOY8jQl6MLxEs56cwXN0dqCnImzVH3TZT1cJ8SW1BRX6qIVxEzjsSGx3yxF3suAilPMqGRp4ffyopjMD1JXiKR2RwLKzizUe5e8XyGOy9fplzhw3jVzTRyUZTRSZKkMLWcQ/gv0E4aONNqs4P"
}

// MARK: - Staging

private class TSConstantsStaging: TSConstantsProtocol {

    public let mainServiceIdentifiedURL = "https://chat.staging.signal.org"
    public let mainServiceUnidentifiedURL = "https://ud-chat.staging.signal.org"
    public let textSecureCDN0ServerURL = "https://cdn-staging.signal.org"
    public let textSecureCDN2ServerURL = "https://cdn2-staging.signal.org"
    public let contactDiscoveryV2URL = "wss://cdsi.staging.signal.org"
    public let keyBackupURL = "https://api-staging.backup.signal.org"
    public let storageServiceURL = "https://storage-staging.signal.org"
    public let sfuURL = "https://sfu.staging.voip.signal.org"
    public let registrationCaptchaURL = "https://signalcaptchas.org/staging/registration/generate.html"
    public let challengeCaptchaURL = "https://signalcaptchas.org/staging/challenge/generate.html"
    // There's no separate test SFU for staging.
    public let sfuTestURL = "https://sfu.test.voip.signal.org"
    public let kUDTrustRoot = "BbqY1DzohE4NUZoVF+L18oUPrK3kILllLEJh2UnPSsEx"
    // There's no separate updates endpoint for staging.
    public let updatesURL = "https://updates.signal.org"
    public let updates2URL = "https://updates2.signal.org"

    public let censorshipReflectorHost = "europe-west1-signal-cdn-reflector.cloudfunctions.net"

    public let serviceCensorshipPrefix = "service-staging"
    public let cdn0CensorshipPrefix = "cdn-staging"
    public let cdn2CensorshipPrefix = "cdn2-staging"
    public let keyBackupCensorshipPrefix = "backup-staging"
    public let storageServiceCensorshipPrefix = "storage-staging"
    public let contactDiscoveryV2CensorshipPrefix = "cdsi-staging"

    // CDS uses the same EnclaveName and MrEnclave
    public let contactDiscoveryV2MrEnclave = MrEnclave("0f6fd79cdfdaa5b2e6337f534d3baf999318b0c462a7ac1f41297a3e4b424a57")

    public let keyBackupEnclave = KeyBackupEnclave(
        name: "39963b736823d5780be96ab174869a9499d56d66497aa8f9b2244f777ebc366b",
        mrenclave: MrEnclave("45627094b2ea4a66f4cf0b182858a8dcf4b8479122c3820fe7fd0551a6d4cf5c"),
        serviceId: "9dbc6855c198e04f21b5cc35df839fdcd51b53658454dfa3f817afefaffc95ef"
    )

    // An array of previously used enclaves that we should try and restore
    // key material from during registration. These must be ordered from
    // newest to oldest, so we check the latest enclaves for backups before
    // checking earlier enclaves.
    public let keyBackupPreviousEnclaves: [KeyBackupEnclave] = [
        // Add the current `keyBackupEnclave` value here when replacing it.
    ]

    public let applicationGroup = "group." + Bundle.main.bundleIdPrefix + ".signal.group.staging"

    // We need to discard all profile key credentials if these values ever change.
    // See: GroupsV2Impl.verifyServerPublicParams(...)
    public let serverPublicParamsBase64 = "ABSY21VckQcbSXVNCGRYJcfWHiAMZmpTtTELcDmxgdFbtp/bWsSxZdMKzfCp8rvIs8ocCU3B37fT3r4Mi5qAemeGeR2X+/YmOGR5ofui7tD5mDQfstAI9i+4WpMtIe8KC3wU5w3Inq3uNWVmoGtpKndsNfwJrCg0Hd9zmObhypUnSkfYn2ooMOOnBpfdanRtrvetZUayDMSC5iSRcXKpdlukrpzzsCIvEwjwQlJYVPOQPj4V0F4UXXBdHSLK05uoPBCQG8G9rYIGedYsClJXnbrgGYG3eMTG5hnx4X4ntARBgELuMWWUEEfSK0mjXg+/2lPmWcTZWR9nkqgQQP0tbzuiPm74H2wMO4u1Wafe+UwyIlIT9L7KLS19Aw8r4sPrXZSSsOZ6s7M1+rTJN0bI5CKY2PX29y5Ok3jSWufIKcgKOnWoP67d5b2du2ZVJjpjfibNIHbT/cegy/sBLoFwtHogVYUewANUAXIaMPyCLRArsKhfJ5wBtTminG/PAvuBdJ70Z/bXVPf8TVsR292zQ65xwvWTejROW6AZX6aqucUj"
}
