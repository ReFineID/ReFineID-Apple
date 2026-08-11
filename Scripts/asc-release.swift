#!/usr/bin/env swift
// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Drive an App Store submission through the App Store Connect API, in
// the language this project is written in and with nothing else.
//
// The steps below the web UI are a handful of JSON-over-HTTP calls, and
// doing them by hand leaves no record of what was done. This composes
// them into named commands. CryptoKit signs the ES256 token from the
// .p8 (which is a P-256 key), URLSession makes the calls, and
// JSONSerialization reads and writes the bodies, so there is no Ruby,
// no Python, and nothing to install. The app is known by its bundle id
// and nothing secret; the key and issuer ids come from the environment
// or from ~/.appstoreconnect/env.
//
// Idempotent by design: ensure-version finds an existing version before
// creating one, and metadata updates a locale that is present rather
// than duplicating it.
//
// Usage:
//   asc-release.swift app-id
//   asc-release.swift state
//   asc-release.swift ensure-version <ios|macos> <versionString>
//   asc-release.swift attach-build <ios|macos> <versionString> <build>
//   asc-release.swift metadata <ios|macos> <versionString>
//   asc-release.swift app-info
//   asc-release.swift review-contact <ios|macos> <versionString>
//   asc-release.swift screenshots <ios|macos> <versionString>

import CryptoKit
import Foundation

let bundleID = "fi.refineid.ReFineID"
let apiBase = "https://api.appstoreconnect.apple.com"
let platforms = ["ios": "IOS", "macos": "MAC_OS"]

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("asc-release: \(message)\n".utf8))
    exit(1)
}

// The key and issuer ids, from the environment or the file beside the
// .p8, so an upload does not need them exported by hand.
func loadEnvironment() -> [String: String] {
    var values = ProcessInfo.processInfo.environment
    let path = ("~/.appstoreconnect/env" as NSString).expandingTildeInPath
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        return values
    }
    for var line in text.split(separator: "\n").map(String.init) {
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("export ") { line.removeFirst("export ".count) }
        guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
        let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        if values[key] == nil { values[key] = value }
    }
    return values
}

let environment = loadEnvironment()
func required(_ name: String) -> String {
    guard let value = environment[name], !value.isEmpty else { die("\(name) is not set") }
    return value
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// The API token, minted once with CryptoKit and reused. The .p8 is a
// PKCS#8 P-256 private key; a P-256 signature's raw representation is
// r||s, which is exactly the ES256 JWS form.
let token: String = {
    let keyID = required("ASC_KEY_ID")
    let issuer = required("ASC_ISSUER_ID")
    let keyPath = ("~/.appstoreconnect/private_keys/AuthKey_\(keyID).p8" as NSString)
        .expandingTildeInPath
    guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
        die("no key at \(keyPath); download the .p8 from App Store Connect")
    }
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        die("the .p8 at \(keyPath) is not a readable P-256 key")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let payload: [String: Any] = [
        "iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1",
    ]
    let headerData = try! JSONSerialization.data(withJSONObject: header)
    let payloadData = try! JSONSerialization.data(withJSONObject: payload)
    let signingInput = "\(headerData.base64URL).\(payloadData.base64URL)"
    let signature = try! key.signature(for: Data(signingInput.utf8))
    return "\(signingInput).\(signature.rawRepresentation.base64URL)"
}()

