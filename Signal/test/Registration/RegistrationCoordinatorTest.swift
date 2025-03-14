//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import Signal
@testable import SignalServiceKit
import XCTest

public class RegistrationCoordinatorTest: XCTestCase {

    // If we just use the force unwrap optional, switches are forced
    // to handle the none case.
    private var _mode: RegistrationMode!

    var mode: RegistrationMode {
        return self._mode
    }

    private var date = Date() {
        didSet {
            Stubs.date = date
        }
    }
    private var dateProvider: DateProvider!

    private var scheduler: TestScheduler!

    private var coordinator: RegistrationCoordinatorImpl!

    private var accountManagerMock: RegistrationCoordinatorImpl.TestMocks.AccountManager!
    private var appExpiryMock: RegistrationCoordinatorImpl.TestMocks.AppExpiry!
    private var changeNumberPniManager: ChangePhoneNumberPniManagerMock!
    private var contactsStore: RegistrationCoordinatorImpl.TestMocks.ContactsStore!
    private var experienceManager: RegistrationCoordinatorImpl.TestMocks.ExperienceManager!
    private var kbs: KeyBackupServiceMock!
    private var kbsAuthCredentialStore: KBSAuthCredentialStorageMock!
    private var mockMessagePipelineSupervisor: RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor!
    private var mockMessageProcessor: RegistrationCoordinatorImpl.TestMocks.MessageProcessor!
    private var mockURLSession: TSRequestOWSURLSessionMock!
    private var ows2FAManagerMock: RegistrationCoordinatorImpl.TestMocks.OWS2FAManager!
    private var preKeyManagerMock: RegistrationCoordinatorImpl.TestMocks.PreKeyManager!
    private var profileManagerMock: RegistrationCoordinatorImpl.TestMocks.ProfileManager!
    private var pushRegistrationManagerMock: RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager!
    private var receiptManagerMock: RegistrationCoordinatorImpl.TestMocks.ReceiptManager!
    private var sessionManager: RegistrationSessionManagerMock!
    private var storageServiceManagerMock: FakeStorageServiceManager!
    private var tsAccountManagerMock: RegistrationCoordinatorImpl.TestMocks.TSAccountManager!

    public override func setUp() {
        super.setUp()

        Stubs.date = date
        dateProvider = { self.date }

        accountManagerMock = RegistrationCoordinatorImpl.TestMocks.AccountManager()
        appExpiryMock = RegistrationCoordinatorImpl.TestMocks.AppExpiry()
        changeNumberPniManager = ChangePhoneNumberPniManagerMock()
        contactsStore = RegistrationCoordinatorImpl.TestMocks.ContactsStore()
        experienceManager = RegistrationCoordinatorImpl.TestMocks.ExperienceManager()
        kbs = KeyBackupServiceMock()
        kbsAuthCredentialStore = KBSAuthCredentialStorageMock()
        mockMessagePipelineSupervisor = RegistrationCoordinatorImpl.TestMocks.MessagePipelineSupervisor()
        mockMessageProcessor = RegistrationCoordinatorImpl.TestMocks.MessageProcessor()
        ows2FAManagerMock = RegistrationCoordinatorImpl.TestMocks.OWS2FAManager()
        preKeyManagerMock = RegistrationCoordinatorImpl.TestMocks.PreKeyManager()
        profileManagerMock = RegistrationCoordinatorImpl.TestMocks.ProfileManager()
        pushRegistrationManagerMock = RegistrationCoordinatorImpl.TestMocks.PushRegistrationManager()
        receiptManagerMock = RegistrationCoordinatorImpl.TestMocks.ReceiptManager()
        sessionManager = RegistrationSessionManagerMock()
        storageServiceManagerMock = FakeStorageServiceManager()
        tsAccountManagerMock = RegistrationCoordinatorImpl.TestMocks.TSAccountManager()

        let mockURLSession = TSRequestOWSURLSessionMock()
        self.mockURLSession = mockURLSession
        let mockSignalService = OWSSignalServiceMock()
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            return mockURLSession
        }

        scheduler = TestScheduler()

        let db = MockDB()

