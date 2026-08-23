// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Golden values captured from the reference engine.
///
/// They cover the five registered operations, pinning the action names, the
/// split between consent context and profile payload, and the request body.
internal enum ReferenceOperation {
    internal static let browserHash =
        "2b0727f383f2e5cc5383515bcf85c6249c0222ed5a8d7bc32222a2b53c283e8d"
    internal static let browserBody =
        "a766616374696f6e7462726f777365725f61757468656e74696361746567636f6e74657874a1666f7269"
        + "67696e7468747470733a2f2f6578616d706c652e74657374677061796c6f6164a3666469676573745820"
        + "666666666666666666666666666666666666666666666666666666666666666669616c676f726974686d"
        + "6c65636473615f7368613235366b6b65795f70726f66696c656a65636473615f703235366770726f6669"
        + "6c65781866692e6569642e61757468656e7469636174696f6e2e76316c6f7065726174696f6e5f696450"
        + "444444444444444444444444444444446c726571756573745f6861736858202b0727f383f2e5cc538351"
        + "5bcf85c6249c0222ed5a8d7bc32222a2b53c283e8d70657870697265735f61667465725f6d731a0001d4"
        + "c0"
    internal static let signHash =
        "92807d0f8baec35748a87180743f2b87c6f224769b125ec2a16eef15b8584b97"
    internal static let identityHash =
        "79334915c75e5bca481ccd0c7a135fd2dcfae922c67039d3527ee105a4567e78"
    internal static let certificateHash =
        "39816e375c41d6063ecc3d1fa654ec0d0a26f37c2f877a176a0caee16427e173"
    internal static let inspectHash =
        "28e8d48ed5649cc5e107bdd4c9359d9b9c4e882ae55cdb614f5b0e66deee6f92"
}
