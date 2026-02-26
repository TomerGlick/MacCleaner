import XCTest
import SwiftCheck
@testable import MacStorageCleanup

/// Base test class for Mac Storage Cleanup tests
final class MacStorageCleanupTests: XCTestCase {
    
    /// Verify that the testing framework is properly configured
    func testTestingFrameworkSetup() {
        XCTAssertTrue(true, "Testing framework is working")
    }
    
    /// Verify that SwiftCheck is properly configured
    func testSwiftCheckSetup() {
        // Simple property test to verify SwiftCheck is working
        property("Addition is commutative") <- forAll { (a: Int, b: Int) in
            return a + b == b + a
        }
    }
}
