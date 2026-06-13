import XCTest
@testable import CursorPocket

final class CloudAgentsClientTests: XCTestCase {
    func testEndpointURLPreservesAPIVersionForAbsolutePaths() throws {
        let client = CloudAgentsClient.shared

        XCTAssertEqual(
            try client.endpointURL(path: "/me").absoluteString,
            "https://api.cursor.com/v1/me"
        )
        XCTAssertEqual(
            try client.endpointURL(path: "/agents?limit=50").absoluteString,
            "https://api.cursor.com/v1/agents?limit=50"
        )
    }

    func testEndpointURLBuildsStreamPathWithoutEncodingSeparators() throws {
        let url = try CloudAgentsClient.shared.endpointURL(
            path: "/agents/agent-123/runs/run-456/stream"
        )

        XCTAssertEqual(url.path, "/v1/agents/agent-123/runs/run-456/stream")
        XCTAssertFalse(url.absoluteString.contains("%2F"))
    }
}
