import CryptoKit
import Foundation

/// Generates RFC 9562 UUIDv8 identities from a frozen domain and canonical
/// string components. Domain strings and component ordering are persistence
/// contracts: changing either would create sibling records across app versions.
nonisolated enum DeterministicUUID {
    static func version8(
        domain: String,
        components: [String]
    ) -> UUID {
        let name = ([domain] + components).joined(separator: "\u{0}")
        var bytes = Array(
            SHA256.hash(data: Data(name.utf8)).prefix(16)
        )
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
