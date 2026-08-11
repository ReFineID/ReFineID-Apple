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

/// The directory a certificate file lives under, which the reader must
/// make current before selecting the file (FINEID S4-1 §3, S4-2 v4.0
/// §4.6).
public enum CertificateDirectory: Equatable, Sendable {
  /// DF.ESIGN (5016) under the master file, where the organization
  /// card keeps its signature certificate (FINEID S4-2 v4.0
  /// §4.6.21-4.6.22).
  case esignApplication

  /// Directly under the master file.
  case masterFile

  /// Directly under the PKCS#15 application DF (already current after
  /// selecting the eID application).
  case pkcs15Application
}
