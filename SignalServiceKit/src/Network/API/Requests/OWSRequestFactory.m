//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSRequestFactory.h"
#import "NSData+keyVersionByte.h"
#import "OWS2FAManager.h"
#import "OWSDevice.h"
#import "OWSIdentityManager.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SignedPrekeyRecord.h"
#import "TSAccountManager.h"
#import "TSRequest.h"
#import <Curve25519Kit/Curve25519.h>
#import <SignalCoreKit/Cryptography.h>
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSRequestKey_AuthKey = @"AuthKey";

@implementation OWSRequestFactory

+ (TSRequest *)disable2FARequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:self.textSecure2FAAPI] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)acknowledgeMessageDeliveryRequestWithServerGuid:(NSString *)serverGuid
{
    OWSAssertDebug(serverGuid.length > 0);

    NSString *path = [NSString stringWithFormat:@"v1/messages/uuid/%@", serverGuid];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)deleteDeviceRequestWithDevice:(OWSDevice *)device
{
    OWSAssertDebug(device);

    NSString *path = [NSString stringWithFormat:self.textSecureDevicesAPIFormat, @(device.deviceId)];

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)getDevicesRequest
{
    NSString *path = [NSString stringWithFormat:self.textSecureDevicesAPIFormat, @""];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)getMessagesRequest
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/messages"] method:@"GET" parameters:@{}];
    [StoryManager appendStoryHeadersToRequest:request];
    request.shouldCheckDeregisteredOn401 = YES;
    return request;
}

+ (TSRequest *)getUnversionedProfileRequestWithAddress:(SignalServiceAddress *)address
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                                  auth:(ChatServiceAuth *)auth
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(address.uuid != nil);

    NSString *path = [NSString stringWithFormat:@"v1/profile/%@", address.uuidString];
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    } else {
        [request setAuth:auth];
    }
    return request;
}

+ (TSRequest *)getVersionedProfileRequestWithServiceId:(ServiceIdObjC *)serviceId
                                     profileKeyVersion:(nullable NSString *)profileKeyVersion
                                     credentialRequest:(nullable NSData *)credentialRequest
                                           udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                                  auth:(ChatServiceAuth *)auth
{
    NSString *uuidParam = serviceId.uuidValue.UUIDString.lowercaseString;
    NSString *_Nullable profileKeyVersionParam = profileKeyVersion.lowercaseString;
    NSString *_Nullable credentialRequestParam = credentialRequest.hexadecimalString.lowercaseString;

    // GET /v1/profile/{uuid}/{version}/{profile_key_credential_request}
    NSString *path;
    if (profileKeyVersion.length > 0 && credentialRequest.length > 0) {
        path = [NSString stringWithFormat:@"v1/profile/%@/%@/%@?credentialType=expiringProfileKey",
                         uuidParam,
                         profileKeyVersionParam,
                         credentialRequestParam];
    } else if (profileKeyVersion.length > 0) {
        path = [NSString stringWithFormat:@"v1/profile/%@/%@", uuidParam, profileKeyVersionParam];
    } else {
        path = [NSString stringWithFormat:@"v1/profile/%@", uuidParam];
    }

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    } else {
        [request setAuth:auth];
    }
    return request;
}

+ (TSRequest *)turnServerInfoRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/accounts/turn"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)allocAttachmentRequestV2
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v2/attachments/form/upload"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)allocAttachmentRequestV3
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v3/attachments/form/upload"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)availablePreKeysCountRequestForIdentity:(OWSIdentity)identity
{
    NSString *path = self.textSecureKeysAPI;
    NSString *queryParam = [OWSRequestFactory queryParamFor:identity];
    if (queryParam != nil) {
        path = [path stringByAppendingFormat:@"?%@", queryParam];
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)contactsIntersectionRequestWithHashesArray:(NSArray<NSString *> *)hashes
{
    OWSAssertDebug(hashes.count > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@", self.textSecureDirectoryAPI, @"tokens"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:@{
                              @"contacts" : hashes,
                          }];
}

