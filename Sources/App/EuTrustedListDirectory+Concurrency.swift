#if os(macOS)

  import Foundation

  extension EuTrustedListDirectory {
    /// One completed value and its original input position.
    private struct IndexedValue<Value: Sendable>: Sendable {
      let index: Int
      let value: Value
    }

    /// Bounds retained response bodies and XML trees during a directory walk.
    internal static let maximumConcurrentNationalLists = 4

    /// Applies an asynchronous operation with a fixed in-flight cap and
    /// returns values in the same order as their inputs.
    internal static func mapBounded<Element: Sendable, Value: Sendable>(
      _ elements: [Element],
      maximumConcurrency: Int,
      operation: @escaping @Sendable (Element) async -> Value
    ) async -> [Value] {
      precondition(maximumConcurrency > 0)
      guard !elements.isEmpty else { return [] }
      return await withTaskGroup(
        of: IndexedValue<Value>.self,
        returning: [Value].self
      ) { group in
        let initialCount = min(maximumConcurrency, elements.count)
        for index in 0..<initialCount {
          group.addTask {
            IndexedValue(
              index: index,
              value: await operation(elements[index])
            )
          }
        }
        var nextIndex = initialCount
        var completed: [IndexedValue<Value>] = []
        while let value = await group.next() {
          completed.append(value)
          if nextIndex < elements.count {
            let index = nextIndex
            nextIndex += 1
            group.addTask {
              IndexedValue(
                index: index,
                value: await operation(elements[index])
              )
            }
          }
        }
        return completed.sorted { $0.index < $1.index }.map(\.value)
      }
    }

    /// Retries only failed inputs once, retaining the original result order.
    internal static func mapRetryingFailures<
      Element: Sendable,
      Value: Sendable
    >(
      _ elements: [Element],
      maximumConcurrency: Int,
      isFailure: @escaping @Sendable (Value) -> Bool,
      operation: @escaping @Sendable (Element) async -> Value
    ) async -> [Value] {
      var results = await Self.mapBounded(
        elements,
        maximumConcurrency: maximumConcurrency,
        operation: operation
      )
      let failedIndices = results.indices.filter { index in
        isFailure(results[index])
      }
      let retried = await Self.mapBounded(
        failedIndices,
        maximumConcurrency: maximumConcurrency
      ) { index in
        await operation(elements[index])
      }
      for (index, result) in zip(failedIndices, retried) {
        results[index] = result
      }
      return results
    }
  }

#endif
