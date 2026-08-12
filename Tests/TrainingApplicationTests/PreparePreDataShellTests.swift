import XCTest

@testable import TrainingApplication

final class PreparePreDataShellTests: XCTestCase {
  func testPreparesPrivateStoresWithoutRequestingHealthAuthorization() async throws {
    let repository = RepositorySpy()
    let healthKit = HealthKitSpy()
    let logger = LoggerSpy()
    let useCase = PreparePreDataShell(
      repository: repository,
      healthKit: healthKit,
      logger: logger
    )

    let state = try await useCase()
    let prepareCallCount = await repository.prepareCallCount
    let authorizationRequestCount = await healthKit.authorizationRequestCount
    let events = await logger.events

    XCTAssertEqual(state, .readyForEngineeringDataOnly)
    XCTAssertEqual(prepareCallCount, 1)
    XCTAssertEqual(authorizationRequestCount, 0)
    XCTAssertEqual(events, [.preDataStoresReady])
  }

  func testLogsFixedFailureEventWithoutRequestingHealthAuthorization() async {
    let healthKit = HealthKitSpy()
    let logger = LoggerSpy()
    let useCase = PreparePreDataShell(
      repository: FailingRepository(),
      healthKit: healthKit,
      logger: logger
    )

    do {
      _ = try await useCase()
      XCTFail("Expected protected store preparation to fail")
    } catch {}

    let authorizationRequestCount = await healthKit.authorizationRequestCount
    let events = await logger.events
    XCTAssertEqual(authorizationRequestCount, 0)
    XCTAssertEqual(events, [.preDataStoresFailed])
  }
}

private enum TestError: Error {
  case storeUnavailable
}

private actor FailingRepository: TrainingRepository {
  func prepareStores() async throws {
    throw TestError.storeUnavailable
  }
}

private actor RepositorySpy: TrainingRepository {
  private(set) var prepareCallCount = 0

  func prepareStores() async throws {
    prepareCallCount += 1
  }
}

private actor HealthKitSpy: HealthKitClient {
  private(set) var authorizationRequestCount = 0

  func requestAuthorization() async throws -> HealthAuthorizationResult {
    authorizationRequestCount += 1
    return .notRequested
  }
}

private actor LoggerSpy: PrivacyLogger {
  private(set) var events: [PrivacyLogEvent] = []

  func record(_ event: PrivacyLogEvent) async {
    events.append(event)
  }
}
