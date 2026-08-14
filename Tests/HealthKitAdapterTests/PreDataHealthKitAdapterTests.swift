import TrainingApplication
import XCTest

@testable import HealthKitAdapter

final class PreDataHealthKitAdapterTests: XCTestCase {
  func testKeepsHealthAuthorizationInaccessibleDuringGateZero() async throws {
    let adapter = PreDataHealthKitAdapter()

    let result = try await adapter.requestAuthorization()

    XCTAssertEqual(result, .notRequested)
  }

  func testPagedOversizedRouteIsSimplifiedWithinRetentionMemoryAndTimeBounds() throws {
    let total = 50_000
    let input = (0..<total).map { index in
      let progress = Double(index) / Double(total - 1)
      let turn = 0.02 * sin(progress * .pi * 12)
      return HealthKitRouteCoordinate(
        northSouthDegrees: 14.5 + progress * 0.2,
        eastWestDegrees: 120.9 + progress * 0.2 + turn)
    }
    let clock = ContinuousClock()
    var durations: [Duration] = []
    var output: [HealthWorkoutRoutePoint] = []
    var peakBufferedPointCount = 0

    for _ in 0..<10 {
      var simplifier = BoundedHealthKitRouteSimplifier(maximumRetainedPoints: 2_000)
      let elapsed = clock.measure {
        for pageStart in stride(from: 0, to: input.count, by: 777) {
          simplifier.append(
            page: Array(input[pageStart..<min(input.count, pageStart + 777)]))
        }
        output = simplifier.finish()
      }
      durations.append(elapsed)
      peakBufferedPointCount = max(peakBufferedPointCount, simplifier.peakBufferedPointCount)
      XCTAssertEqual(simplifier.originalPointCount, total)
    }
    let p95Index = Int((Double(durations.count) * 0.95).rounded(.up)) - 1
    let p95 = durations.sorted()[p95Index]

    XCTAssertLessThanOrEqual(output.count, 2_000)
    XCTAssertLessThanOrEqual(peakBufferedPointCount, 4_001)
    XCTAssertEqual(output.first?.northSouthDegrees, input.first?.northSouthDegrees)
    XCTAssertEqual(output.last?.eastWestDegrees, input.last?.eastWestDegrees)
    XCTAssertTrue(output.contains { $0.eastWestDegrees > 121.09 })
    XCTAssertLessThan(p95, Duration.seconds(2))
  }
}
