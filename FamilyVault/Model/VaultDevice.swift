import Foundation
import UIKit

/// One of the (at most two) iPhones allowed to open this vault.
struct VaultDevice: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var model: String
    var addedAt: Date
    var lastSeenAt: Date

    static func current(id: String, name: String? = nil) -> VaultDevice {
        VaultDevice(
            id: id,
            name: name?.trimmingCharacters(in: .whitespaces).isEmpty == false ? name! : UIDevice.current.name,
            model: UIDevice.current.model,
            addedAt: Date(),
            lastSeenAt: Date()
        )
    }
}
