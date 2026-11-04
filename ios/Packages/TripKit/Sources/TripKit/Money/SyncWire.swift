import Foundation

// What the two phones say to each other (`LedgerSync` in the app), as JSON. Both builds that may meet must read
// each other: fields added later are optional (an older build leaves them out, and skips what it does not know),
// and a message an older build cannot read at all (`ack`, `nack`) is one it drops, as it drops anything it
// cannot read.

/// A greeting in the clear, then only signed messages.
public nonisolated enum SyncMessage: Codable, Sendable, Equatable {
    /// who this is: a name, a public key, this connection's random number, the UWB token if any, and the
    /// version of the sync it speaks (`LedgerSyncSession.version`; absent from builds before acknowledgements)
    case hello(name: String, key: Data, nonce: Data, token: Data?, v: Int?)
    /// a `SyncPayload`, numbered and signed with the connection's key
    case sealed(n: UInt64, body: Data, mac: Data)
}

/// What a signed message carries.
public nonisolated enum SyncPayload: Codable, Sendable, Equatable {
    /// this phone's install id, which names the rows it logged; sent only to a paired phone
    case intro(install: String)
    /// the whole ledger as the sender has stored it, and its `LedgerDigest` (absent from builds before
    /// acknowledgements)
    case state(LedgerState, digest: String?)
    /// the ledger with this digest is written on the phone that got it
    case ack(digest: String)
    /// the ledger with this digest could not be written there, and why
    case nack(digest: String, reason: String)
    /// the phones touched
    case touched
}
