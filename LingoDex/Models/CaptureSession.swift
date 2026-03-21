import Foundation

struct CaptureSession: Sendable, Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let date: Date
    var words: [WordEntry]
}