// One API call. Returns the parsed body, or exits with the API's own
// error on a non-2xx response. Brackets in a path (filter[bundleId])
// are percent-encoded, which URL rejects unencoded.
@discardableResult
func api(_ method: String, _ path: String, body: [String: Any]? = nil) -> [String: Any] {
    let encoded = path.replacingOccurrences(of: "[", with: "%5B")
        .replacingOccurrences(of: "]", with: "%5D")
    guard let url = URL(string: apiBase + encoded) else { die("bad path: \(path)") }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
    }
    let semaphore = DispatchSemaphore(value: 0)
    var data = Data()
    var status = 0
    URLSession.shared.dataTask(with: request) { responseData, response, _ in
        data = responseData ?? Data()
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        semaphore.signal()
    }.resume()
    semaphore.wait()
    guard (200..<300).contains(status) else {
        die("HTTP \(status) on \(method) \(path): \(String(data: data, encoding: .utf8) ?? "")")
    }
    if data.isEmpty { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

func apiPlatform(_ name: String) -> String {
    guard let value = platforms[name] else { die("platform is ios or macos, not '\(name)'") }
    return value
}

func dataArray(_ object: [String: Any]) -> [[String: Any]] {
    object["data"] as? [[String: Any]] ?? []
}

func appID() -> String {
    let data = dataArray(api("GET", "/v1/apps?filter[bundleId]=\(bundleID)"))
    guard let first = data.first, let id = first["id"] as? String else {
        die("app \(bundleID) not found on this account")
    }
    return id
}

// The id and version string of the platform's editable version, or nil.
func findVersion(_ platform: String) -> (id: String, version: String)? {
    let path = "/v1/apps/\(appID())/appStoreVersions?filter[platform]=\(platform)"
        + "&fields[appStoreVersions]=versionString"
    guard let first = dataArray(api("GET", path)).first,
        let id = first["id"] as? String,
        let attributes = first["attributes"] as? [String: Any],
        let version = attributes["versionString"] as? String
    else { return nil }
    return (id, version)
}

// The id of the version for a platform and string, created if absent.
// A platform's one editable version is renamed rather than duplicated.
func ensureVersion(_ platformName: String, _ version: String) -> String {
    let platform = apiPlatform(platformName)
    if let existing = findVersion(platform) {
        if existing.version == version { return existing.id }
        api("PATCH", "/v1/appStoreVersions/\(existing.id)", body: [
            "data": ["type": "appStoreVersions", "id": existing.id,
                     "attributes": ["versionString": version]],
        ])
        return existing.id
    }
    let created = api("POST", "/v1/appStoreVersions", body: [
        "data": ["type": "appStoreVersions",
                 "attributes": ["platform": platform, "versionString": version],
                 "relationships": ["app": ["data": ["type": "apps", "id": appID()]]]],
    ])
    guard let data = created["data"] as? [String: Any], let id = data["id"] as? String else {
        die("could not create the version")
    }
    return id
}

func attachBuild(_ platformName: String, _ version: String, _ number: String) {
    let versionID = ensureVersion(platformName, version)
    let path = "/v1/builds?filter[app]=\(appID())&filter[version]=\(number)&limit=1"
    guard let build = dataArray(api("GET", path)).first, let buildID = build["id"] as? String else {
        die("build \(number) not found; has it finished processing?")
    }
    api("PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build",
        body: ["data": ["type": "builds", "id": buildID]])
    print("attached build \(number) to \(platformName) \(version)")
}

// The repository root, from this script's own location (Scripts/..),
// so Metadata/ is found however the tool is invoked.
let repository = URL(fileURLWithPath: #filePath)
    .resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()

// The submission details, defined in one place - Metadata/appstore.json
// - and the locale map inside it, locale to its fields.
let metadata: [String: Any] = {
    let url = repository.appendingPathComponent("Metadata/appstore.json")
    guard let data = try? Data(contentsOf: url),
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { die("could not read Metadata/appstore.json") }
    return json
}()
let localizations = metadata["localizations"] as? [String: Any] ?? [:]

// The existing localizations of a resource, locale to its id, so a
// push updates what is present and creates what is not.
func existingLocalizations(_ path: String) -> [String: String] {
    var map: [String: String] = [:]
    for entry in dataArray(api("GET", path)) {
        if let attributes = entry["attributes"] as? [String: Any],
            let locale = attributes["locale"] as? String, let id = entry["id"] as? String {
            map[locale] = id
        }
    }
    return map
}

// Create or update each locale's version localization from the JSON.
// The description is the platform's own; the rest is shared.
func pushMetadata(_ platformName: String, _ version: String) {
    _ = apiPlatform(platformName)
    let versionID = ensureVersion(platformName, version)
    let existing = existingLocalizations(
        "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=50")
    for locale in localizations.keys.sorted() {
        let entry = localizations[locale] as? [String: Any] ?? [:]
        guard let description = (entry["description"] as? [String: Any])?[platformName] as? String
        else { continue }
        var attributes: [String: Any] = ["description": description]
        if let keywords = entry["keywords"] as? String { attributes["keywords"] = keywords }
        if let promo = entry["promotionalText"] as? String { attributes["promotionalText"] = promo }
        if let support = metadata["supportUrl"] as? String { attributes["supportUrl"] = support }
        if let marketing = metadata["marketingUrl"] as? String { attributes["marketingUrl"] = marketing }
        if let id = existing[locale] {
            api("PATCH", "/v1/appStoreVersionLocalizations/\(id)", body: [
                "data": ["type": "appStoreVersionLocalizations", "id": id,
                         "attributes": attributes]])
            print("  \(locale): updated")
        } else {
            attributes["locale"] = locale
            api("POST", "/v1/appStoreVersionLocalizations", body: [
                "data": ["type": "appStoreVersionLocalizations", "attributes": attributes,
                         "relationships": ["appStoreVersion": [
                             "data": ["type": "appStoreVersions", "id": versionID]]]]])
            print("  \(locale): created")
        }
    }
}

// The app-level info record that carries name, subtitle and category.
func appInfoID() -> String {
    let infos = dataArray(api("GET", "/v1/apps/\(appID())/appInfos"))
    for info in infos {
        let state = (info["attributes"] as? [String: Any])?["state"] as? String
        if state == "PREPARE_FOR_SUBMISSION", let id = info["id"] as? String { return id }
    }
    guard let id = infos.first?["id"] as? String else { die("no app info record") }
    return id
}

// Sets the primary category and each locale's subtitle from the JSON.
// Both live on the app info record, not on a version.
func pushAppInfo() {
    let infoID = appInfoID()
    let category = metadata["primaryCategory"] as? String ?? "UTILITIES"
    api("PATCH", "/v1/appInfos/\(infoID)", body: [
        "data": ["type": "appInfos", "id": infoID,
                 "relationships": ["primaryCategory": [
                     "data": ["type": "appCategories", "id": category]]]]])
    print("primary category: \(category)")
    let existing = existingLocalizations("/v1/appInfos/\(infoID)/appInfoLocalizations?limit=50")
    for locale in localizations.keys.sorted() {
        guard let subtitle = (localizations[locale] as? [String: Any])?["subtitle"] as? String
        else { continue }
        if let id = existing[locale] {
            api("PATCH", "/v1/appInfoLocalizations/\(id)", body: [
                "data": ["type": "appInfoLocalizations", "id": id,
                         "attributes": ["subtitle": subtitle]]])
            print("  \(locale): subtitle updated")
        } else {
            api("POST", "/v1/appInfoLocalizations", body: [
                "data": ["type": "appInfoLocalizations",
                         "attributes": ["locale": locale, "subtitle": subtitle],
                         "relationships": ["appInfo": [
                             "data": ["type": "appInfos", "id": infoID]]]]])
            print("  \(locale): subtitle created")
        }
    }
}

// Sets the App Review contact and notes on a platform's version, from
// the JSON. No demo account: the app has no login.
func reviewContact(_ platformName: String, _ version: String) {
    let versionID = ensureVersion(platformName, version)
    let review = metadata["review"] as? [String: Any] ?? [:]
    var attributes: [String: Any] = [
        "contactFirstName": review["firstName"] ?? "",
        "contactLastName": review["lastName"] ?? "",
        "contactPhone": review["phone"] ?? "",
        "contactEmail": review["email"] ?? "",
        "demoAccountRequired": false,
    ]
    if let notes = review["notes"] as? String { attributes["notes"] = notes }
    let existing = api(
        "GET", "/v1/appStoreVersions/\(versionID)/appStoreReviewDetail")["data"] as? [String: Any]
    if let id = existing?["id"] as? String {
        api("PATCH", "/v1/appStoreReviewDetails/\(id)", body: [
            "data": ["type": "appStoreReviewDetails", "id": id, "attributes": attributes]])
    } else {
        api("POST", "/v1/appStoreReviewDetails", body: [
            "data": ["type": "appStoreReviewDetails", "attributes": attributes,
                     "relationships": ["appStoreVersion": [
                         "data": ["type": "appStoreVersions", "id": versionID]]]]])
    }
    print("review contact set for \(platformName) \(version)")
}

// PUTs one chunk to a reserved upload URL. These are presigned, so they
// carry their own auth in the headers the reservation handed back and
// must not get the API bearer token.
func putChunk(_ operation: [String: Any], _ data: Data) {
    guard let urlString = operation["url"] as? String, let url = URL(string: urlString),
        let offset = operation["offset"] as? Int, let length = operation["length"] as? Int
    else { die("malformed upload operation") }
    var request = URLRequest(url: url)
    request.httpMethod = operation["method"] as? String ?? "PUT"
    for header in operation["requestHeaders"] as? [[String: Any]] ?? [] {
        if let name = header["name"] as? String, let value = header["value"] as? String {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
    request.httpBody = data.subdata(in: offset..<(offset + length))
    let semaphore = DispatchSemaphore(value: 0)
    var status = 0
    URLSession.shared.dataTask(with: request) { _, response, _ in
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        semaphore.signal()
    }.resume()
    semaphore.wait()
    guard (200..<300).contains(status) else { die("HTTP \(status) uploading a screenshot chunk") }
}

// The screenshot set for a version localization and display type, its
// existing shots cleared so a re-run replaces rather than appends.
func screenshotSet(localizationID: String, displayType: String) -> String {
    let sets = dataArray(api(
        "GET", "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets"))
    let setID: String
    if let match = sets.first(where: {
        ($0["attributes"] as? [String: Any])?["screenshotDisplayType"] as? String == displayType
    }), let id = match["id"] as? String {
        setID = id
        for shot in dataArray(api("GET", "/v1/appScreenshotSets/\(setID)/appScreenshots")) {
            if let id = shot["id"] as? String { api("DELETE", "/v1/appScreenshots/\(id)") }
        }
    } else {
        let created = api("POST", "/v1/appScreenshotSets", body: [
            "data": ["type": "appScreenshotSets",
                     "attributes": ["screenshotDisplayType": displayType],
                     "relationships": ["appStoreVersionLocalization": [
                         "data": ["type": "appStoreVersionLocalizations",
                                  "id": localizationID]]]]])
        guard let id = (created["data"] as? [String: Any])?["id"] as? String
        else { die("no screenshot set id") }
        setID = id
    }
    return setID
}

// Reserves, uploads and commits one screenshot into a set.
func uploadScreenshot(setID: String, file: URL) {
    guard let data = try? Data(contentsOf: file) else { die("cannot read \(file.path)") }
    let reservation = api("POST", "/v1/appScreenshots", body: [
        "data": ["type": "appScreenshots",
                 "attributes": ["fileName": file.lastPathComponent, "fileSize": data.count],
                 "relationships": ["appScreenshotSet": [
                     "data": ["type": "appScreenshotSets", "id": setID]]]]])
    guard let reserved = reservation["data"] as? [String: Any], let id = reserved["id"] as? String,
        let operations = (reserved["attributes"] as? [String: Any])?["uploadOperations"]
            as? [[String: Any]]
    else { die("no upload operations for \(file.lastPathComponent)") }
    for operation in operations { putChunk(operation, data) }
    let checksum = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    api("PATCH", "/v1/appScreenshots/\(id)", body: [
        "data": ["type": "appScreenshots", "id": id,
                 "attributes": ["uploaded": true, "sourceFileChecksum": checksum]]])
    print("    \(file.lastPathComponent)")
}

// Uploads every PNG under Metadata/screenshots/<locale>/<DISPLAY_TYPE>/
// for a platform's version, one screenshot set per display type.
func pushScreenshots(_ platformName: String, _ version: String) {
    let versionID = ensureVersion(platformName, version)
    let versionLocalizations = existingLocalizations(
        "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=50")
    let root = repository.appendingPathComponent("Metadata/screenshots")
    let fileManager = FileManager.default
    for (locale, localizationID) in versionLocalizations.sorted(by: { $0.key < $1.key }) {
        let localeDir = root.appendingPathComponent(locale)
        guard let displayDirs = try? fileManager.contentsOfDirectory(
            at: localeDir, includingPropertiesForKeys: nil) else { continue }
        print("  \(locale):")
        for displayDir in displayDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let displayType = displayDir.lastPathComponent
            let shots = ((try? fileManager.contentsOfDirectory(
                at: displayDir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            guard !shots.isEmpty else { continue }
            print("    [\(displayType)]")
            let setID = screenshotSet(localizationID: localizationID, displayType: displayType)
            for shot in shots { uploadScreenshot(setID: setID, file: shot) }
        }
    }
}

func state() {
    let path = "/v1/apps/\(appID())/appStoreVersions?fields[appStoreVersions]="
        + "versionString,platform,appStoreState,build&include=build"
        + "&fields[builds]=version&limit=50"
    let response = api("GET", path)
    var builds: [String: String] = [:]
    for entry in (response["included"] as? [[String: Any]] ?? []) where entry["type"] as? String == "builds" {
        if let id = entry["id"] as? String, let attributes = entry["attributes"] as? [String: Any],
            let version = attributes["version"] as? String {
            builds[id] = version
        }
    }
    for version in dataArray(response) {
        let attributes = version["attributes"] as? [String: Any] ?? [:]
        let relationship = (version["relationships"] as? [String: Any])?["build"] as? [String: Any]
        let buildID = (relationship?["data"] as? [String: Any])?["id"] as? String
        let build = buildID.flatMap { builds[$0] } ?? "-"
        print(String(format: "  %@ %@ %@ build=%@",
                     (attributes["platform"] as? String ?? "").padding(toLength: 7, withPad: " ", startingAt: 0),
                     (attributes["versionString"] as? String ?? "").padding(toLength: 10, withPad: " ", startingAt: 0),
                     (attributes["appStoreState"] as? String ?? "").padding(toLength: 24, withPad: " ", startingAt: 0),
                     build))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { die("a command is required; see the header") }
let rest = Array(arguments.dropFirst())

switch (command, rest.count) {
case ("app-id", 0): print(appID())
case ("state", 0): state()
case ("ensure-version", 2): print(ensureVersion(rest[0], rest[1]))
case ("attach-build", 3): attachBuild(rest[0], rest[1], rest[2])
case ("metadata", 2): pushMetadata(rest[0], rest[1])
case ("app-info", 0): pushAppInfo()
case ("review-contact", 2): reviewContact(rest[0], rest[1])
case ("screenshots", 2): pushScreenshots(rest[0], rest[1])
default: die("unknown command or wrong arguments: '\(command)'; see the header")
}