        let dependencies = RegistrationCoordinatorDependencies(
            accountManager: accountManagerMock,
            appExpiry: appExpiryMock,
            changeNumberPniManager: changeNumberPniManager,
            contactsManager: RegistrationCoordinatorImpl.TestMocks.ContactsManager(),
            contactsStore: contactsStore,
            dateProvider: { self.dateProvider() },
            db: db,
            experienceManager: experienceManager,
            kbs: kbs,
            kbsAuthCredentialStore: kbsAuthCredentialStore,
            keyValueStoreFactory: InMemoryKeyValueStoreFactory(),
            messagePipelineSupervisor: mockMessagePipelineSupervisor,
            messageProcessor: mockMessageProcessor,
            ows2FAManager: ows2FAManagerMock,
            preKeyManager: preKeyManagerMock,
            profileManager: profileManagerMock,
            pushRegistrationManager: pushRegistrationManagerMock,
            receiptManager: receiptManagerMock,
            remoteConfig: RegistrationCoordinatorImpl.TestMocks.RemoteConfig(),
            schedulers: TestSchedulers(scheduler: scheduler),
            signalRecipientShim: RegistrationCoordinatorImpl.TestMocks.SignalRecipient(),
            sessionManager: sessionManager,
            signalService: mockSignalService,
            storageServiceManager: storageServiceManagerMock,
            tsAccountManager: tsAccountManagerMock,
            udManager: RegistrationCoordinatorImpl.TestMocks.UDManager()
        )
        let loader = RegistrationCoordinatorLoaderImpl(dependencies: dependencies)
        coordinator = db.write {
            return loader.coordinator(
                forDesiredMode: mode,
                transaction: $0
            ) as! RegistrationCoordinatorImpl
        }
    }

    public override class var defaultTestSuite: XCTestSuite {
        let testSuite = XCTestSuite(name: NSStringFromClass(self))
        addTests(to: testSuite, mode: .registering)
        addTests(to: testSuite, mode: .reRegistering(e164: Stubs.e164))
        return testSuite
    }

    private class func addTests(
        to testSuite: XCTestSuite,
        mode: RegistrationMode
    ) {
        testInvocations.forEach { invocation in
            let testCase = RegistrationCoordinatorTest(invocation: invocation)
            testCase._mode = mode
            testSuite.addTest(testCase)
        }
    }

    private func executeTest(_ block: () -> Void) {
        XCTContext.runActivity(named: "\(self.name), mode:\(mode.testDescription)", block: { _ in
            block()
        })
    }

    private func executeTest(_ block: () throws -> Void) throws {
        try XCTContext.runActivity(named: "\(self.name), mode:\(mode.testDescription)", block: { _ in
            try block()
        })
    }

    // MARK: - Opening Path

    func testOpeningPath_splash() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            setupDefaultAccountAttributes()

            switch mode {
            case .registering:
                // With no state set up, should show the splash.
                XCTAssertEqual(coordinator.nextStep().value, .splash)
                // Once we show it, don't show it again.
                XCTAssertNotEqual(coordinator.continueFromSplash().value, .splash)
            case .reRegistering, .changingNumber:
                XCTAssertNotEqual(coordinator.nextStep().value, .splash)
            }
        }
    }

    func testOpeningPath_appExpired() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            appExpiryMock.isExpired = true

            setupDefaultAccountAttributes()

            // We should start with the banner.
            XCTAssertEqual(coordinator.nextStep().value, .appUpdateBanner)
        }
    }

    func testOpeningPath_permissions() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            setupDefaultAccountAttributes()

            contactsStore.doesNeedContactsAuthorization = true
            pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

            var nextStep: Guarantee<RegistrationStep>
            switch mode {
            case .registering:
                // Gotta get the splash out of the way.
                XCTAssertEqual(coordinator.nextStep().value, .splash)
                nextStep = coordinator.continueFromSplash()
            case .reRegistering, .changingNumber:
                // No splash for these.
                nextStep = coordinator.nextStep()
            }

            // Now we should show the permissions.
            XCTAssertEqual(nextStep.value, .permissions(Stubs.permissionsState()))
            // Doesn't change even if we try and proceed.
            XCTAssertEqual(coordinator.nextStep().value, .permissions(Stubs.permissionsState()))

            // Once the state is updated we can proceed.
            nextStep = coordinator.requestPermissions()
            XCTAssertNotNil(nextStep.value)
            XCTAssertNotEqual(nextStep.value, .splash)
            XCTAssertNotEqual(nextStep.value, .permissions(Stubs.permissionsState()))
        }
    }

    // MARK: - Reg Recovery Password Path

    func testRegRecoveryPwPath_happyPath() throws {
        try executeTest {
            try _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: false)
        }
    }

    func testRegRecoveryPwPath_happyPathWithReglock() throws {
        try executeTest {
            try _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: true)
        }
    }

    private func _runRegRecoverPwPathTestHappyPath(wasReglockEnabled: Bool) throws {
        // Don't care about timing, just start it.
        scheduler.start()

        // Set profile info so we skip those steps.
        setupDefaultAccountAttributes()

        ows2FAManagerMock.isReglockEnabledMock = { wasReglockEnabled }

        // Set a PIN on disk.
        ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

        // Make KBS give us back a reg recovery password.
        kbs.dataGenerator = {
            switch $0 {
            case .registrationRecoveryPassword:
                return Stubs.regRecoveryPwData
            case .registrationLock:
                return Stubs.reglockData
            default:
                return nil
            }
        }

        // NOTE: We expect to skip opening path steps because
        // if we have a KBS master key locally, this _must_ be
        // a previously registered device, and we can skip intros.

        // We haven't set a phone number so it should ask for that.
        XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

        // Give it a phone number, which should show the PIN entry step.
        var nextStep = coordinator.submitE164(Stubs.e164).value
        // Now it should ask for the PIN to confirm the user knows it.
        XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath()))

        // Give it the pin code, which should make it try and register.
        let expectedRequest = RegistrationRequestFactory.createAccountRequest(
            verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
            e164: Stubs.e164,
            authPassword: "", // Doesn't matter for request generation.
            accountAttributes: Stubs.accountAttributes(),
            skipDeviceTransfer: true
        )
        let identityResponse = Stubs.accountIdentityResponse()
        var authPassword: String!
        mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
            matcher: { request in
                // The password is generated internally by RegistrationCoordinator.
                // Extract it so we can check that the same password sent to the server
                // to register is used later for other requests.
                authPassword = request.authPassword
                let requestAttributes = Self.attributesFromCreateAccountRequest(request)
                if wasReglockEnabled {
                    XCTAssertEqual(Stubs.reglockData.hexadecimalString, requestAttributes.registrationLockToken)
                } else {
                    XCTAssertNil(requestAttributes.registrationLockToken)
                }
                return request.url == expectedRequest.url
            },
            statusCode: 200,
            bodyData: try JSONEncoder().encode(identityResponse)
        ))

        func expectedAuthedAccount() -> AuthedAccount {
            return .explicit(aci: identityResponse.aci, e164: Stubs.e164, authPassword: authPassword)
        }

        // When registered, it should try and sync push tokens.
        pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { auth in
            XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
            return .value(.success)
        }

        // When registered, we should create pre-keys.
        preKeyManagerMock.createPreKeysMock = { auth in
            XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
            return .value(())
        }

        if wasReglockEnabled {
            // If we had reglock before registration, it should be re-enabled.
            let expectedReglockRequest = OWSRequestFactory.enableRegistrationLockV2Request(token: Stubs.reglockToken)
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    return request.url == expectedReglockRequest.url
                },
                statusCode: 200,
                bodyData: nil
            ))
        }

        // We haven't done a kbs backup; that should happen now.
        kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
            XCTAssertEqual(pin, Stubs.pinCode)
            // We don't have a kbs auth credential, it should use chat server creds.
            XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
            XCTAssertFalse(rotateMasterKey)
            self.kbs.hasMasterKey = true
            return .value(())
        }

        // Once we sync push tokens, we should restore from storage service.
        accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
            XCTAssertEqual(auth, expectedAuthedAccount())
            return .value(())
        }

        // Once we do the storage service restore,
        // we will sync account attributes and then we are finished!
        let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
            Stubs.accountAttributes(),
            auth: .implicit() // doesn't matter for url matching
        )
        self.mockURLSession.addResponse(
            matcher: { request in
                return request.url == expectedAttributesRequest.url
            },
            statusCode: 200
        )

        nextStep = coordinator.submitPINCode(Stubs.pinCode).value
        XCTAssertEqual(nextStep, .done)
    }

    func testRegRecoveryPwPath_wrongPIN() throws {
        try executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            let wrongPinCode = "ABCD"

            // Set a different PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make KBS give us back a reg recovery password.
            kbs.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }

            // NOTE: We expect to skip opening path steps because
            // if we have a KBS master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164).value
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath()))

            // Give it the wrong PIN, it should reject and give us the same step again.
            nextStep = coordinator.submitPINCode(wrongPinCode).value
            XCTAssertEqual(
                nextStep,
                .pinEntry(Stubs.pinEntryStateForRegRecoveryPath(
                    error: .wrongPin(wrongPin: wrongPinCode),
                    remainingAttempts: 9
                ))
            )

            // Give it the right pin code, which should make it try and register.
            let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )

            let identityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                matcher: { request in
                    authPassword = request.authPassword
                    return request.url == expectedRequest.url
                },
                statusCode: 200,
                bodyData: try JSONEncoder().encode(identityResponse)
            ))

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(aci: identityResponse.aci, e164: Stubs.e164, authPassword: authPassword)
            }

            // When registered, it should try and sync push tokens.
            pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(.success)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.createPreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(())
            }

            // We haven't done a kbs backup; that should happen now.
            kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(pin, Stubs.pinCode)
                // We don't have a kbs auth credential, it should use chat server creds.
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                self.kbs.hasMasterKey = true
                return .value(())
            }

            // Once we sync push tokens, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount())
                return .value(())
            }

            // Once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            nextStep = coordinator.submitPINCode(Stubs.pinCode).value
            XCTAssertEqual(nextStep, .done)
        }
    }

    func testRegRecoveryPwPath_wrongPassword() {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make KBS give us back a reg recovery password.
            kbs.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            kbs.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a KBS master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath()))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )

            // Fail the request at t=2; the reg recovery pw is invalid.
            let failResponse = TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
                statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.unauthorized.rawValue
            )
            mockURLSession.addResponse(failResponse, atTime: 2, on: scheduler)

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Before requesting a session at t=2, it should ask for push tokens to give the session.
            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return .value(Stubs.apnsToken)
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            // Check we have the master key now, to be safe.
            XCTAssert(kbs.hasMasterKey)
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))
            // We want to have kept the master key; we failed the reg recovery pw check
            // but that could happen even if the key is valid. Once we finish session based
            // re-registration we want to be able to recover the key.
            XCTAssert(kbs.hasMasterKey)
        }
    }

    func testRegRecoveryPwPath_failedReglock() {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make KBS give us back a reg recovery password.
            kbs.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            kbs.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a KBS master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath()))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )

            // Fail the request at t=2; the reglock is invalid.
            let failResponse = TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedRecoveryPwRequest.url!.absoluteString,
                statusCode: RegistrationServiceResponses.AccountCreationResponseCodes.reglockFailed.rawValue,
                bodyJson: RegistrationServiceResponses.RegistrationLockFailureResponse(
                    timeRemainingMs: 10,
                    kbsAuthCredential: Stubs.kbsAuthCredential
                )
            )
            mockURLSession.addResponse(failResponse, atTime: 2, on: scheduler)

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Before requesting a session at t=2, it should ask for push tokens to give the session.
            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return .value(Stubs.apnsToken)
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            XCTAssert(kbs.hasMasterKey)
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))
            // We want to have wiped our master key; we failed reglock, which means the key itself is
            // wrong.
            XCTAssertFalse(kbs.hasMasterKey)
        }
    }

    func testRegRecoveryPwPath_retryNetworkError() throws {
        executeTest {
            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Set a PIN on disk.
            ows2FAManagerMock.pinCodeMock = { Stubs.pinCode }

            // Make KBS give us back a reg recovery password.
            kbs.dataGenerator = {
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }
            kbs.hasMasterKey = true

            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // NOTE: We expect to skip opening path steps because
            // if we have a KBS master key locally, this _must_ be
            // a previously registered device, and we can skip intros.

            // We haven't set a phone number so it should ask for that.
            XCTAssertEqual(coordinator.nextStep().value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should show the PIN entry step.
            var nextStep = coordinator.submitE164(Stubs.e164)
            // Now it should ask for the PIN to confirm the user knows it.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForRegRecoveryPath()))

            // Now we want to control timing so we can verify things happened in the right order.
            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it the pin code, which should make it try and register.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            let expectedRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )

            // Fail the request at t=2 with a network error.
            let failResponse = TSRequestOWSURLSessionMock.Response.networkError(url: expectedRecoveryPwRequest.url!)
            mockURLSession.addResponse(failResponse, atTime: 2, on: scheduler)

            let identityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!

            // Once the first request fails, at t=2, it should retry.
            scheduler.run(atTime: 1) {
                // Resolve with success at t=3
                let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                    verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                    e164: Stubs.e164,
                    authPassword: "", // Doesn't matter for request generation.
                    accountAttributes: Stubs.accountAttributes(),
                    skipDeviceTransfer: true
                )

                self.mockURLSession.addResponse(
                    TSRequestOWSURLSessionMock.Response(
                        matcher: { request in
                            // The password is generated internally by RegistrationCoordinator.
                            // Extract it so we can check that the same password sent to the server
                            // to register is used later for other requests.
                            authPassword = request.authPassword
                            return request.url == expectedRequest.url
                        },
                        statusCode: 200,
                        bodyData: try! JSONEncoder().encode(identityResponse)
                    ),
                    atTime: 3,
                    on: self.scheduler
                )
            }

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(aci: identityResponse.aci, e164: Stubs.e164, authPassword: authPassword)
            }

            // When registered at t=3, it should try and sync push tokens. Succeed at t=4
            pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 3)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.guarantee(resolvingWith: .success, atTime: 4)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.createPreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(())
            }

            // We haven't done a kbs backup; that should happen at t=4. Succeed at t=5.
            kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(self.scheduler.currentTime, 4)
                XCTAssertEqual(pin, Stubs.pinCode)
                // We don't have a kbs auth credential, it should use chat server creds.
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                self.kbs.hasMasterKey = true
                return self.scheduler.promise(resolvingWith: (), atTime: 5)
            }

            // Once we sync push tokens at t=5, we should restore from storage service.
            // Succeed at t=6.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 5)
                XCTAssertEqual(auth, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 6)
            }

            // Once we do the storage service restore at t=6,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    matcher: { request in
                        return request.url == expectedAttributesRequest.url
                    },
                    statusCode: 200,
                    bodyData: nil
                ),
                atTime: 7,
                on: scheduler
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 7)

            XCTAssertEqual(nextStep.value, .done)
        }
    }

    // MARK: - KBS Auth Credential Path

    func testKBSAuthCredentialPath_happyPath() {
        executeTest {
            // Run the scheduler for a bit; we don't care about timing these bits.
            scheduler.start()

            // Don't care about timing, just start it.
            setupDefaultAccountAttributes()

            // Set profile info so we skip those steps.
            self.setAllProfileInfo()

            // Put some auth credentials in storage.
            let credentialCandidates: [KBSAuthCredential] = [
                Stubs.kbsAuthCredential,
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
            ]
            kbsAuthCredentialStore.dict = Dictionary(grouping: credentialCandidates, by: \.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should cause it to check the auth credentials.
            // Match the main auth credential.
            let expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
                e164: Stubs.e164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(TSRequestOWSURLSessionMock.Response(
                urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
                statusCode: 200,
                bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                    "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .match,
                    "aaaa:abc": .notMatch,
                    "zzzz:xyz": .invalid,
                    "0000:123": .unknown
                ])
            ))

            let nextStep = coordinator.submitE164(Stubs.e164).value

            // At this point, we should be asking for PIN entry so we can use the credential
            // to recover the KBS master key.
            XCTAssertEqual(nextStep, .pinEntry(Stubs.pinEntryStateForKBSAuthCredentialPath()))
            // We should have wipted the invalid and unknown credentials.
            let remainingCredentials = kbsAuthCredentialStore.dict
            XCTAssertNotNil(remainingCredentials[Stubs.kbsAuthCredential.username])
            XCTAssertNotNil(remainingCredentials["aaaa"])
            XCTAssertNil(remainingCredentials["zzzz"])
            XCTAssertNil(remainingCredentials["0000"])

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Enter the PIN, which should try and recover from KBS.
            // Once we do that, it should follow the Reg Recovery Password Path.
            let nextStepPromise = coordinator.submitPINCode(Stubs.pinCode)

            // At t=1, resolve the key restoration from kbs and have it start returning the key.
            kbs.restoreKeysAndBackupMock = { pin, authMethod in
                XCTAssertEqual(self.scheduler.currentTime, 0)
                XCTAssertEqual(pin, Stubs.pinCode)
                XCTAssertEqual(authMethod, .kbsAuth(Stubs.kbsAuthCredential, backup: nil))
                self.kbs.hasMasterKey = true
                return self.scheduler.guarantee(resolvingWith: .success, atTime: 1)
            }

            // At t=1 it should get the latest credentials from kbs.
            self.kbs.dataGenerator = {
                XCTAssertEqual(self.scheduler.currentTime, 1)
                switch $0 {
                case .registrationRecoveryPassword:
                    return Stubs.regRecoveryPwData
                case .registrationLock:
                    return Stubs.reglockData
                default:
                    return nil
                }
            }

            // Now still at t=1 it should make a reg recovery pw request, resolve it at t=2.
            let accountIdentityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!
            let expectedRegRecoveryPwRequest = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: .recoveryPassword(Stubs.regRecoveryPw),
                e164: Stubs.e164,
                authPassword: "", // Doesn't matter for request generation.
                accountAttributes: Stubs.accountAttributes(),
                skipDeviceTransfer: true
            )
            self.mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    matcher: { request in
                        XCTAssertEqual(self.scheduler.currentTime, 1)
                        authPassword = request.authPassword
                        return request.url == expectedRegRecoveryPwRequest.url
                    },
                    statusCode: 200,
                    bodyJson: accountIdentityResponse
                ),
                atTime: 2,
                on: self.scheduler
            )

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(aci: accountIdentityResponse.aci, e164: Stubs.e164, authPassword: authPassword)
            }

            // When registered at t=2, it should try and sync push tokens.
            // Resolve at t=3.
            pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 2)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.guarantee(resolvingWith: .success, atTime: 3)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.createPreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(())
            }

            // At t=3 once we sync push tokens, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 3)
                XCTAssertEqual(auth, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 4)
            }

            // And at t=4 once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 4)
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            for i in 0...2 {
                scheduler.run(atTime: i) {
                    XCTAssertNil(nextStepPromise.value)
                }
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            XCTAssertEqual(nextStepPromise.value, .done)
        }
    }

    func testKBSAuthCredentialPath_noMatchingCredentials() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Put some auth credentials in storage.
            let credentialCandidates: [KBSAuthCredential] = [
                Stubs.kbsAuthCredential,
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "aaaa", password: "abc")),
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "zzzz", password: "xyz")),
                KBSAuthCredential(credential: RemoteAttestation.Auth(username: "0000", password: "123"))
            ]
            kbsAuthCredentialStore.dict = Dictionary(grouping: credentialCandidates, by: \.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            // Give it a phone number, which should cause it to check the auth credentials.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Don't give back any matches at t=2, which means we will want to create a session as a fallback.
            let expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
                e164: Stubs.e164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                        "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .notMatch,
                        "aaaa:abc": .notMatch,
                        "zzzz:xyz": .invalid,
                        "0000:123": .unknown
                    ])
                ),
                atTime: 2,
                on: scheduler
            )

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            pushRegistrationManagerMock.requestPushTokenMock = { .value(Stubs.apnsToken)}

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))

            // We should have wipted the invalid and unknown credentials.
            let remainingCredentials = kbsAuthCredentialStore.dict
            XCTAssertNotNil(remainingCredentials[Stubs.kbsAuthCredential.username])
            XCTAssertNotNil(remainingCredentials["aaaa"])
            XCTAssertNil(remainingCredentials["zzzz"])
            XCTAssertNil(remainingCredentials["0000"])
        }
    }

    func testKBSAuthCredentialPath_noMatchingCredentialsThenChangeNumber() {
        executeTest {
            // Don't care about timing, just start it.
            scheduler.start()

            // Set profile info so we skip those steps.
            setupDefaultAccountAttributes()

            // Put some auth credentials in storage.
            let credentialCandidates: [KBSAuthCredential] = [
                Stubs.kbsAuthCredential
            ]
            kbsAuthCredentialStore.dict = Dictionary(grouping: credentialCandidates, by: \.username).mapValues { $0.first! }

            // Get past the opening.
            goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            scheduler.stop()
            scheduler.adjustTime(to: 0)

            let originalE164 = E164("+17875550100")!
            let changedE164 = E164("+17875550101")!

            // Give it a phone number, which should cause it to check the auth credentials.
            var nextStep = coordinator.submitE164(originalE164)

            // Don't give back any matches at t=2, which means we will want to create a session as a fallback.
            var expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
                e164: originalE164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                        "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .notMatch
                    ])
                ),
                atTime: 2,
                on: scheduler
            )

            // Once the first request fails, at t=2, it should try an start a session.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we don't need to resolve it in this test.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(e164: originalE164, hasSentVerificationCode: false)),
                    atTime: 3
                )
            }

            // Then when it gets back the session at t=3, it should immediately ask for
            // a verification code to be sent.
            scheduler.run(atTime: 3) {
                // Resolve with an updated session at time 4.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(Stubs.session(hasSentVerificationCode: true)),
                    atTime: 4
                )
            }

            pushRegistrationManagerMock.requestPushTokenMock = { .value(Stubs.apnsToken)}

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 4)

            // Now we should expect to be at verification code entry since we already set the phone number.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))

            // We should have wiped the invalid and unknown credentials.
            let remainingCredentials = kbsAuthCredentialStore.dict
            XCTAssertNotNil(remainingCredentials[Stubs.kbsAuthCredential.username])

            // Now change the phone number; this should take us back to phone number entry.
            nextStep = coordinator.requestChangeE164()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))

            // Give it a phone number, which should cause it to check the auth credentials again.
            nextStep = coordinator.submitE164(changedE164)

            // Give a match at t=5, so it registers via kbs auth credential.
            expectedKBSCheckRequest = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
                e164: changedE164,
                credentials: credentialCandidates
            )
            mockURLSession.addResponse(
                TSRequestOWSURLSessionMock.Response(
                    urlSuffix: expectedKBSCheckRequest.url!.absoluteString,
                    statusCode: 200,
                    bodyJson: RegistrationServiceResponses.KBSAuthCheckResponse(matches: [
                        "\(Stubs.kbsAuthCredential.username):\(Stubs.kbsAuthCredential.credential.password)": .match
                    ])
                ),
                atTime: 5,
                on: scheduler
            )

            // Now it should ask for PIN entry; we are on the kbs auth credential path.
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForKBSAuthCredentialPath()))
        }
    }

    // MARK: - Session Path

    public func testSessionPath_happyPath() {
        executeTest {
            createSessionAndRequestFirstCode()

            scheduler.tick()

            var nextStep: Guarantee<RegistrationStep>!

            // Submit a code at t=5.
            scheduler.run(atTime: 5) {
                nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
            }

            // At t=7, give back a verified session.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: true
                )),
                atTime: 7
            )

            let accountIdentityResponse = Stubs.accountIdentityResponse()
            var authPassword: String!

            // That means at t=7 it should try and register with the verified
            // session; be ready for that starting at t=6 (but not before).
            scheduler.run(atTime: 6) {
                let expectedRequest = RegistrationRequestFactory.createAccountRequest(
                    verificationMethod: .sessionId(Stubs.sessionId),
                    e164: Stubs.e164,
                    authPassword: "", // Doesn't matter for request generation.
                    accountAttributes: Stubs.accountAttributes(),
                    skipDeviceTransfer: true
                )
                // Resolve it at t=8
                self.mockURLSession.addResponse(
                    TSRequestOWSURLSessionMock.Response(
                        matcher: { request in
                            authPassword = request.authPassword
                            return request.url == expectedRequest.url
                        },
                        statusCode: 200,
                        bodyJson: accountIdentityResponse
                    ),
                    atTime: 8,
                    on: self.scheduler
                )
            }

            func expectedAuthedAccount() -> AuthedAccount {
                return .explicit(aci: accountIdentityResponse.aci, e164: Stubs.e164, authPassword: authPassword)
            }

            // Once we are registered at t=8, we should try and sync push tokens
            // with the credentials we got in the identity response.
            pushRegistrationManagerMock.syncPushTokensForcingUploadMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 8)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return self.scheduler.guarantee(resolvingWith: .success, atTime: 9)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.createPreKeysMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 9)
                XCTAssertEqual(auth, expectedAuthedAccount().chatServiceAuth)
                return .value(())
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 9)

            // Now we should ask to create a PIN.
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForPostRegCreate()))

            // Confirm the pin first.
            nextStep = coordinator.setPINCodeForConfirmation(.stub())
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .pinEntry(Stubs.pinEntryStateForPostRegConfirm()))

            scheduler.adjustTime(to: 0)

            // When we submit the pin, it should backup with kbs.
            nextStep = coordinator.submitPINCode(Stubs.pinCode)

            // Finish the validation at t=1.
            kbs.generateAndBackupKeysMock = { pin, authMethod, rotateMasterKey in
                XCTAssertEqual(self.scheduler.currentTime, 0)
                XCTAssertEqual(pin, Stubs.pinCode)
                XCTAssertEqual(authMethod, .chatServerAuth(expectedAuthedAccount()))
                XCTAssertFalse(rotateMasterKey)
                return self.scheduler.promise(resolvingWith: (), atTime: 1)
            }

            // At t=1 once we sync push tokens, we should restore from storage service.
            accountManagerMock.performInitialStorageServiceRestoreMock = { auth in
                XCTAssertEqual(self.scheduler.currentTime, 1)
                XCTAssertEqual(auth, expectedAuthedAccount())
                return self.scheduler.promise(resolvingWith: (), atTime: 2)
            }

            // When registered, we should create pre-keys.
            preKeyManagerMock.createPreKeysMock = { auth in
                XCTAssertEqual(auth, expectedAuthedAccount())
                return .value(())
            }

            // And at t=2 once we do the storage service restore,
            // we will sync account attributes and then we are finished!
            let expectedAttributesRequest = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                Stubs.accountAttributes(),
                auth: .implicit() // doesn't matter for url matching
            )
            self.mockURLSession.addResponse(
                matcher: { request in
                    XCTAssertEqual(self.scheduler.currentTime, 2)
                    return request.url == expectedAttributesRequest.url
                },
                statusCode: 200
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            XCTAssertEqual(nextStep.value, .done)
        }
    }

    public func testSessionPath_invalidE164() {
        executeTest {
            setUpSessionPath()

            let badE164 = E164("+15555555555")!

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(badE164)

            // At t=2, reject for invalid argument (the e164).
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .invalidArgument,
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            // It should put us on the phone number entry screen again
            // with an error.
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: badE164,
                        withValidationErrorFor: .invalidArgument
                    )
                )
            )
        }
    }

    public func testSessionPath_rateLimitSessionCreation() {
        executeTest {
            setUpSessionPath()

            let retryTimeInterval: TimeInterval = 5

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, reject with a rate limit.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfter(retryTimeInterval),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)

            // It should put us on the phone number entry screen again
            // with an error.
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(retryTimeInterval)
                    )
                )
            )
        }
    }

    public func testSessionPath_cantSendFirstSMSCode() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session, but with SMS code rate limiting already.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 10,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // It should put us on the phone number entry screen again
            // with an error.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(10)
                    )
                )
            )
        }
    }

    public func testSessionPath_rateLimitFirstSMSCode() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Reject with a timeout.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .retryAfterTimeout(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 10,
                        nextCall: 0,
                        nextVerificationAttempt: nil,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // It should put us on the phone number entry screen again
            // with an error.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(
                    Stubs.phoneNumberEntryState(
                        mode: mode,
                        previouslyEnteredE164: Stubs.e164,
                        withValidationErrorFor: .retryAfter(10)
                    )
                )
            )
        }
    }

    public func testSessionPath_changeE164() {
        executeTest {
            setUpSessionPath()

            let originalE164 = E164("+17875550100")!
            let changedE164 = E164("+17875550101")!

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(originalE164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: originalE164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Give back a session with a sent code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: originalE164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // We should be on the verification code entry screen.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(
                    Stubs.verificationCodeEntryState(e164: originalE164)
                )
            )

            // Ask to change the number; this should put us back on phone number entry.
            nextStep = coordinator.requestChangeE164()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode))
            )

            // Give it the new phone number, which should cause it to start a session.
            nextStep = coordinator.submitE164(changedE164)

            // We'll ask for a push challenge, though we won't resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=5, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: changedE164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 5
            )

            // Once we get that session at t=5, we should try and send a code.
            // Be ready for that starting at t=4 (but not before).
            scheduler.run(atTime: 4) {
                // Give back a session with a sent code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: changedE164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 6
                )
            }

            // We should be on the verification code entry screen.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(
                    Stubs.verificationCodeEntryState(e164: changedE164)
                )
            )
        }
    }

    public func testSessionPath_captchaChallenge() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with a captcha challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should get a captcha step back.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.tick()

            // Submit a captcha challenge at t=4.
            scheduler.run(atTime: 4) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=6, give back a session without the challenge.
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 6
            )

            // That means at t=6 it should try and send a code;
            // be ready for that starting at t=5 (but not before).
            scheduler.run(atTime: 5) {
                // Resolve with a session at time 7.
                // The session has a sent code, but requires a challenge to send
                // a code again. That should be ignored until we ask to send another code.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.captcha],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 7
                )
            }

            // At t=7, we should get back the code entry step.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 7)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))

            // Now try and resend a code, which should hit us with the captcha challenge immediately.
            scheduler.start()
            XCTAssertEqual(coordinator.requestSMSCode().value, .captchaChallenge)
            scheduler.stop()

            // Submit a captcha challenge at t=8.
            scheduler.run(atTime: 8) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=10, give back a session without the challenge.
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 10
            )

            // This means at t=10 when we fulfill the challenge, it should
            // immediately try and send the code that couldn't be sent before because
            // of the challenge.
            // Reply to this at t=12.
            self.date = date.addingTimeInterval(10)
            let secondCodeDate = date
            scheduler.run(atTime: 9) {
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: secondCodeDate,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 12
                )
            }

            // Ensure that at t=11, before we've gotten the request code response,
            // we don't have a result yet.
            scheduler.run(atTime: 11) {
                XCTAssertNil(nextStep.value)
            }

            // Once all is done, we should have a new code and be back on the code
            // entry screen.
            // TODO[Registration]: test that the "next SMS code" state is properly set
            // given the new sms code date above.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 12)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))
        }
    }

    public func testSessionPath_pushChallenge() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // At t=3, give the push challenge token. Also prepare to handle its usage, and the
            // resulting request for another SMS code.
            scheduler.run(atTime: 3) {
                challengeTokenFuture.resolve("a pre-auth challenge token")

                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 4
                )

                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.pushChallenge],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 6
                )

                // We should still be waiting.
                XCTAssertNil(nextStep.value)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)

            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState())
            )
            XCTAssertEqual(
                sessionManager.latestChallengeFulfillment,
                .pushChallenge("a pre-auth challenge token")
            )
        }
    }

    public func testSessionPath_pushChallengeTimeoutAfterResolutionThatTakesTooLong() {
        executeTest {
            let sessionStartsAt = 2

            setUpSessionPath()

            dateProvider = { self.date.addingTimeInterval(TimeInterval(self.scheduler.currentTime)) }

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt)
                case 2:
                    let minWaitTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / self.scheduler.secondsPerTick)
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt + minWaitTime)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: sessionStartsAt
            )

            // Take too long to resolve with the challenge token.
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = sessionStartsAt + pushChallengeTimeout + 1
            scheduler.run(atTime: receiveChallengeTokenTime) {
                challengeTokenFuture.resolve("challenge token that should be ignored")
            }

            scheduler.advance(to: sessionStartsAt + pushChallengeTimeout - 1)
            XCTAssertNil(nextStep.value)

            scheduler.tick()
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime)

            // One time to set up, one time for the min wait time, one time
            // for the full timeout.
            XCTAssertEqual(receivePreAuthChallengeTokenCount, 3)
        }
    }

    public func testSessionPath_pushChallengeTimeoutAfterNoResolution() {
        executeTest {
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)

            let sessionStartsAt = 2
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll never provide a challenge token and will just leave it around forever.
            let (challengeTokenPromise, _) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt)
                case 2:
                    XCTAssertEqual(self.scheduler.currentTime, sessionStartsAt + pushChallengeMinTime)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with a push challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2 + pushChallengeMinTime + pushChallengeTimeout)
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))

            // One time to set up, one time for the min wait time, one time
            // for the full timeout.
            XCTAssertEqual(receivePreAuthChallengeTokenCount, 3)
        }
    }

    public func testSessionPath_pushChallengeWithoutPushNotificationsAvailable() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(nil)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we don't need to resolve it in this test.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return Guarantee<String>.pending().0
            }

            // Require a push challenge, which we won't be able to answer.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
            )
            XCTAssertNil(sessionManager.latestChallengeFulfillment)
        }
    }

    public func testSessionPath_preferPushChallengesIfWeCanAnswerThemImmediately() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Be ready to provide the push challenge token as soon as it's needed.
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return .value("a pre-auth challenge token")
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with multiple challenges.
            sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha, .pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Be ready to handle push challenges as soon as we can.
            scheduler.run(atTime: 2) {
                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 4
                )
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 5
                )
            }

            // We should still be waiting at t=4.
            scheduler.run(atTime: 4) {
                XCTAssertNil(nextStep.value)
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 5)

            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState())
            )
            XCTAssertEqual(
                sessionManager.latestChallengeFulfillment,
                .pushChallenge("a pre-auth challenge token")
            )
        }
    }

    public func testSessionPath_prefersCaptchaChallengesIfWeCannotAnswerPushChallengeQuickly() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 2)
                return challengeTokenPromise
            }

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge, .captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Take too long to resolve with the challenge token.
            let pushChallengeTimeout = Int(RegistrationCoordinatorImpl.Constants.pushTokenTimeout / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = pushChallengeTimeout + 1
            scheduler.run(atTime: receiveChallengeTokenTime - 1) {
                self.date = self.date.addingTimeInterval(TimeInterval(receiveChallengeTokenTime))
            }
            scheduler.run(atTime: receiveChallengeTokenTime) {
                challengeTokenFuture.resolve("challenge token that should be ignored")
            }

            // Once we get that session at t=2, we should wait a short time for the
            // push challenge token.
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)

            // After that, we should get a captcha step back, because we haven't
            // yet received the push challenge token.
            scheduler.advance(to: 2 + pushChallengeMinTime)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime)
        }
    }

    public func testSessionPath_pushChallengeFastResolution() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(Stubs.apnsToken)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // Prepare to provide the challenge token.
            let pushChallengeMinTime = Int(RegistrationCoordinatorImpl.Constants.pushTokenMinWaitTime / scheduler.secondsPerTick)
            let receiveChallengeTokenTime = 2 + pushChallengeMinTime - 1

            let (challengeTokenPromise, challengeTokenFuture) = Guarantee<String>.pending()
            var receivePreAuthChallengeTokenCount = 0
            pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                switch receivePreAuthChallengeTokenCount {
                case 0, 1:
                    XCTAssertEqual(self.scheduler.currentTime, 2)
                default:
                    XCTFail("Calling preAuthChallengeToken too many times")
                }
                receivePreAuthChallengeTokenCount += 1
                return challengeTokenPromise
            }

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.pushChallenge, .captcha],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Don't resolve the captcha token immediately, but quickly enough.
            scheduler.run(atTime: receiveChallengeTokenTime - 1) {
                self.date = self.date.addingTimeInterval(TimeInterval(pushChallengeMinTime - 1))
            }
            scheduler.run(atTime: receiveChallengeTokenTime) {
                // Also prep for the token's submission.
                self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: receiveChallengeTokenTime + 1
                )

                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: false,
                        requestedInformation: [.pushChallenge],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: receiveChallengeTokenTime + 2
                )

                challengeTokenFuture.resolve("challenge token")
            }

            // Once we get that session, we should wait a short time for the
            // push challenge token and fulfill it.
            scheduler.advance(to: receiveChallengeTokenTime + 2)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, receiveChallengeTokenTime + 2)

            XCTAssertEqual(receivePreAuthChallengeTokenCount, 2)
        }
    }

    public func testSessionPath_ignoresPushChallengesIfWeCannotEverAnswerThem() {
        executeTest {
            setUpSessionPath()

            pushRegistrationManagerMock.requestPushTokenMock = {
                XCTAssertEqual(self.scheduler.currentTime, 0)
                return .value(nil)
            }

            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with multiple challenges.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: self.date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha, .pushChallenge],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)
            XCTAssertNil(sessionManager.latestChallengeFulfillment)
        }
    }

    public func testSessionPath_unknownChallenge() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session with a captcha challenge and an unknown challenge.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [.captcha],
                    hasUnknownChallengeRequiringAppUpdate: true,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should get a captcha step back.
            // We have an unknown challenge, but we should do known challenges first!
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(nextStep.value, .captchaChallenge)

            scheduler.tick()

            // Submit a captcha challenge at t=4.
            scheduler.run(atTime: 4) {
                nextStep = self.coordinator.submitCaptcha(Stubs.captchaToken)
            }

            // At t=6, give back a session without the captcha but still with the
            // unknown challenge
            self.sessionManager.fulfillChallengeResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: false,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: true,
                    verified: false
                )),
                atTime: 6
            )

            // This means at t=6 we should get the app update banner.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 6)
            XCTAssertEqual(nextStep.value, .appUpdateBanner)
        }
    }

    public func testSessionPath_wrongVerificationCode() {
        executeTest {
            createSessionAndRequestFirstCode()

            // Now try and send the wrong code.
            let badCode = "garbage"

            // At t=1, give back a rejected argument response, its the wrong code.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .rejectedArgument(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 0,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            let nextStep = coordinator.submitVerificationCode(badCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    validationError: .invalidVerificationCode(invalidCode: badCode)
                ))
            )
        }
    }

    public func testSessionPath_verificationCodeTimeouts() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a retry response.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: 10,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    nextVerificationAttempt: 10,
                    validationError: .submitCodeTimeout
                ))
            )

            // Resend an sms code, time that out too at t=2.
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 7,
                    nextCall: 0,
                    nextVerificationAttempt: 9,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            nextStep = coordinator.requestSMSCode()

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 2)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    nextSMS: 7,
                    nextVerificationAttempt: 9,
                    validationError: .smsResendTimeout
                ))
            )

            // Resend an voice code, time that out too at t=4.
            // Make the timeout SO short that it retries at t=4.
            self.sessionManager.didRequestCode = false
            self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 6,
                    nextCall: 0.1,
                    nextVerificationAttempt: 8,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 4
            )

            // Be ready for the retry at t=4
            scheduler.run(atTime: 3) {
                // Ensure we called it the first time.
                XCTAssert(self.sessionManager.didRequestCode)
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .retryAfterTimeout(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 5,
                        nextCall: 4,
                        nextVerificationAttempt: 8,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 5
                )
            }

            nextStep = coordinator.requestVoiceCode()

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 5)
            XCTAssertEqual(
                nextStep.value,
                .verificationCodeEntry(Stubs.verificationCodeEntryState(
                    nextSMS: 5,
                    nextCall: 4,
                    nextVerificationAttempt: 8,
                    validationError: .voiceResendTimeout
                ))
            )
        }
    }

    public func testSessionPath_disallowedVerificationCode() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a disallowed response when submitting a code.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .disallowed(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
            )
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
            )
        }
    }

    public func testSessionPath_timedOutVerificationCodeWithoutRetries() {
        executeTest {
            createSessionAndRequestFirstCode()

            // At t=1, give back a retry response when submitting a code,
            // but with no ability to resubmit.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .retryAfterTimeout(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 1
            )

            var nextStep = coordinator.submitVerificationCode(Stubs.verificationCode)

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 1)
            XCTAssertEqual(
                nextStep.value,
                .showErrorSheet(.verificationCodeSubmissionUnavailable)
            )
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(
                nextStep.value,
                .phoneNumberEntry(Stubs.phoneNumberEntryState(
                    mode: mode,
                    previouslyEnteredE164: Stubs.e164
                ))
            )
        }
    }

    public func testSessionPath_expiredSession() {
        executeTest {
            setUpSessionPath()

            // Give it a phone number, which should cause it to start a session.
            var nextStep = coordinator.submitE164(Stubs.e164)

            // At t=2, give back a session thats ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a verification code.
            // Have that ready to go at t=1.
            scheduler.run(atTime: 1) {
                // We'll ask for a push challenge, though we won't resolve it.
                self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                    return Guarantee<String>.pending().0
                }

                // Resolve with a session at time 3.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)

            // Now we should expect to be at verification code entry since we sent the code.
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))

            scheduler.tick()

            // Submit a code at t=5.
            scheduler.run(atTime: 5) {
                nextStep = self.coordinator.submitVerificationCode(Stubs.pinCode)
            }

            // At t=7, give back an expired session.
            self.sessionManager.submitCodeResponse = self.scheduler.guarantee(
                resolvingWith: .invalidSession,
                atTime: 7
            )

            // That means at t=7 it should show an error, and then phone number entry.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 7)
            XCTAssertEqual(nextStep.value, .showErrorSheet(.sessionInvalidated))
            nextStep = coordinator.nextStep()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .phoneNumberEntry(Stubs.phoneNumberEntryState(
                mode: mode,
                previouslyEnteredE164: Stubs.e164
            )))
        }
    }

    // MARK: - Profile Setup Path

    // TODO[Registration]: test the profile setup steps.

    // MARK: Happy Path Setups

    private func preservingSchedulerState(_ block: () -> Void) {
        let startTime = scheduler.currentTime
        let wasRunning = scheduler.isRunning
        scheduler.stop()
        scheduler.adjustTime(to: 0)
        block()
        scheduler.adjustTime(to: startTime)
        if wasRunning {
            scheduler.start()
        }
    }

    private func goThroughOpeningHappyPath(expectedNextStep: RegistrationStep) {
        preservingSchedulerState {
            contactsStore.doesNeedContactsAuthorization = true
            pushRegistrationManagerMock.doesNeedNotificationAuthorization = true

            var nextStep: Guarantee<RegistrationStep>!
            switch mode {
            case .registering:
                // Gotta get the splash out of the way.
                nextStep = coordinator.nextStep()
                scheduler.runUntilIdle()
                XCTAssertEqual(nextStep.value, .splash)
            case .reRegistering, .changingNumber:
                break
            }

            // Now we should show the permissions.
            nextStep = coordinator.continueFromSplash()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, .permissions(Stubs.permissionsState()))

            // Once the state is updated we can proceed.
            nextStep = coordinator.requestPermissions()
            scheduler.runUntilIdle()
            XCTAssertEqual(nextStep.value, expectedNextStep)
        }
    }

    private func setUpSessionPath() {
        // Set profile info so we skip those steps.
        self.setupDefaultAccountAttributes()

        pushRegistrationManagerMock.requestPushTokenMock = { .value(Stubs.apnsToken) }

        pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = { .pending().0 }

        // No other setup; no auth credentials, kbs keys, etc in storage
        // so that we immediately go to the session flow.

        // Get past the opening.
        goThroughOpeningHappyPath(expectedNextStep: .phoneNumberEntry(Stubs.phoneNumberEntryState(mode: mode)))
    }

    private func createSessionAndRequestFirstCode() {
        setUpSessionPath()

        preservingSchedulerState {
            // Give it a phone number, which should cause it to start a session.
            let nextStep = coordinator.submitE164(Stubs.e164)

            // We'll ask for a push challenge, though we won't resolve it.
            self.pushRegistrationManagerMock.receivePreAuthChallengeTokenMock = {
                return Guarantee<String>.pending().0
            }

            // At t=2, give back a session that's ready to go.
            self.sessionManager.beginSessionResponse = self.scheduler.guarantee(
                resolvingWith: .success(RegistrationSession(
                    id: Stubs.sessionId,
                    e164: Stubs.e164,
                    receivedDate: date,
                    nextSMS: 0,
                    nextCall: 0,
                    nextVerificationAttempt: nil,
                    allowedToRequestCode: true,
                    requestedInformation: [],
                    hasUnknownChallengeRequiringAppUpdate: false,
                    verified: false
                )),
                atTime: 2
            )

            // Once we get that session at t=2, we should try and send a code.
            // Be ready for that starting at t=1 (but not before).
            scheduler.run(atTime: 1) {
                // Resolve with a session thats ready for code submission at time 3.
                self.sessionManager.requestCodeResponse = self.scheduler.guarantee(
                    resolvingWith: .success(RegistrationSession(
                        id: Stubs.sessionId,
                        e164: Stubs.e164,
                        receivedDate: self.date,
                        nextSMS: 0,
                        nextCall: 0,
                        nextVerificationAttempt: 0,
                        allowedToRequestCode: true,
                        requestedInformation: [],
                        hasUnknownChallengeRequiringAppUpdate: false,
                        verified: false
                    )),
                    atTime: 3
                )
            }

            // At t=3 we should get back the code entry step.
            scheduler.runUntilIdle()
            XCTAssertEqual(scheduler.currentTime, 3)
            XCTAssertEqual(nextStep.value, .verificationCodeEntry(Stubs.verificationCodeEntryState()))
        }
    }

    // MARK: - Helpers

    private func setupDefaultAccountAttributes() {
        ows2FAManagerMock.pinCodeMock = { nil }
        ows2FAManagerMock.isReglockEnabledMock = { false }

        tsAccountManagerMock.isManualMessageFetchEnabledMock = { false }

        setAllProfileInfo()
    }

    private func setAllProfileInfo() {
        tsAccountManagerMock.hasDefinedIsDiscoverableByPhoneNumberMock = { true }
        profileManagerMock.hasProfileNameMock = { true }
    }

    private static func attributesFromCreateAccountRequest(
        _ request: TSRequest
    ) -> AccountAttributes {
        let accountAttributesData = try! JSONSerialization.data(
            withJSONObject: request.parameters["accountAttributes"]!,
            options: .fragmentsAllowed
        )
        return try! JSONDecoder().decode(
            AccountAttributes.self,
            from: accountAttributesData
        )
    }

    // MARK: - Stubs

    private enum Stubs {

        static let e164 = E164("+17875550100")!
        static let pinCode = "1234"

        static let regRecoveryPwData = Data(repeating: 8, count: 8)
        static var regRecoveryPw: String { regRecoveryPwData.base64EncodedString() }

        static let reglockData = Data(repeating: 7, count: 8)
        static var reglockToken: String { reglockData.hexadecimalString }

        static let kbsAuthCredential = KBSAuthCredential(credential: RemoteAttestation.Auth(username: "abcd", password: "xyz"))

        static let captchaToken = "captchaToken"
        static let apnsToken = "apnsToken"

        static let authUsername = "username_jdhfsalkjfhd"
        static let authPassword = "password_dskafjasldkfjasf"

        static let sessionId = UUID().uuidString
        static let verificationCode = "8888"

        static var date: Date!

        static func accountAttributes() -> AccountAttributes {
            return AccountAttributes(
                isManualMessageFetchEnabled: false,
                registrationId: 0,
                pniRegistrationId: 0,
                unidentifiedAccessKey: "",
                unrestrictedUnidentifiedAccess: false,
                twofaMode: .none,
                registrationRecoveryPassword: nil,
                encryptedDeviceName: nil,
                discoverableByPhoneNumber: false,
                canReceiveGiftBadges: false,
                hasKBSBackups: true
            )
        }

        static func accountIdentityResponse() -> RegistrationServiceResponses.AccountIdentityResponse {
            return RegistrationServiceResponses.AccountIdentityResponse(
                aci: UUID(),
                pni: UUID(),
                e164: e164,
                username: nil,
                hasPreviouslyUsedKBS: false
            )
        }

        static func session(
            e164: E164 = Stubs.e164,
            hasSentVerificationCode: Bool
        ) -> RegistrationSession {
            return RegistrationSession(
                id: UUID().uuidString,
                e164: e164,
                receivedDate: date,
                nextSMS: 0,
                nextCall: 0,
                nextVerificationAttempt: hasSentVerificationCode ? 0 : nil,
                allowedToRequestCode: true,
                requestedInformation: [],
                hasUnknownChallengeRequiringAppUpdate: false,
                verified: false
            )
        }

        // MARK: Step States

        static func permissionsState() -> RegistrationPermissionsState {
            return RegistrationPermissionsState(shouldRequestAccessToContacts: true)
        }

        static func pinEntryStateForRegRecoveryPath(
            error: RegistrationPinValidationError? = nil,
            remainingAttempts: UInt? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: remainingAttempts),
                error: error
            )
        }

        static func pinEntryStateForKBSAuthCredentialPath(
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                error: error
            )
        }

        static func phoneNumberEntryState(
            mode: RegistrationMode,
            previouslyEnteredE164: E164? = nil,
            withValidationErrorFor response: Registration.BeginSessionResponse = .success(Stubs.session(hasSentVerificationCode: false))
        ) -> RegistrationPhoneNumberState {
            let validationError: RegistrationPhoneNumberValidationError?
            switch response {
            case .success:
                validationError = nil
            case .invalidArgument:
                validationError = .invalidNumber(invalidE164: previouslyEnteredE164 ?? Stubs.e164)
            case .retryAfter(let timeInterval):
                validationError = .rateLimited(expiration: self.date.addingTimeInterval(timeInterval))
            case .networkFailure, .genericError:
                XCTFail("Should not be generating phone number state for error responses.")
                validationError = nil
            }

            let phoneNumberMode: RegistrationPhoneNumberState.RegistrationPhoneNumberMode
            switch mode {
            case .registering:
                phoneNumberMode = .initialRegistration(previouslyEnteredE164: previouslyEnteredE164)
            case .reRegistering(let e164):
                phoneNumberMode = .reregistration(e164: e164)
            case .changingNumber(let changeNumberParams):
                phoneNumberMode = .changingPhoneNumber(oldE164: changeNumberParams.oldE164)
            }
            return RegistrationPhoneNumberState(
                mode: phoneNumberMode,
                validationError: validationError
            )
        }

        static func verificationCodeEntryState(
            e164: E164 = Stubs.e164,
            nextSMS: TimeInterval? = 0,
            nextCall: TimeInterval? = 0,
            nextVerificationAttempt: TimeInterval = 0,
            validationError: RegistrationVerificationValidationError? = nil
        ) -> RegistrationVerificationState {
            return RegistrationVerificationState(
                e164: e164,
                nextSMSDate: nextSMS.map { date.addingTimeInterval($0) },
                nextCallDate: nextCall.map { date.addingTimeInterval($0) },
                nextVerificationAttemptDate: date.addingTimeInterval(nextVerificationAttempt),
                validationError: validationError
            )
        }

        static func pinEntryStateForSessionPathReglock(
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(canSkip: false, remainingAttempts: nil),
                error: error
            )
        }

        static func pinEntryStateForPostRegRestore(
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .enteringExistingPin(canSkip: true, remainingAttempts: nil),
                error: error
            )
        }

        static func pinEntryStateForPostRegCreate() -> RegistrationPinState {
            return RegistrationPinState(operation: .creatingNewPin, error: nil)
        }

        static func pinEntryStateForPostRegConfirm(
            error: RegistrationPinValidationError? = nil
        ) -> RegistrationPinState {
            return RegistrationPinState(
                operation: .confirmingNewPin(.stub()),
                error: error
            )
        }
    }
}

extension RegistrationMode {

    var testDescription: String {
        switch self {
        case .registering:
            return "registering"
        case .reRegistering:
            return "re-registering"
        case .changingNumber:
            return "changing number"
        }
    }
}
