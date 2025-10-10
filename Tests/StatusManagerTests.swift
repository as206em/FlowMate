import XCTest
@testable import FlowMate

@MainActor
final class StatusManagerTests: XCTestCase {
    
    var statusManager: StatusManager!
    
    override func setUp() {
        super.setUp()
        statusManager = StatusManager()
    }
    
    override func tearDown() {
        statusManager = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(statusManager.currentIcon, "checkmark.circle")
        XCTAssertEqual(statusManager.state, .idle)
        XCTAssertEqual(statusManager.priority, .app)
    }
    
    // MARK: - Icon Mapping Tests
    
    func testIconMapping() {
        XCTAssertEqual(StatusState.idle.iconName, "checkmark.circle")
        XCTAssertEqual(StatusState.processing.iconName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(StatusState.success.iconName, "checkmark.circle.fill")
        XCTAssertEqual(StatusState.failure.iconName, "exclamationmark.triangle.fill")
    }
    
    // MARK: - Priority Comparison Tests
    
    func testPriorityComparison() {
        XCTAssertTrue(StatusPriority.critical < StatusPriority.proofreading)
        XCTAssertTrue(StatusPriority.proofreading < StatusPriority.app)
        XCTAssertTrue(StatusPriority.critical < StatusPriority.app)
        
        XCTAssertFalse(StatusPriority.app < StatusPriority.critical)
        XCTAssertFalse(StatusPriority.proofreading < StatusPriority.critical)
    }
    
    // MARK: - Basic Update Tests
    
    func testUpdateStatusWithoutTimeout() {
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.currentIcon, "arrow.triangle.2.circlepath")
        XCTAssertEqual(statusManager.state, .processing)
        XCTAssertEqual(statusManager.priority, .proofreading)
    }
    