+ (TSRequest *)currentSignedPreKeyRequest
{
    NSString *path = self.textSecureSignedKeysAPI;
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)profileAvatarUploadFormRequest
{
    NSString *path = self.textSecureProfileAvatarFormAPI;
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (TSRequest *)recipientPreKeyRequestWithServiceId:(ServiceIdObjC *)serviceId
                                          deviceId:(NSString *)deviceId
                                       udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(deviceId.length > 0);

    NSString *path =
        [NSString stringWithFormat:@"%@/%@/%@", self.textSecureKeysAPI, serviceId.uuidValue.UUIDString, deviceId];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)registerForPushRequestWithPushIdentifier:(NSString *)identifier
                                         voipIdentifier:(nullable NSString *)voipId
{
    OWSAssertDebug(identifier.length > 0);

    NSString *path = [NSString stringWithFormat:@"%@/%@", self.textSecureAccountsAPI, @"apn"];

    NSMutableDictionary *parameters = [@{ @"apnRegistrationId" : identifier } mutableCopy];
    if (voipId.length > 0) {
        parameters[@"voipRegistrationId"] = voipId;
    } else {
        OWSAssertDebug(SSKFeatureFlags.notificationServiceExtension);
    }

    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
}

+ (TSRequest *)unregisterAccountRequest
{
    NSString *path = [NSString stringWithFormat:@"%@/%@", self.textSecureAccountsAPI, @"me"];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"DELETE" parameters:@{}];
}

+ (TSRequest *)requestVerificationCodeRequestWithE164:(NSString *)e164
                                     preauthChallenge:(nullable NSString *)preauthChallenge
                                         captchaToken:(nullable NSString *)captchaToken
                                            transport:(TSVerificationTransport)transport
{
    OWSAssertDebug(e164.length > 0);

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray new];
    [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client" value:@"ios"]];

    if (captchaToken.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"captcha" value:captchaToken]];
    }

    if (preauthChallenge.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"challenge" value:preauthChallenge]];
    }

    NSString *path = [NSString
        stringWithFormat:@"%@/%@/code/%@", self.textSecureAccountsAPI, [self stringForTransport:transport], e164];

    NSURLComponents *components = [[NSURLComponents alloc] initWithString:path];
    components.queryItems = queryItems;

    TSRequest *request = [TSRequest requestWithUrl:components.URL method:@"GET" parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;

    if (transport == TSVerificationTransportVoice) {
        NSString *_Nullable localizationHeader = [self voiceCodeLocalizationHeader];
        if (localizationHeader.length > 0) {
            [request setValue:localizationHeader forHTTPHeaderField:@"Accept-Language"];
        }
    }

    return request;
}

+ (nullable NSString *)voiceCodeLocalizationHeader
{
    NSLocale *locale = [NSLocale currentLocale];
    NSString *_Nullable languageCode = [locale objectForKey:NSLocaleLanguageCode];
    NSString *_Nullable countryCode = [locale objectForKey:NSLocaleCountryCode];

    if (!languageCode) {
        return nil;
    }

    OWSAssertDebug([languageCode rangeOfString:@"-"].location == NSNotFound);

    if (!countryCode) {
        // In the absence of a country code, just send a language code.
        return languageCode;
    }

    OWSAssertDebug(languageCode.length == 2);
    OWSAssertDebug(countryCode.length == 2);
    return [NSString stringWithFormat:@"%@-%@", languageCode, countryCode];
}

+ (NSString *)stringForTransport:(TSVerificationTransport)transport
{
    switch (transport) {
        case TSVerificationTransportSMS:
            return @"sms";
        case TSVerificationTransportVoice:
            return @"voice";
    }
}

+ (TSRequest *)currencyConversionRequest NS_SWIFT_NAME(currencyConversionRequest())
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/payments/conversions"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)updateSecondaryDeviceCapabilitiesRequest
{
    // If you are updating capabilities for a primary device, use `updateAccountAttributes` instead
    OWSAssertDebug(!self.tsAccountManager.isPrimaryDevice);

    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/devices/capabilities"]
                              method:@"PUT"
                          parameters:[self deviceCapabilitiesWithIsSecondaryDevice:YES]];
}

+ (NSDictionary<NSString *, NSNumber *> *)deviceCapabilitiesForLocalDevice
{
    // tsAccountManager.isPrimaryDevice only has a valid value for registered
    // devices.
    OWSAssertDebug(self.tsAccountManager.isRegisteredAndReady);

    BOOL isSecondaryDevice = !self.tsAccountManager.isPrimaryDevice;
    return [self deviceCapabilitiesWithIsSecondaryDevice:isSecondaryDevice];
}

