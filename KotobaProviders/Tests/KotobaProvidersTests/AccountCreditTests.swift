import Foundation
import KotobaCore
import Testing

@testable import KotobaProviders

/// Out of credit as the router finds it: a refusal for no credit marks the account, and the next transcript from it
/// clears the mark. No request is sent only to find it.
struct AccountCreditTests {
    @Test func aDictationRefusedForNoCreditMarksItsAccount() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let router = stub.provider()

        await #expect(throws: ProviderError.noCredit) { try await router.transcribe(stub.request()) }

        #expect(router.credit.isOut(.openRouter))
        #expect(!router.credit.isOut(.xai))
        #expect(!router.credit.isOut(.azure))
    }

    @Test func theNextTranscriptClearsTheMark() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let router = stub.provider()
        _ = try? await router.transcribe(stub.request())

        stub.reply(.fixture("success"))
        _ = try await router.transcribe(stub.request())

        #expect(!router.credit.isOut(.openRouter))
    }

    /// Any other failure says nothing about credit: the mark stays until a transcript comes.
    @Test(arguments: [StubReply.failure(.notConnectedToInternet), .raw(status: 503, body: ""), .status(401)])
    func otherFailuresKeepTheMark(reply: StubReply) async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let router = stub.provider()
        _ = try? await router.transcribe(stub.request())

        stub.reply(reply)
        _ = try? await router.transcribe(stub.request())

        #expect(router.credit.isOut(.openRouter))
    }

    /// History's "Transcribe Again With" on another account's model marks that account, not the owner's route.
    @Test func aRequestOnAnotherRouteMarksThatAccount() async throws {
        let stub = StubHost(reply: .raw(status: 402, body: ""))
        let router = stub.provider()
        var request = try stub.request()
        request.model = TranscriptionRoute.xaiGrok.rawValue

        _ = try? await router.transcribe(request)

        #expect(router.credit.isOut(.xai))
        #expect(!router.credit.isOut(.openRouter))
    }

    @Test(arguments: [
        (ProviderAccount.openRouter, StubReply.fixture("openrouter-key-spent")),
        (.xai, .fixture("xai-api-key-team-blocked")),
    ])
    func aKeyCheckWithNoCreditMarksTheAccount(account: ProviderAccount, reply: StubReply) async {
        let stub = StubHost(reply: reply)
        let router = stub.provider()

        #expect(await router.checkKey("new-key", for: account) == .noCredit)

        #expect(router.credit.isOut(account))
    }

    /// OpenRouter's key check reads the key's own limit, not the account's balance, so a valid key says nothing about
    /// the credit a dictation found missing.
    @Test func aValidKeyCheckKeepsTheMark() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let router = stub.provider()
        _ = try? await router.transcribe(stub.request())

        stub.reply(.fixture("openrouter-key"))
        #expect(await router.checkKey("sk-or-new", for: .openRouter) == .valid)

        #expect(router.credit.isOut(.openRouter))
    }

    @Test func eachChangeIsAnnounced() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let router = stub.provider()

        _ = try? await router.transcribe(stub.request())
        stub.reply(.fixture("success"))
        _ = try await router.transcribe(stub.request())

        #expect(router.credit.changeCount == 2)
    }

    /// A second refusal or a second transcript leaves the marks as they were: no reader wakes.
    @Test func aRequestThatChangesNothingIsNotAnnounced() async throws {
        let stub = StubHost(reply: .fixture("success"))
        let router = stub.provider()

        _ = try await router.transcribe(stub.request())
        stub.reply(.fixture("error-402", status: 402))
        _ = try? await router.transcribe(stub.request())
        _ = try? await router.transcribe(stub.request())

        #expect(router.credit.changeCount == 1)
    }
}

/// Cleanup and Rewrite run on OpenRouter whatever the speech model, so their answers mark the OpenRouter account too.
struct ChatCreditTests {
    @Test func aCleanupRefusedForNoCreditMarksOpenRouter() async {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let credit = AccountCredit()

        _ = try? await stub.cleaner(credit: credit).clean("fix the login bug", vocabulary: [], mode: .code)

        #expect(credit.isOut(.openRouter))
        #expect(!credit.isOut(.xai))
    }

    @Test func aRewriteRefusedForNoCreditMarksOpenRouter() async {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let credit = AccountCredit()

        _ = try? await stub.cleaner(credit: credit).polisher().polish("fix the login bug")

        #expect(credit.isOut(.openRouter))
    }

    @Test func aCleanupAnswerClearsTheMark() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let credit = AccountCredit()
        let cleaner = stub.cleaner(credit: credit)
        _ = try? await cleaner.clean("fix the login bug", vocabulary: [], mode: .code)

        stub.reply(.fixture("cleanup-success"))
        _ = try await cleaner.clean("fix the login bug", vocabulary: [], mode: .code)

        #expect(!credit.isOut(.openRouter))
    }

    @Test func aRewriteAnswerClearsTheMark() async throws {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let credit = AccountCredit()
        let polisher = stub.cleaner(credit: credit).polisher()
        _ = try? await polisher.polish("fix the login bug")

        stub.reply(.fixture("polish-success"))
        _ = try await polisher.polish("fix the login bug")

        #expect(!credit.isOut(.openRouter))
    }

    /// A cleanup that fails for another reason says nothing about credit.
    @Test(arguments: [StubReply.failure(.notConnectedToInternet), .raw(status: 503, body: ""), .status(401)])
    func otherChatFailuresKeepTheMark(reply: StubReply) async {
        let stub = StubHost(reply: .fixture("error-402", status: 402))
        let credit = AccountCredit()
        let cleaner = stub.cleaner(credit: credit)
        _ = try? await cleaner.clean("fix the login bug", vocabulary: [], mode: .code)

        stub.reply(reply)
        _ = try? await cleaner.clean("fix the login bug", vocabulary: [], mode: .code)

        #expect(credit.isOut(.openRouter))
    }
}
