import Testing
import Foundation
@testable import LongDeckCore

@Suite struct HTTPRequestParserTests {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    @Test func parsesCompleteRequest() {
        let raw = "POST /hook HTTP/1.1\r\nContent-Length: 5\r\nHost: x\r\n\r\nhello"
        let r = HTTPRequestParser.parse(data(raw))
        #expect(r == .request(HTTPRequest(method: "POST", path: "/hook",
                                          headers: ["content-length": "5", "host": "x"],
                                          body: data("hello"))))
    }

    @Test func needsMoreForPartialHeaderAndBody() {
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nContent-Le")) == .needMore)
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nContent-Length: 5\r\n\r\nhe")) == .needMore)
    }

    @Test func headerKeysLowercased() {
        guard case .request(let r) = HTTPRequestParser.parse(
            data("GET /x HTTP/1.1\r\nX-LongDeck-Token: abc\r\nX-Tmux-Pane: %3\r\n\r\n")) else {
            Issue.record("expected request"); return
        }
        #expect(r.headers["x-longdeck-token"] == "abc")
        #expect(r.headers["x-tmux-pane"] == "%3")
    }

    @Test func rejects() {
        #expect(HTTPRequestParser.parse(data("garbage\r\n\r\n")) == .failure(status: 400))
        #expect(HTTPRequestParser.parse(data("GET /x HTTP/2\r\n\r\n")) == .failure(status: 400))
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nHost: x\r\n\r\n")) == .failure(status: 411))
        let big = HTTPRequestParser.maxBodyBytes + 1
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nContent-Length: \(big)\r\n\r\n")) == .failure(status: 413))
        let huge = Data(repeating: 0x61, count: HTTPRequestParser.maxHeaderBytes + 1)
        #expect(HTTPRequestParser.parse(huge) == .failure(status: 431))
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n")) == .failure(status: 501))
        #expect(HTTPRequestParser.parse(data("POST /hook HTTP/1.1\r\nContent-Length: abc\r\n\r\n")) == .failure(status: 400))
    }

    @Test func ignoresBytesAfterBody() {
        guard case .request(let r) = HTTPRequestParser.parse(
            data("POST /hook HTTP/1.1\r\nContent-Length: 2\r\n\r\nabEXTRA")) else {
            Issue.record("expected request"); return
        }
        #expect(r.body == data("ab"))
    }
}