+ (NSDictionary<NSString *, NSNumber *> *)deviceCapabilitiesWithIsSecondaryDevice:(BOOL)isSecondaryDevice
{
    NSMutableDictionary<NSString *, NSNumber *> *capabilities = [NSMutableDictionary new];
    capabilities[@"gv2"] = @(YES);
    capabilities[@"gv2-2"] = @(YES);
    capabilities[@"gv2-3"] = @(YES);
    capabilities[@"transfer"] = @(YES);
    capabilities[@"announcementGroup"] = @(YES);
    capabilities[@"senderKey"] = @(YES);

    if (RemoteConfig.stories || isSecondaryDevice) {
        capabilities[@"stories"] = @(YES);
    }

    if (RemoteConfig.canReceiveGiftBadges) {
        capabilities[@"giftBadges"] = @(YES);
    }

    // If the storage service requires (or will require) secondary devices
    // to have a capability in order to be linked, we might need to always
    // set that capability here if isSecondaryDevice is true.

    if (KeyBackupServiceObjcBridge.hasBackedUpMasterKey) {
        capabilities[@"storage"] = @(YES);
    }

    capabilities[@"changeNumber"] = @(YES);

    OWSLogInfo(@"local device capabilities: %@", capabilities);
    return [capabilities copy];
}

+ (TSRequest *)submitMessageRequestWithServiceId:(ServiceIdObjC *)serviceId
                                        messages:(NSArray<DeviceMessage *> *)messages
                                       timestamp:(uint64_t)timestamp
                                     udAccessKey:(nullable SMKUDAccessKey *)udAccessKey
                                        isOnline:(BOOL)isOnline
                                        isUrgent:(BOOL)isUrgent
                                         isStory:(BOOL)isStory
{
    // NOTE: messages may be empty; See comments in OWSDeviceManager.
    OWSAssertDebug(timestamp > 0);

    NSString *path = [self.textSecureMessagesAPI stringByAppendingString:serviceId.uuidValue.UUIDString];

    path = [path stringByAppendingFormat:@"?story=%@", isStory ? @"true" : @"false"];

    // Returns the per-account-message parameters used when submitting a message to
    // the Signal Web Service.
    // See
    // <https://github.com/signalapp/Signal-Server/blob/65da844d70369cb8b44966cfb2d2eb9b925a6ba4/service/src/main/java/org/whispersystems/textsecuregcm/entities/IncomingMessageList.java>.
    NSDictionary *parameters = @{
        @"messages" : [messages map:^id _Nonnull(DeviceMessage *_Nonnull item) { return [item requestParameters]; }],
        @"timestamp" : @(timestamp),
        @"online" : @(isOnline),
        @"urgent" : @(isUrgent)
    };

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"PUT" parameters:parameters];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    return request;
}

+ (TSRequest *)submitMultiRecipientMessageRequestWithCiphertext:(NSData *)ciphertext
                                           compositeUDAccessKey:(SMKUDAccessKey *)udAccessKey
                                                      timestamp:(uint64_t)timestamp
                                                       isOnline:(BOOL)isOnline
                                                       isUrgent:(BOOL)isUrgent
                                                        isStory:(BOOL)isStory
{
    OWSAssertDebug(ciphertext);
    OWSAssertDebug(udAccessKey);
    OWSAssertDebug(timestamp > 0);

    // We build the URL by hand instead of passing the query parameters into the query parameters
    // AFNetworking won't handle both query parameters and an httpBody (which we need here)
    NSURLComponents *components = [[NSURLComponents alloc] initWithString:self.textSecureMultiRecipientMessageAPI];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"ts" value:[@(timestamp) stringValue]],
        [NSURLQueryItem queryItemWithName:@"online" value:isOnline ? @"true" : @"false"],
        [NSURLQueryItem queryItemWithName:@"urgent" value:isUrgent ? @"true" : @"false"],
        [NSURLQueryItem queryItemWithName:@"story" value:isStory ? @"true" : @"false"],
    ];
    NSURL *url = [components URL];

    TSRequest *request = [TSRequest requestWithUrl:url method:@"PUT" parameters:nil];
    [request setValue:kSenderKeySendRequestBodyContentType forHTTPHeaderField:@"Content-Type"];
    if (udAccessKey != nil) {
        [self useUDAuthWithRequest:request accessKey:udAccessKey];
    }
    request.HTTPBody = [ciphertext copy];
    return request;
}

