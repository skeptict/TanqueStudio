import Foundation
import SwiftData

enum ImageSource: String, Codable {
    case generated
    case imported
    case dtProject
}

@Model
final class TSImage {
    var id: UUID
    var filePath: String
    var createdAt: Date
    var source: ImageSource
    var configJSON: String?   // GenerationConfig encoded as JSON
    var collection: String?   // subdirectory name, nil = root
    var batchID: UUID?        // groups batch/sequence results
    var batchIndex: Int?
    var thumbnailData: Data?  // cached thumbnail, optional

    init(
        id: UUID = UUID(),
        filePath: String,
        createdAt: Date = Date(),
        source: ImageSource,
        configJSON: String? = nil,
        collection: String? = nil,
        batchID: UUID? = nil,
        batchIndex: Int? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.createdAt = createdAt
        self.source = source
        self.configJSON = configJSON
        self.collection = collection
        self.batchID = batchID
        self.batchIndex = batchIndex
    }
}
