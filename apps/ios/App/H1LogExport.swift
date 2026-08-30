import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct H1LogExport: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .json) { export in
            SentTransferredFile(export.url)
        }
    }
}