+ (TSRequest *)registerSignedPrekeyRequestForIdentity:(OWSIdentity)identity
                                         signedPreKey:(SignedPreKeyRecord *)signedPreKey
{
    OWSAssertDebug(signedPreKey);

    NSString *path = self.textSecureSignedKeysAPI;
    NSString *queryParam = [OWSRequestFactory queryParamFor:identity];
    if (queryParam != nil) {
        path = [path stringByAppendingFormat:@"?%@", queryParam];
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path]
                              method:@"PUT"
                          parameters:[self signedPreKeyRequestParameters:signedPreKey]];
}

#pragma mark - Storage Service

+ (TSRequest *)storageAuthRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/storage/auth"] method:@"GET" parameters:@{}];
}

#pragma mark - Remote Attestation

+ (TSRequest *)remoteAttestationAuthRequestForKeyBackup
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v1/backup/auth"] method:@"GET" parameters:@{}];
}

+ (TSRequest *)remoteAttestationAuthRequestForCDSI
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"v2/directory/auth"] method:@"GET" parameters:@{}];
}

#pragma mark - KBS

+ (TSRequest *)kbsEnclaveTokenRequestWithEnclaveName:(NSString *)enclaveName
                                        authUsername:(NSString *)authUsername
                                        authPassword:(NSString *)authPassword
                                             cookies:(NSArray<NSHTTPCookie *> *)cookies
{
    NSString *path = [NSString stringWithFormat:@"v1/token/%@", enclaveName];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];

    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Set the cookie header.
    // OWSURLSession disables default cookie handling for all requests.
    OWSAssertDebug(request.allHTTPHeaderFields.count == 0);
    [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];

    return request;
}

+ (TSRequest *)kbsEnclaveRequestWithRequestId:(NSData *)requestId
                                         data:(NSData *)data
                                      cryptIv:(NSData *)cryptIv
                                     cryptMac:(NSData *)cryptMac
                                  enclaveName:(NSString *)enclaveName
                                 authUsername:(NSString *)authUsername
                                 authPassword:(NSString *)authPassword
                                      cookies:(NSArray<NSHTTPCookie *> *)cookies
                                  requestType:(NSString *)requestType
{
    NSString *path = [NSString stringWithFormat:@"v1/backup/%@", enclaveName];

    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:path]
                                            method:@"PUT"
                                        parameters:@{
                                            @"requestId" : requestId.base64EncodedString,
                                            @"data" : data.base64EncodedString,
                                            @"iv" : cryptIv.base64EncodedString,
                                            @"mac" : cryptMac.base64EncodedString,
                                            @"type" : requestType
                                        }];

    request.authUsername = authUsername;
    request.authPassword = authPassword;

    // Set the cookie header.
    // OWSURLSession disables default cookie handling for all requests.
    OWSAssertDebug(request.allHTTPHeaderFields.count == 0);
    [request setAllHTTPHeaderFields:[NSHTTPCookie requestHeaderFieldsWithCookies:cookies]];

    return request;
}

#pragma mark - UD

