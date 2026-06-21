import XCTest
import TamaCore

final class ProcessScannerTests: XCTestCase {
    func test_scan_includes_current_process() {
        let procs = SysctlProcessScanner().scan()
        XCTAssertFalse(procs.isEmpty, "scan should return running processes")
        let myPid = ProcessInfo.processInfo.processIdentifier
        let me = procs.first { $0.pid == myPid }
        XCTAssertNotNil(me, "scan should include the test runner process")
        XCTAssertNotNil(me?.execPath, "own exec path should be readable")
    }
}
