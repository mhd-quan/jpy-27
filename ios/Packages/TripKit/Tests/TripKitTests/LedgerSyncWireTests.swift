import Foundation
import Testing
@testable import TripKit

/// What goes between the phones must read both ways between this build and the one before acknowledgements
/// (b444f14 and earlier): two travellers do not update on the same day.
@Suite struct LedgerSyncWireTests {
    /// The shapes as the build before acknowledgements declares them.
    enum OldMessage: Codable, Equatable {
        case hello(name: String, key: Data, nonce: Data, token: Data?)
        case sealed(n: UInt64, body: Data, mac: Data)
    }

    enum OldPayload: Codable, Equatable {
        case intro(install: String)
        case state(LedgerState)
        case touched
    }

    let ledger = LedgerState(records: [LedgerRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, yen: 900,
                                                    category: "food", method: "cash", at: Date(timeIntervalSinceReferenceDate: 800_000_000),
                                                    origin: "a")],
                             tombstones: [LedgerTombstone(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                                          at: Date(timeIntervalSinceReferenceDate: 800_000_060))],
                             kept: ["k"])

    /// `ledger` as JSON, as either build writes it.
    let ledgerJSON = #"{"kept":["k"],"records":[{"at":800000000,"category":"food","id":"00000000-0000-0000-0000-000000000001","method":"cash","note":"","origin":"a","yen":900}],"tombstones":[{"at":800000060,"id":"00000000-0000-0000-0000-000000000002"}]}"#

    func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func read<T: Decodable>(_ type: T.Type, _ text: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(text.utf8))
    }

    @Test func anOldLedgerReadsWithNoDigest() {
        #expect(read(SyncPayload.self, #"{"state":{"_0":\#(ledgerJSON)}}"#) == .state(ledger, digest: nil))
    }

    @Test func anOldGreetingReadsWithNoVersion() {
        #expect(read(SyncMessage.self, #"{"hello":{"key":"AQ==","name":"Lan","nonce":"Ag=="}}"#)
            == .hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: nil, v: nil))
        #expect(read(SyncMessage.self, #"{"hello":{"key":"AQ==","name":"Lan","nonce":"Ag==","token":"Aw=="}}"#)
            == .hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: Data([3]), v: nil))
    }

    @Test func theOtherOldMessagesStillRead() {
        #expect(read(SyncPayload.self, #"{"intro":{"install":"PHONE-B"}}"#) == .intro(install: "PHONE-B"))
        #expect(read(SyncPayload.self, #"{"touched":{}}"#) == .touched)
        #expect(read(SyncMessage.self, #"{"sealed":{"body":"AQ==","mac":"Ag==","n":7}}"#)
            == .sealed(n: 7, body: Data([1]), mac: Data([2])))
    }

    @Test func whatThisBuildWritesIsPinned() throws {
        #expect(try json(SyncPayload.state(ledger, digest: "d1")) == #"{"state":{"_0":\#(ledgerJSON),"digest":"d1"}}"#)
        #expect(try json(SyncPayload.ack(digest: "d1")) == #"{"ack":{"digest":"d1"}}"#)
        #expect(try json(SyncPayload.nack(digest: "d1", reason: "disk full")) == #"{"nack":{"digest":"d1","reason":"disk full"}}"#)
        #expect(try json(SyncMessage.hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: nil, v: 2))
            == #"{"hello":{"key":"AQ==","name":"Lan","nonce":"Ag==","v":2}}"#)
    }

    @Test func anOldBuildReadsWhatThisOneSends() throws {
        let state = try JSONEncoder().encode(SyncPayload.state(ledger, digest: "d1"))
        #expect(try JSONDecoder().decode(OldPayload.self, from: state) == .state(ledger))
        let hello = try JSONEncoder().encode(SyncMessage.hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: Data([3]),
                                                               v: LedgerSyncSession.version))
        #expect(try JSONDecoder().decode(OldMessage.self, from: hello) == .hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: Data([3])))
        let intro = try JSONEncoder().encode(SyncPayload.intro(install: "PHONE-A"))
        #expect(try JSONDecoder().decode(OldPayload.self, from: intro) == .intro(install: "PHONE-A"))
    }

    /// An old build cannot read an ack or a nack: it drops it, as it drops anything it cannot read, and goes on.
    @Test func anOldBuildDropsAcksAndNacks() throws {
        for payload in [SyncPayload.ack(digest: "d1"), .nack(digest: "d1", reason: "disk full")] {
            let data = try JSONEncoder().encode(payload)
            #expect((try? JSONDecoder().decode(OldPayload.self, from: data)) == nil)
        }
    }

    @Test func everyMessageRoundTrips() throws {
        let payloads: [SyncPayload] = [.intro(install: "A"), .state(ledger, digest: "d"), .state(.empty, digest: nil),
                                       .ack(digest: "d"), .nack(digest: "d", reason: "r"), .touched]
        for p in payloads {
            #expect(try JSONDecoder().decode(SyncPayload.self, from: JSONEncoder().encode(p)) == p)
        }
        let messages: [SyncMessage] = [.hello(name: "Lan", key: Data([1]), nonce: Data([2]), token: nil, v: 2),
                                       .sealed(n: 1, body: Data([1]), mac: Data([2]))]
        for m in messages {
            #expect(try JSONDecoder().decode(SyncMessage.self, from: JSONEncoder().encode(m)) == m)
        }
    }
}
