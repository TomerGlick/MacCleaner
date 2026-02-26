import XCTest
@testable import MacStorageCleanupApp

final class StorageViewModelTests: XCTestCase {
    
    @MainActor
    func testInitialState() {
        let viewModel = StorageViewModel()
        
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertEqual(viewModel.totalCapacity, 0)
        XCTAssertEqual(viewModel.usedSpace, 0)
        XCTAssertEqual(viewModel.availableSpace, 0)
        XCTAssertTrue(viewModel.categoryData.isEmpty)
    }
    
    @MainActor
    func testFormattedValues() {
        let viewModel = StorageViewModel()
        viewModel.totalCapacity = 500_000_000_000 // 500 GB
        viewModel.usedSpace = 350_000_000_000 // 350 GB
        viewModel.availableSpace = 150_000_000_000 // 150 GB
        
        XCTAssertFalse(viewModel.formattedTotalCapacity.isEmpty)
        XCTAssertFalse(viewModel.formattedUsedSpace.isEmpty)
        XCTAssertFalse(viewModel.formattedAvailableSpace.isEmpty)
    }
    
    @MainActor
    func testPercentageCalculations() {
        let viewModel = StorageViewModel()
        viewModel.totalCapacity = 1000
        viewModel.usedSpace = 700
        viewModel.availableSpace = 300
        
        XCTAssertEqual(viewModel.usedPercentage, 70.0, accuracy: 0.01)
        XCTAssertEqual(viewModel.availablePercentage, 30.0, accuracy: 0.01)
    }
    
    @MainActor
    func testPercentageWithZeroCapacity() {
        let viewModel = StorageViewModel()
        viewModel.totalCapacity = 0
        viewModel.usedSpace = 0
        viewModel.availableSpace = 0
        
        XCTAssertEqual(viewModel.usedPercentage, 0.0)
        XCTAssertEqual(viewModel.availablePercentage, 0.0)
    }
    
    @MainActor
    func testLoadStorageData() async {
        let viewModel = StorageViewModel()
        
        await viewModel.loadStorageData()
        
        XCTAssertFalse(viewModel.isLoading)
        // After loading, we should have some data (unless running in a test environment with no disk access)
        // The actual values will depend on the system
    }
}
