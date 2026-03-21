import Foundation

struct Story: Sendable, Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let title: String
    let body: String
    let createdAt: Date
    let associatedWordIds: [UUID]
}