    func testUpdateStatusWithSuccessState() {
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.currentIcon, "checkmark.circle.fill")
        XCTAssertEqual(statusManager.state, .success)
    }
    
    func testUpdateStatusWithFailureState() {
        statusManager.updateStatus(
            state: .failure,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.currentIcon, "exclamationmark.triangle.fill")
        XCTAssertEqual(statusManager.state, .failure)
    }
    
    // MARK: - Priority Enforcement Tests
    
    func testLowerPriorityCannotOverrideHigherPriority() {
        // Set a high priority state
        statusManager.updateStatus(
            state: .processing,
            priority: .critical
        )
        XCTAssertEqual(statusManager.priority, .critical)
        XCTAssertEqual(statusManager.state, .processing)
        
        // Try to update with lower priority (should be ignored)
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading
        )
        
        // Should still be in processing state with critical priority
        XCTAssertEqual(statusManager.priority, .critical)
        XCTAssertEqual(statusManager.state, .processing)
        XCTAssertEqual(statusManager.currentIcon, "arrow.triangle.2.circlepath")
    }
    
    func testEqualPriorityCanOverride() {
        // Set initial state with proofreading priority
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        XCTAssertEqual(statusManager.state, .processing)
        
        // Update with same priority (should succeed)
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.state, .success)
        XCTAssertEqual(statusManager.currentIcon, "checkmark.circle.fill")
    }
    
    func testHigherPriorityCanOverrideLowerPriority() {
        // Set a low priority state
        statusManager.updateStatus(
            state: .success,
            priority: .app
        )
        XCTAssertEqual(statusManager.priority, .app)
        
        // Update with higher priority (should succeed)
        statusManager.updateStatus(
            state: .processing,
            priority: .critical
        )
        
        XCTAssertEqual(statusManager.priority, .critical)
        XCTAssertEqual(statusManager.state, .processing)
    }
    
    func testProofreadingCannotOverrideCritical() {
        statusManager.updateStatus(
            state: .failure,
            priority: .critical
        )
        
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        // Should remain in critical failure state
        XCTAssertEqual(statusManager.priority, .critical)
        XCTAssertEqual(statusManager.state, .failure)
    }
    
    func testAppCannotOverrideProofreading() {
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        statusManager.updateStatus(
            state: .idle,
            priority: .app
        )
        
        // Should remain in proofreading processing state
        XCTAssertEqual(statusManager.priority, .proofreading)
        XCTAssertEqual(statusManager.state, .processing)
    }
    
    // MARK: - Timeout Tests
    
    func testTimeoutReturnsToIdle() async {
        // Set a status with a short timeout
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading,
            timeout: 0.1  // 100ms
        )
        
        XCTAssertEqual(statusManager.state, .success)
        
        // Wait for timeout
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        
        // Should have returned to idle
        XCTAssertEqual(statusManager.state, .idle)
        XCTAssertEqual(statusManager.priority, .app)
        XCTAssertEqual(statusManager.currentIcon, "checkmark.circle")
    }
    
    func testTimeoutCancelledByNewUpdate() async {
        // Set a status with a longer timeout
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading,
            timeout: 1.0  // 1 second
        )
        
        // Wait a bit, but not for full timeout
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // Update with new status (should cancel timeout)
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.state, .processing)
        
        // Wait for original timeout period to pass
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        // Should still be in processing (not reverted to idle)
        // because the new update didn't have a timeout
        XCTAssertEqual(statusManager.state, .processing)
    }
    
    func testMultipleTimeouts() async {
        // First timeout
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading,
            timeout: 0.1
        )
        
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        XCTAssertEqual(statusManager.state, .idle)
        
        // Second timeout
        statusManager.updateStatus(
            state: .failure,
            priority: .proofreading,
            timeout: 0.1
        )
        
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        XCTAssertEqual(statusManager.state, .idle)
    }
    
    // MARK: - Manual Reset Tests
    
    func testManualResetToIdle() {
        statusManager.updateStatus(
            state: .processing,
            priority: .critical
        )
        
        XCTAssertEqual(statusManager.state, .processing)
        XCTAssertEqual(statusManager.priority, .critical)
        
        statusManager.resetToIdle()
        
        XCTAssertEqual(statusManager.state, .idle)
        XCTAssertEqual(statusManager.priority, .app)
        XCTAssertEqual(statusManager.currentIcon, "checkmark.circle")
    }
    
    func testManualResetCancelsTimeout() async {
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading,
            timeout: 0.5
        )
        
        // Immediately reset
        statusManager.resetToIdle()
        
        XCTAssertEqual(statusManager.state, .idle)
        
        // Wait for what would have been timeout
        try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms
        
        // Should still be idle (not affected by cancelled timeout)
        XCTAssertEqual(statusManager.state, .idle)
    }
    
    // MARK: - Complex Workflow Tests
    
    func testProofreadingWorkflow() async {
        // Start processing
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        XCTAssertEqual(statusManager.state, .processing)
        
        // Simulate success with timeout
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading,
            timeout: 0.1
        )
        XCTAssertEqual(statusManager.state, .success)
        
        // Wait for timeout
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(statusManager.state, .idle)
    }
    
    func testFailureWorkflowWithLongerTimeout() async {
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        statusManager.updateStatus(
            state: .failure,
            priority: .proofreading,
            timeout: 0.2  // 200ms
        )
        
        XCTAssertEqual(statusManager.state, .failure)
        
        // Wait for timeout
        try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms
        
        XCTAssertEqual(statusManager.state, .idle)
    }
    
    func testCriticalOverridesDuringProofreading() {
        // Proofreading in progress
        statusManager.updateStatus(
            state: .processing,
            priority: .proofreading
        )
        
        // Critical event occurs (higher priority)
        statusManager.updateStatus(
            state: .failure,
            priority: .critical
        )
        
        XCTAssertEqual(statusManager.state, .failure)
        XCTAssertEqual(statusManager.priority, .critical)
        
        // Proofreading tries to update (should be ignored)
        statusManager.updateStatus(
            state: .success,
            priority: .proofreading
        )
        
        XCTAssertEqual(statusManager.state, .failure)
        XCTAssertEqual(statusManager.priority, .critical)
    }
}
