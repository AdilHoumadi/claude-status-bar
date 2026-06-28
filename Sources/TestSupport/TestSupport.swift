import Foundation

/// A minimal, dependency-free test harness.
///
/// Command Line Tools (no full Xcode) ships neither `XCTest` nor `Testing`, so the
/// suite runs as a plain executable: `swift run ClaudeStatusBarTests`. Each suite is a
/// `(name, body)` pair; `runSuites` executes them, prints a report, and exits non-zero
/// on any failure — preserving the RED→GREEN discipline.

public final class TestContext {
    public private(set) var failures: [String] = []
    public private(set) var checks = 0

    public init() {}

    public func expect(
        _ condition: Bool,
        _ message: @autoclosure () -> String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        checks += 1
        if !condition {
            failures.append("\(file):\(line): \(message())")
        }
    }

    public func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
    }
}

public typealias TestSuite = (name: String, body: (TestContext) -> Void)

public func runSuites(_ suites: [TestSuite]) -> Never {
    var totalChecks = 0
    var totalFailures = 0
    for suite in suites {
        let t = TestContext()
        suite.body(t)
        totalChecks += t.checks
        if t.failures.isEmpty {
            print("✓ \(suite.name) — \(t.checks) checks passed")
        } else {
            totalFailures += t.failures.count
            print("✗ \(suite.name) — \(t.failures.count) of \(t.checks) FAILED:")
            for f in t.failures { print("    \(f)") }
        }
    }
    print("\n\(totalChecks) checks, \(totalFailures) failed")
    exit(totalFailures == 0 ? 0 : 1)
}
