import XCTest
@testable import CursorPocket

final class CloudAgentsClientTests: XCTestCase {
    func testEndpointURLPreservesAPIVersionForLeadingSlashPaths() throws {
        let url = try CloudAgentsClient.shared.endpointURL(path: "/me")

        XCTAssertEqual(url.absoluteString, "https://api.cursor.com/v1/me")
    }

    func testEndpointURLPreservesAPIVersionForNestedPathsAndQueries() throws {
        let url = try CloudAgentsClient.shared.endpointURL(path: "/agents?limit=50")

        XCTAssertEqual(url.absoluteString, "https://api.cursor.com/v1/agents?limit=50")
    }

    func testEndpointURLPreservesAPIVersionForStreamPaths() throws {
        let url = try CloudAgentsClient.shared.endpointURL(
            path: "agents/bc-123/runs/run-456/stream"
        )

        XCTAssertEqual(url.absoluteString, "https://api.cursor.com/v1/agents/bc-123/runs/run-456/stream")
    }
}
