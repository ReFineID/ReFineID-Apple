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
//   apple-app-store-connect-release-manager.swift get <path>
//   apple-app-store-connect-release-manager.swift api <METHOD> <path> [json|-]
//   apple-app-store-connect-release-manager.swift app-id
//   apple-app-store-connect-release-manager.swift state
//   apple-app-store-connect-release-manager.swift builds <ios|macos>
//   apple-app-store-connect-release-manager.swift distribute <ios|macos> [group]
//   apple-app-store-connect-release-manager.swift add-tester <email> [group]
//   apple-app-store-connect-release-manager.swift invite <email>
//   apple-app-store-connect-release-manager.swift ensure-version <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift attach-build <ios|macos> <versionString> <build>
//   apple-app-store-connect-release-manager.swift metadata <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift app-info
//   apple-app-store-connect-release-manager.swift review-contact <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift screenshots <ios|macos> <versionString>
//   apple-app-store-connect-release-manager.swift age-rating
//   apple-app-store-connect-release-manager.swift export-compliance <ios|macos>
//   apple-app-store-connect-release-manager.swift pricing
//   apple-app-store-connect-release-manager.swift submissions
//   apple-app-store-connect-release-manager.swift submit <ios|macos> <versionString>

import CryptoKit
import Foundation

let bundleID = "fi.refineid.ReFineID"
let apiBase = "https://api.appstoreconnect.apple.com"
let platforms = ["ios": "IOS", "macos": "MAC_OS"]

// What this file is called, read from how it was invoked so a rename
// cannot leave a failure naming something that no longer exists.
let toolName = URL(fileURLWithPath: CommandLine.arguments.first ?? "release")
    .deletingPathExtension().lastPathComponent

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(toolName): \(message)\n".utf8))
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

// Prints a response the way a person reads it.
func printJSON(_ object: [String: Any]) {
    guard !object.isEmpty else { return }
    let pretty = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
    print(String(data: pretty, encoding: .utf8) ?? "")
}

