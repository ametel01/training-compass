import Foundation
import TrainingApplication

/// Adapter-owned decoded coordinate. Values of this type never cross the
/// application boundary or enter persistence.
struct HealthKitRouteCoordinate: Equatable, Sendable {
  let northSouthDegrees: Double
  let eastWestDegrees: Double

  init(northSouthDegrees: Double, eastWestDegrees: Double) {
    self.northSouthDegrees = northSouthDegrees
    self.eastWestDegrees = eastWestDegrees
  }

  var isValid: Bool {
    northSouthDegrees.isFinite
      && eastWestDegrees.isFinite
      && (-90...90).contains(northSouthDegrees)
      && (-180...180).contains(eastWestDegrees)
  }
}

/// Incrementally consumes HealthKit pages and periodically reduces its private
/// buffer. At no point does it retain the complete original geometry.
struct BoundedHealthKitRouteSimplifier: Sendable {
  let maximumRetainedPoints: Int
  let maximumBufferedPoints: Int
  private var buffered: [HealthKitRouteCoordinate] = []
  private(set) var originalPointCount = 0
  private(set) var peakBufferedPointCount = 0

  init(maximumRetainedPoints: Int) {
    precondition(maximumRetainedPoints >= 2)
    precondition(maximumRetainedPoints <= HealthWorkoutRoute.maximumRetainedPoints)
    self.maximumRetainedPoints = maximumRetainedPoints
    self.maximumBufferedPoints = maximumRetainedPoints * 2
    buffered.reserveCapacity(maximumBufferedPoints + 1)
  }

  mutating func append(page: [HealthKitRouteCoordinate]) {
    for point in page where point.isValid {
      originalPointCount += 1
      buffered.append(point)
      peakBufferedPointCount = max(peakBufferedPointCount, buffered.count)
      if buffered.count > maximumBufferedPoints {
        buffered = Self.simplify(buffered, retaining: maximumRetainedPoints)
      }
    }
  }

  mutating func finish() -> [HealthWorkoutRoutePoint] {
    if buffered.count > maximumRetainedPoints {
      buffered = Self.simplify(buffered, retaining: maximumRetainedPoints)
    }
    return buffered.map {
      HealthWorkoutRoutePoint(
        northSouthDegrees: $0.northSouthDegrees,
        eastWestDegrees: $0.eastWestDegrees)
    }
  }

  private struct Segment: Sendable {
    let start: Int
    let end: Int
    let candidate: Int
    let distanceSquared: Double
  }

  /// Retains the points selected by a bounded Ramer-Douglas-Peucker split.
  /// A max heap makes the cap exact while keeping endpoints and the largest
  /// path deviations first.
  private static func simplify(
    _ points: [HealthKitRouteCoordinate],
    retaining targetCount: Int
  ) -> [HealthKitRouteCoordinate] {
    guard points.count > targetCount else { return points }
    var retained = Array(repeating: false, count: points.count)
    retained[0] = true
    retained[points.count - 1] = true
    var retainedCount = 2
    var heap: [Segment] = []
    if let initial = segment(in: points, start: 0, end: points.count - 1) {
      heapAppend(initial, to: &heap)
    }

    while retainedCount < targetCount, let next = heapPop(from: &heap) {
      guard !retained[next.candidate] else { continue }
      retained[next.candidate] = true
      retainedCount += 1
      if let left = segment(in: points, start: next.start, end: next.candidate) {
        heapAppend(left, to: &heap)
      }
      if let right = segment(in: points, start: next.candidate, end: next.end) {
        heapAppend(right, to: &heap)
      }
    }

    return points.indices.compactMap { retained[$0] ? points[$0] : nil }
  }

  private static func segment(
    in points: [HealthKitRouteCoordinate],
    start: Int,
    end: Int
  ) -> Segment? {
    guard end - start > 1 else { return nil }
    let midpoint = Double(start + end) / 2
    var selected = start + 1
    var selectedDistance = -Double.infinity
    var selectedMidpointDistance = Double.infinity
    for index in (start + 1)..<end {
      let distance = perpendicularDistanceSquared(
        points[index], from: points[start], to: points[end])
      let midpointDistance = abs(Double(index) - midpoint)
      if distance > selectedDistance
        || (distance == selectedDistance && midpointDistance < selectedMidpointDistance)
      {
        selected = index
        selectedDistance = distance
        selectedMidpointDistance = midpointDistance
      }
    }
    return Segment(
      start: start,
      end: end,
      candidate: selected,
      distanceSquared: selectedDistance)
  }

  private static func perpendicularDistanceSquared(
    _ point: HealthKitRouteCoordinate,
    from start: HealthKitRouteCoordinate,
    to end: HealthKitRouteCoordinate
  ) -> Double {
    let longitudeScale = cos(
      ((start.northSouthDegrees + end.northSouthDegrees) / 2) * .pi / 180)
    let x = point.eastWestDegrees * longitudeScale
    let y = point.northSouthDegrees
    let startX = start.eastWestDegrees * longitudeScale
    let startY = start.northSouthDegrees
    let deltaX = end.eastWestDegrees * longitudeScale - startX
    let deltaY = end.northSouthDegrees - startY
    let lengthSquared = deltaX * deltaX + deltaY * deltaY
    guard lengthSquared > 0 else {
      let offsetX = x - startX
      let offsetY = y - startY
      return offsetX * offsetX + offsetY * offsetY
    }
    let projection = min(
      1,
      max(0, ((x - startX) * deltaX + (y - startY) * deltaY) / lengthSquared))
    let projectedX = startX + projection * deltaX
    let projectedY = startY + projection * deltaY
    let offsetX = x - projectedX
    let offsetY = y - projectedY
    return offsetX * offsetX + offsetY * offsetY
  }

  private static func hasHigherPriority(_ left: Segment, than right: Segment) -> Bool {
    if left.distanceSquared != right.distanceSquared {
      return left.distanceSquared > right.distanceSquared
    }
    let leftSpan = left.end - left.start
    let rightSpan = right.end - right.start
    if leftSpan != rightSpan { return leftSpan > rightSpan }
    return left.candidate < right.candidate
  }

  private static func heapAppend(_ value: Segment, to heap: inout [Segment]) {
    heap.append(value)
    var child = heap.count - 1
    while child > 0 {
      let parent = (child - 1) / 2
      guard hasHigherPriority(heap[child], than: heap[parent]) else { break }
      heap.swapAt(child, parent)
      child = parent
    }
  }

  private static func heapPop(from heap: inout [Segment]) -> Segment? {
    guard !heap.isEmpty else { return nil }
    if heap.count == 1 { return heap.removeLast() }
    let first = heap[0]
    heap[0] = heap.removeLast()
    var parent = 0
    while true {
      let left = parent * 2 + 1
      guard left < heap.count else { break }
      let right = left + 1
      let child =
        right < heap.count && hasHigherPriority(heap[right], than: heap[left]) ? right : left
      guard hasHigherPriority(heap[child], than: heap[parent]) else { break }
      heap.swapAt(parent, child)
      parent = child
    }
    return first
  }
}
