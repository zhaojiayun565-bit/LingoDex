import Foundation

struct WordEntry: Sendable, Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let imageFileName: String
    let recognizedEnglish: String
    let learnWord: String
    let nativeWord: String
    var phoneticBreakdown: String? = nil
    let createdAt: Date
    var srs: SRSCardState
    var thumbnailData: Data? = nil
}

