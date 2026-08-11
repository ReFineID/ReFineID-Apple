//Copyright 2026 Petri Koistinen
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.
import CardCore
import Testing

@Suite
internal struct RetryCountTests {
  @Test
  internal func refusesImplausibleValues() {
    #expect(RetryCount(attemptsRemaining: RetryCount.maximumPlausible + 1) == nil)
    #expect(RetryCount(attemptsRemaining: .max) == nil)
  }

  @Test
  internal func acceptsWholePlausibleRange() {
    for value in 0...RetryCount.maximumPlausible {
      #expect(RetryCount(attemptsRemaining: value) != nil)
    }
  }

  @Test
  internal func pristineAllowanceIsPristine() throws {
    let count = try #require(
      RetryCount(attemptsRemaining: RetryCount.pristineAllowance)
    )
    #expect(count.isPristine)
    #expect(!count.isBlocked)
  }

  @Test
  internal func zeroIsBlockedNotPristine() throws {
    let count = try #require(RetryCount(attemptsRemaining: 0))
    #expect(count.isBlocked)
    #expect(!count.isPristine)
  }
}
