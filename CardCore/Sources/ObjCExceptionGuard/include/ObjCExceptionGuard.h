// Copyright 2026 Petri Koistinen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//        https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block`, catching the Objective-C exception it may raise.
///
/// Swift cannot catch these: a raise inside Swift code terminates the
/// process. System interfaces that can raise are called through this,
/// and the raise becomes a value the caller can look at.
///
/// Returns the exception raised, or nil when the block finished.
NSException *_Nullable CardCoreCatchException(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