+ (TSRequest *)udSenderCertificateRequestWithUuidOnly:(BOOL)uuidOnly
{
    NSString *path = @"v1/certificate/delivery?includeUuid=true";
    if (uuidOnly) {
        path = [path stringByAppendingString:@"&includeE164=false"];
    }
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

+ (void)useUDAuthWithRequest:(TSRequest *)request accessKey:(SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(request);
    OWSAssertDebug(udAccessKey);

    // Suppress normal auth headers.
    request.shouldHaveAuthorizationHeaders = NO;

    // Add UD auth header.
    [request setValue:[udAccessKey.keyData base64EncodedString] forHTTPHeaderField:@"Unidentified-Access-Key"];

    request.isUDRequest = YES;
}

#pragma mark - Profiles

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(NSData *)encryptedPaddedName
{
    const NSUInteger kEncodedNameLength = 108;

    NSString *base64EncodedName = [encryptedPaddedName base64EncodedString];
    NSString *urlEncodedName;
    // name length must match exactly
    if (base64EncodedName.length == kEncodedNameLength) {
        urlEncodedName = base64EncodedName.encodeURIComponent;
    } else {
        // if name length doesn't match exactly, use a blank name.
        // Since names are required, the server will reject this with HTTP405,
        // which is desirable - we want this request to fail rather than upload
        // a broken name.
        OWSFailDebug(@"Couldn't encode name.");
        OWSAssertDebug(encryptedPaddedName == nil);
        urlEncodedName = @"";
    }
    NSString *urlString = [NSString stringWithFormat:@"v1/profile/name/%@", urlEncodedName];

    NSURL *url = [NSURL URLWithString:urlString];
    TSRequest *request = [[TSRequest alloc] initWithURL:url];
    request.HTTPMethod = @"PUT";
    
    return request;
}

#pragma mark - Versioned Profiles

+ (TSRequest *)versionedProfileSetRequestWithName:(nullable ProfileValue *)name
                                              bio:(nullable ProfileValue *)bio
                                         bioEmoji:(nullable ProfileValue *)bioEmoji
                                        hasAvatar:(BOOL)hasAvatar
                                   paymentAddress:(nullable ProfileValue *)paymentAddress
                                  visibleBadgeIds:(NSArray<NSString *> *)visibleBadgeIds
                                          version:(NSString *)version
                                       commitment:(NSData *)commitment
                                             auth:(ChatServiceAuth *)auth
{
    OWSAssertDebug(version.length > 0);
    OWSAssertDebug(commitment.length > 0);

    NSString *base64EncodedCommitment = [commitment base64EncodedString];

    NSMutableDictionary<NSString *, NSObject *> *parameters = [@{
        @"version" : version,
        @"avatar" : @(hasAvatar),
        @"commitment" : base64EncodedCommitment,
    } mutableCopy];

    if (name != nil) {
        OWSAssertDebug(name.hasValidBase64Length);
        parameters[@"name"] = name.encryptedBase64;
    }
    if (bio != nil) {
        OWSAssertDebug(bio.hasValidBase64Length);
        parameters[@"about"] = bio.encryptedBase64;
    }
    if (bioEmoji != nil) {
        OWSAssertDebug(bioEmoji.hasValidBase64Length);
        parameters[@"aboutEmoji"] = bioEmoji.encryptedBase64;
    }
    if (paymentAddress != nil) {
        OWSAssertDebug(paymentAddress.hasValidBase64Length);
        parameters[@"paymentAddress"] = paymentAddress.encryptedBase64;
    }
    parameters[@"badgeIds"] = [visibleBadgeIds copy];

    NSURL *url = [NSURL URLWithString:self.textSecureVersionedProfileAPI];
    TSRequest *request = [TSRequest requestWithUrl:url method:@"PUT" parameters:parameters];
    [request setAuth:auth];
    return request;
}

#pragma mark - Remote Config

+ (TSRequest *)getRemoteConfigRequest
{
    NSURL *url = [NSURL URLWithString:@"/v1/config/"];
    return [TSRequest requestWithUrl:url method:@"GET" parameters:@{}];
}

#pragma mark - Groups v2

+ (TSRequest *)groupAuthenticationCredentialRequestWithFromRedemptionSeconds:(uint64_t)fromRedemptionSeconds
                                                         toRedemptionSeconds:(uint64_t)toRedemptionSeconds
{
    OWSAssertDebug(fromRedemptionSeconds > 0);
    OWSAssertDebug(toRedemptionSeconds > 0);

    NSString *path =
        [NSString stringWithFormat:@"/v1/certificate/auth/group?redemptionStartSeconds=%llu&redemptionEndSeconds=%llu",
                  (unsigned long long)fromRedemptionSeconds,
                  (unsigned long long)toRedemptionSeconds];
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - Payments

+ (TSRequest *)paymentsAuthenticationCredentialRequest
{
    NSString *path = @"/v1/payments/auth";
    return [TSRequest requestWithUrl:[NSURL URLWithString:path] method:@"GET" parameters:@{}];
}

#pragma mark - Spam

+ (TSRequest *)pushChallengeRequest
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge/push"] method:@"POST" parameters:@{}];
}

+ (TSRequest *)pushChallengeResponseWithToken:(NSString *)challengeToken
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge"]
                              method:@"PUT"
                          parameters:@{ @"type" : @"rateLimitPushChallenge", @"challenge" : challengeToken }];
}

