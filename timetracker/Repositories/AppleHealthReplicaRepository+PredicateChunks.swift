import Foundation

extension Set<UUID> {
    func chunkedForReplicaPredicate(
        limit: Int = 400
    ) -> [[UUID]] {
        let values = Array(self)
        return stride(from: 0, to: values.count, by: limit).map { offset in
            Array(values[offset ..< Swift.min(offset + limit, values.count)])
        }
    }
}