// A request body from an argument, or from stdin when it is "-".
//
// The one-off calls a release needs - reading what an endpoint holds,
// patching an attribute the named commands do not cover - used to go
// through a shell wrapper around curl and a Ruby token minter. They are
// the same call this file already makes, so they are made here.
func readBody(_ argument: String) -> [String: Any] {
    let text = argument == "-"
        ? String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
        : argument
    guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
        let body = object as? [String: Any]
    else { die("the body is not a JSON object") }
    return body
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
    // Copyright lives on the version itself, not on a localization.
    if let copyright = metadata["copyright"] as? String {
        api("PATCH", "/v1/appStoreVersions/\(versionID)", body: [
            "data": ["type": "appStoreVersions", "id": versionID,
                     "attributes": ["copyright": copyright]]])
        print("  copyright: \(copyright)")
    }
    let existing = existingLocalizations(
        "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations?limit=50")
    for locale in localizations.keys.sorted() {
        let entry = localizations[locale] as? [String: Any] ?? [:]
        guard let description = (entry["description"] as? [String: Any])?[platformName] as? String
        else { continue }
        var attributes: [String: Any] = ["description": description]
        if let keywords = entry["keywords"] as? String { attributes["keywords"] = keywords }
        // Per platform, like the description: the Mac signs documents
        // and the iPhone does not yet, so one sentence cannot serve both.
        if let promo = (entry["promotionalText"] as? [String: Any])?[platformName] as? String {
            attributes["promotionalText"] = promo
        }
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
    // The privacy policy URL lives here too, and is per locale: the
    // policy is published in each language at its own address. App
    // Store Connect asks for it on the app record rather than on a
    // version, and a submission without it is refused.
    for locale in localizations.keys.sorted() {
        let entry = localizations[locale] as? [String: Any] ?? [:]
        guard let subtitle = entry["subtitle"] as? String else { continue }
        var attributes: [String: Any] = ["subtitle": subtitle]
        if let policy = entry["privacyPolicyUrl"] as? String {
            attributes["privacyPolicyUrl"] = policy
        }
        if let id = existing[locale] {
            api("PATCH", "/v1/appInfoLocalizations/\(id)", body: [
                "data": ["type": "appInfoLocalizations", "id": id,
                         "attributes": attributes]])
            print("  \(locale): subtitle and privacy policy updated")
        } else {
            attributes["locale"] = locale
            api("POST", "/v1/appInfoLocalizations", body: [
                "data": ["type": "appInfoLocalizations",
                         "attributes": attributes,
                         "relationships": ["appInfo": [
                             "data": ["type": "appInfos", "id": infoID]]]]])
            print("  \(locale): subtitle and privacy policy created")
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

// Sets the age rating to 4+: every content category at its lowest and
// no unrestricted web access. The declaration is app-level, carried by
// the app info record and shared across platforms.
func pushAgeRating() {
    let declaration = api("GET", "/v1/appInfos/\(appInfoID())/ageRatingDeclaration")
    guard let id = (declaration["data"] as? [String: Any])?["id"] as? String
    else { die("no age rating declaration on the app info record") }
    let none = "NONE"
    let attributes: [String: Any] = [
        "alcoholTobaccoOrDrugUseOrReferences": none,
        "contests": none,
        "gamblingSimulated": none,
        "medicalOrTreatmentInformation": none,
        "profanityOrCrudeHumor": none,
        "sexualContentGraphicAndNudity": none,
        "sexualContentOrNudity": none,
        "horrorOrFearThemes": none,
        "matureOrSuggestiveThemes": none,
        "violenceCartoonOrFantasy": none,
        "violenceRealistic": none,
        "violenceRealisticProlongedGraphicOrSadistic": none,
        "gunsOrOtherWeapons": none,
        "healthOrWellnessTopics": false,
        "advertising": false,
        "gambling": false,
        "unrestrictedWebAccess": false,
        "ageAssurance": false,
        "lootBox": false,
        "messagingAndChat": false,
        "parentalControls": false,
        "userGeneratedContent": false,
    ]
    api("PATCH", "/v1/ageRatingDeclarations/\(id)", body: [
        "data": ["type": "ageRatingDeclarations", "id": id, "attributes": attributes]])
    print("age rating 4+ set")
}

// Marks the platform's uploaded build as using no non-exempt encryption
// - the standard exempt answer for an app that only authenticates and
// signs with the card, and does not itself ship an encryption product.
func pushExportCompliance(_ platformName: String) {
    let platform = apiPlatform(platformName)
    guard let versionInfo = findVersion(platform) else { die("no version for \(platformName)") }
    let response = api("GET", "/v1/appStoreVersions/\(versionInfo.id)?include=build")
    guard let build = (response["included"] as? [[String: Any]])?
        .first(where: { $0["type"] as? String == "builds" }), let buildID = build["id"] as? String
    else { die("no build attached to \(platformName) \(versionInfo.version)") }
    let usesNonExempt = metadata["usesNonExemptEncryption"] as? Bool ?? false
    // A build that shipped with ITSAppUsesNonExemptEncryption in its
    // Info.plist already carries the answer and cannot be overwritten.
    let current = (build["attributes"] as? [String: Any])?["usesNonExemptEncryption"] as? Bool
    if current == usesNonExempt {
        print("export compliance already exempt on \(platformName) build \(versionInfo.version)")
        return
    }
    api("PATCH", "/v1/builds/\(buildID)", body: [
        "data": ["type": "builds", "id": buildID,
                 "attributes": ["usesNonExemptEncryption": usesNonExempt]]])
    print("export compliance (exempt) set on \(platformName) build \(versionInfo.version)")
}

// Puts the app on the free tier in every territory: a price schedule
// whose base territory carries the zero price point, which the store
// equalizes across all territories.
// Sets the price schedule from the JSON: free, in every territory,
// priced from one base.
//
// The base is the territory Apple leaves alone when it adjusts prices
// elsewhere for tax or exchange rates, and it decides the currency the
// baseline is written in. It is named in the JSON rather than assumed,
// because the sensible base is the seller's own country and the
// default is not.
func pushPricing() {
    guard (metadata["pricing"] as? String) == "free" else {
        die("only free pricing is supported; 'pricing' says "
            + "\(metadata["pricing"] ?? "nothing")")
    }
    let base = metadata["baseTerritory"] as? String ?? "USA"
    let app = appID()
    let points = dataArray(api(
        "GET", "/v1/apps/\(app)/appPricePoints?filter[territory]=\(base)&limit=200"))
    guard let freeID = points.first(where: {
        let price = ($0["attributes"] as? [String: Any])?["customerPrice"] as? String
        return price.flatMap(Double.init) == 0
    })?["id"] as? String else { die("no free price point for \(base)") }
    let temporary = "${free-price}"
    api("POST", "/v1/appPriceSchedules", body: [
        "data": ["type": "appPriceSchedules",
                 "relationships": [
                     "app": ["data": ["type": "apps", "id": app]],
                     "baseTerritory": ["data": ["type": "territories", "id": base]],
                     "manualPrices": ["data": [["type": "appPrices", "id": temporary]]]]],
        "included": [["type": "appPrices", "id": temporary,
                      "relationships": [
                          "appPricePoint": ["data": ["type": "appPricePoints", "id": freeID]],
                          "territory": ["data": ["type": "territories", "id": base]]]]]])
    print("pricing: free, all territories, based on \(base)")
}

// Every review submission, and whether it is one.
//
// The state is not the answer: READY_FOR_REVIEW means a container could
// be sent, not that anything was. A submission is real when it carries
// a version and has a submitted date, which is what this prints.
//
// An empty container is left behind whenever a version is refused for
// review, and the API can create one but not remove it: DELETE is not
// an allowed operation on this resource, and an empty one is "not in a
// cancellable state" either. App Store Connect's own Submissions page
// deletes them, so those are named here rather than silently listed.
func submissions() {
    let all = dataArray(api(
        "GET", "/v1/reviewSubmissions?filter[app]=\(appID())&limit=50"))
    guard !all.isEmpty else {
        print("no review submissions")
        return
    }
    for entry in all {
        guard let id = entry["id"] as? String else { continue }
        let attributes = entry["attributes"] as? [String: Any] ?? [:]
        let submitted = attributes["submittedDate"] as? String
        let items = dataArray(api("GET", "/v1/reviewSubmissions/\(id)/items")).count
        let note = (items == 0 && submitted == nil)
            ? "   empty; delete it in App Store Connect"
            : ""
        print(String(
            format: "  %@ %@ versions=%d submitted=%@%@",
            (attributes["platform"] as? String ?? "-")
                .padding(toLength: 7, withPad: " ", startingAt: 0),
            (attributes["state"] as? String ?? "-")
                .padding(toLength: 20, withPad: " ", startingAt: 0),
            items,
            submitted ?? "-",
            note))
    }
}

// Submits a platform's version for App Review. This is the one step that
// leaves the account: it creates the review submission, adds the version
// as its item, and marks it submitted.
func submit(_ platformName: String, _ version: String) {
    let platform = apiPlatform(platformName)
    let versionID = ensureVersion(platformName, version)
    let app = appID()
    let open = dataArray(api("GET", "/v1/reviewSubmissions?filter[app]=\(app)"
        + "&filter[platform]=\(platform)&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW"))
    let submissionID: String
    if let id = open.first?["id"] as? String {
        submissionID = id
    } else {
        let created = api("POST", "/v1/reviewSubmissions", body: [
            "data": ["type": "reviewSubmissions",
                     "attributes": ["platform": platform],
                     "relationships": ["app": ["data": ["type": "apps", "id": app]]]]])
        guard let id = (created["data"] as? [String: Any])?["id"] as? String
        else { die("could not create a review submission") }
        submissionID = id
    }
    api("POST", "/v1/reviewSubmissionItems", body: [
        "data": ["type": "reviewSubmissionItems",
                 "relationships": [
                     "reviewSubmission": ["data": ["type": "reviewSubmissions", "id": submissionID]],
                     "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]]]])
    api("PATCH", "/v1/reviewSubmissions/\(submissionID)", body: [
        "data": ["type": "reviewSubmissions", "id": submissionID,
                 "attributes": ["submitted": true]]])
    print("submitted \(platformName) \(version) for review")
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

// Whether a display type belongs to a platform.
//
// The locale folders hold every platform's shots side by side, and a
// version takes only its own: offering a Mac version an iPhone set is
// refused with "Display Type Not Allowed", which aborted the run and
// left the locales after it with nothing.
func platform(_ platformName: String, shows folderName: String) -> Bool {
    switch platformName {
    case "macos":
        folderName.hasPrefix("APP_DESKTOP")
    default:
        folderName.hasPrefix("APP_IPHONE") || folderName.hasPrefix("APP_IPAD")
    }
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
            guard platform(platformName, shows: displayType) else { continue }
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

// The platform's recent builds with their TestFlight readiness: a build
// is testable once it processes to VALID, and reaches external testers
// once its beta review is APPROVED. Internal testers need only VALID.
func builds(_ platformName: String) {
    let platform = apiPlatform(platformName)
    let path = "/v1/builds?filter[app]=\(appID())&filter[preReleaseVersion.platform]=\(platform)"
        + "&sort=-uploadedDate&limit=10&include=preReleaseVersion,betaAppReviewSubmission"
        + "&fields[builds]=version,processingState,expired,preReleaseVersion,betaAppReviewSubmission"
        + "&fields[preReleaseVersions]=version&fields[betaAppReviewSubmissions]=betaReviewState"
    let response = api("GET", path)
    var included: [String: [String: Any]] = [:]
    for entry in response["included"] as? [[String: Any]] ?? [] {
        if let type = entry["type"] as? String, let id = entry["id"] as? String {
            included["\(type)/\(id)"] = entry["attributes"] as? [String: Any]
        }
    }
    func related(_ build: [String: Any], _ name: String, _ type: String) -> [String: Any]? {
        let relationship = (build["relationships"] as? [String: Any])?[name] as? [String: Any]
        guard let id = (relationship?["data"] as? [String: Any])?["id"] as? String else { return nil }
        return included["\(type)/\(id)"]
    }
    for build in dataArray(response) {
        let attributes = build["attributes"] as? [String: Any] ?? [:]
        let marketing = related(build, "preReleaseVersion", "preReleaseVersions")?["version"]
            as? String ?? "-"
        let review = related(build, "betaAppReviewSubmission", "betaAppReviewSubmissions")?[
            "betaReviewState"] as? String ?? "none"
        let expired = (attributes["expired"] as? Bool ?? false) ? " expired" : ""
        print(String(format: "  %@ build %@ %@ beta=%@%@",
                     marketing.padding(toLength: 10, withPad: " ", startingAt: 0),
                     (attributes["version"] as? String ?? "").padding(toLength: 5, withPad: " ", startingAt: 0),
                     (attributes["processingState"] as? String ?? "").padding(toLength: 10, withPad: " ", startingAt: 0),
                     review, expired))
    }
}

// Distributes a platform's newest build to a beta group and submits it
// for beta app review. An external group only shows a build to its
// testers once that review is approved; internal groups need no review.
func distribute(_ platformName: String, _ groupName: String) {
    let platform = apiPlatform(platformName)
    let buildsPath = "/v1/builds?filter[app]=\(appID())"
        + "&filter[preReleaseVersion.platform]=\(platform)&sort=-uploadedDate&limit=1"
    guard let build = dataArray(api("GET", buildsPath)).first, let buildID = build["id"] as? String
    else { die("no \(platformName) build to distribute") }
    let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
    guard let groupID = groups.first(where: {
        ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    })?["id"] as? String else { die("no beta group named '\(groupName)'") }
    api("POST", "/v1/betaGroups/\(groupID)/relationships/builds", body: [
        "data": [["type": "builds", "id": buildID]]])
    print("added \(platformName) build to group '\(groupName)'")
    let review = api("GET", "/v1/builds/\(buildID)/betaAppReviewSubmission")["data"] as? [String: Any]
    if review == nil {
        api("POST", "/v1/betaAppReviewSubmissions", body: [
            "data": ["type": "betaAppReviewSubmissions",
                     "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]])
        print("submitted \(platformName) build for beta review")
    } else {
        print("beta review already exists for the \(platformName) build")
    }
}

// Creates a beta tester in a beta group. Joining an external group is
// what makes App Store Connect send the TestFlight invitation email, so
// this is the whole "invite a new tester" flow; `invite` merely resends.
func addTester(_ email: String, _ groupName: String) {
    let groups = dataArray(api("GET", "/v1/apps/\(appID())/betaGroups?limit=50"))
    guard let groupID = groups.first(where: {
        ($0["attributes"] as? [String: Any])?["name"] as? String == groupName
    })?["id"] as? String else { die("no beta group named '\(groupName)'") }
    api("POST", "/v1/betaTesters", body: [
        "data": ["type": "betaTesters",
                 "attributes": ["email": email],
                 "relationships": [
                     "betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]]]])
    print("added \(email) to group '\(groupName)'")
}

// Sends a TestFlight invitation email to an existing beta tester. The
// tester must already be on the app (in a group or assigned a build);
// this is the "resend invite" the App Store Connect UI offers.
func invite(_ email: String) {
    let testers = dataArray(api("GET", "/v1/betaTesters?filter[email]=\(email)"))
    guard let testerID = testers.first?["id"] as? String else {
        die("no beta tester with email \(email); add them to a group first")
    }
    api("POST", "/v1/betaTesterInvitations", body: [
        "data": ["type": "betaTesterInvitations",
                 "relationships": [
                     "app": ["data": ["type": "apps", "id": appID()]],
                     "betaTester": ["data": ["type": "betaTesters", "id": testerID]]]]])
    print("TestFlight invite sent to \(email)")
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
case ("get", 1):
    printJSON(api("GET", rest[0]))
case ("api", 2):
    printJSON(api(rest[0].uppercased(), rest[1]))
case ("api", 3):
    printJSON(api(rest[0].uppercased(), rest[1], body: readBody(rest[2])))
case ("app-id", 0): print(appID())
case ("state", 0): state()
case ("builds", 1): builds(rest[0])
case ("distribute", 1): distribute(rest[0], "Beta")
case ("distribute", 2): distribute(rest[0], rest[1])
case ("add-tester", 1): addTester(rest[0], "Beta")
case ("add-tester", 2): addTester(rest[0], rest[1])
case ("invite", 1): invite(rest[0])
case ("ensure-version", 2): print(ensureVersion(rest[0], rest[1]))
case ("attach-build", 3): attachBuild(rest[0], rest[1], rest[2])
case ("metadata", 2): pushMetadata(rest[0], rest[1])
case ("app-info", 0): pushAppInfo()
case ("review-contact", 2): reviewContact(rest[0], rest[1])
case ("screenshots", 2): pushScreenshots(rest[0], rest[1])
case ("age-rating", 0): pushAgeRating()
case ("export-compliance", 1): pushExportCompliance(rest[0])
case ("pricing", 0): pushPricing()
case ("submissions", 0): submissions()
case ("submit", 2): submit(rest[0], rest[1])
default: die("unknown command or wrong arguments: '\(command)'; see the header")
}