+ (TSRequest *)recaptchChallengeResponseWithToken:(NSString *)serverToken captchaToken:(NSString *)captchaToken
{
    return [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/challenge"]
                              method:@"PUT"
                          parameters:@{ @"type" : @"recaptcha", @"token" : serverToken, @"captcha" : captchaToken }];
}

#pragma mark - Subscriptions

+ (TSRequest *)subscriptionCreateStripePaymentMethodRequest:(NSString *)base64SubscriberID
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/create_payment_method",
                                                      base64SubscriberID]]
                method:@"POST"
            parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionCreatePaypalPaymentMethodRequest:(NSString *)base64SubscriberID
                                                  returnUrl:(NSURL *)returnUrl
                                                  cancelUrl:(NSURL *)cancelUrl
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL
                           URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/create_payment_method/paypal",
                                                   base64SubscriberID]]
                method:@"POST"
            parameters:@{ @"returnUrl" : returnUrl.absoluteString, @"cancelUrl" : cancelUrl.absoluteString }];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionSetDefaultPaymentMethodRequest:(NSString *)base64SubscriberID
                                                processor:(NSString *)processor
                                                paymentID:(NSString *)paymentID
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL
                           URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/default_payment_method/%@/%@",
                                                   base64SubscriberID,
                                                   processor,
                                                   paymentID]]
                method:@"POST"
            parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionSetSubscriptionLevelRequest:(NSString *)base64SubscriberID level:(NSString *)level currency:(NSString *)currency idempotencyKey:(NSString *)idempotencyKey  {
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/level/%@/%@/%@", base64SubscriberID, level, currency, idempotencyKey]]
                                              method:@"PUT"
                                         parameters:@{}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionReceiptCredentialsRequest:(NSString *)base64SubscriberID
                                             request:(NSString *)base64ReceiptCredentialRequest
{
    TSRequest *request =  [TSRequest requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@/receipt_credentials", base64SubscriberID]]
                                              method:@"POST"
                                         parameters:@{@"receiptCredentialRequest" : base64ReceiptCredentialRequest}];
    request.shouldHaveAuthorizationHeaders = NO;
    request.shouldRedactUrlInLogs = YES;
    return request;
}

+ (TSRequest *)subscriptionRedeemReceiptCredential:(NSString *)base64ReceiptCredentialPresentation
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/donation/redeem-receipt"]
                                            method:@"POST"
                                        parameters:@{
                                            @"receiptCredentialPresentation" : base64ReceiptCredentialPresentation,
                                            @"visible" : @(self.subscriptionManager.displayBadgesOnProfile),
                                            @"primary" : @(NO)
                                        }];
    return request;
}

+ (TSRequest *)subscriptionGetCurrentSubscriptionLevelRequest:(NSString *)base64SubscriberID
{
    TSRequest *request = [TSRequest
        requestWithUrl:[NSURL URLWithString:[NSString stringWithFormat:@"/v1/subscription/%@", base64SubscriberID]]
                method:@"GET"
            parameters:@{}];
    request.shouldRedactUrlInLogs = YES;
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

+ (TSRequest *)boostReceiptCredentialsWithPaymentIntentId:(NSString *)paymentIntentId
                                               andRequest:(NSString *)base64ReceiptCredentialRequest
                                      forPaymentProcessor:(NSString *)processor
{
    TSRequest *request = [TSRequest requestWithUrl:[NSURL URLWithString:@"/v1/subscription/boost/receipt_credentials"]
                                            method:@"POST"
                                        parameters:@{
                                            @"paymentIntentId" : paymentIntentId,
                                            @"receiptCredentialRequest" : base64ReceiptCredentialRequest,
                                            @"processor" : processor
                                        }];
    request.shouldHaveAuthorizationHeaders = NO;
    return request;
}

@end

NS_ASSUME_NONNULL_END
