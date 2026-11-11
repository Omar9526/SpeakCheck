import Foundation
import Testing
@testable import SpeakCheck

@Suite(.serialized)
struct RemoteDocumentIDsTests {
    @Test func defaultsToLocalAndRemembersServerID() {
        let local = UUID(), server = UUID()
        #expect(RemoteDocumentIDs.server(for: local) == local)
        RemoteDocumentIDs.set(server, for: local)
        #expect(RemoteDocumentIDs.server(for: local) == server)
        RemoteDocumentIDs.set(local, for: local)  // совпадают — запись не нужна
        #expect(RemoteDocumentIDs.server(for: local) == local)
    }
}
