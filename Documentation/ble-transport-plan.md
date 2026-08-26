# Bluetooth Low Energy (BLE) Transport Profile Implementation Plan

Status: Engineering Architecture & Implementation Plan  
Target Profile Identifier: `fi.refineid.ble.v1`  
Applicable Repositories: `ReFineID-Apple` (iOS/macOS), `ReFineID-Unix` (Linux), `ReFineID-Android`  
Date: 2026-08-26  

---

## 1. Executive Summary

This document specifies the architecture, wire framing, privacy model, and implementation roadmap for the **Bluetooth Low Energy (BLE) Transport Profile (`fi.refineid.ble.v1`)** within the Remote Authorization Proxy Protocol (RAPP) framework.

BLE provides an offline, peer-to-peer wireless transport between the **Requester** (Mac, Linux, Windows desktop/laptop) and the **Authorization Proxy** (iPhone, Android) that operates independently of local Wi-Fi infrastructure, router configurations, and public network client isolation.

---

## 2. Design Principles & Cryptographic Boundary

### 2.1 Complete Cryptographic Independence
RAPP treats Bluetooth Low Energy strictly as an untrusted physical underlay (RAPP Specification Section 5). 
- All confidentiality, integrity, mutual authentication, and replay resistance are provided by the **Noise Protocol handshakes** (`Noise_XXpsk3` for pairing, `Noise_KK` for sessions) using Curve25519, ChaCha20-Poly1305, and SHA-256.
- The security of RAPP does not depend on Bluetooth PINs, standard Bluetooth link-layer encryption, or OS Bluetooth pairing sheets.
- An on-path Bluetooth sniffer or malicious intermediary can observe only opaque Noise ciphertexts.

### 2.2 Strict Privacy & Anti-Tracking
- BLE advertisements **MUST NOT** broadcast persistent device identifiers, hardware MAC addresses, card numbers, person names, or certificates.
- The `rendezvous_token` (derived from the Noise handshake hash) is exchanged **only inside established, encrypted BLE channels** and never broadcast in public advertisement packets.
- Advertisements are active only while an explicit pairing offer or session connection is pending, and expire automatically.

### 2.3 Physical Proximity & Bounded Lifetime
- BLE operates within natural radio proximity (~5–10 meters).
- Connection attempts are bounded by monotonic timeouts (discovery timeout: 10s, synchronous operation timeout: 120s).

---

## 3. Wire Profile Specification (`fi.refineid.ble.v1`)

### 3.1 Framing
Every RAPP frame over BLE adheres to the universal RAPP framing rule:
- **2-byte big-endian length prefix** followed by the payload (Noise handshake message or Noise-encrypted deterministic CBOR envelope).
- Maximum frame size: 65,535 bytes (enforced before allocation).

### 3.2 Dual Transmission Channels

To ensure maximum performance and universal platform compatibility, `fi.refineid.ble.v1` supports two physical BLE channels:

1. **L2CAP Connection-Oriented Channels (CoC) — Preferred**:
   - Supported on iOS 11+, macOS 11+, and modern Linux BlueZ.
   - Provides direct, bidirectional binary streaming over a dedicated PSM (Protocol/Service Multiplexer) channel without GATT attribute overhead.
   - Automatic hardware/stack packet segmentation and reassembly up to 64 KiB SDUs.

2. **GATT Characteristic Streaming (Fallback Baseline)**:
   - Universal baseline across all BLE-capable platforms.
   - Negotiates maximum Attribute MTU (up to 512 bytes via ATT MTU Exchange).
   - Frames larger than (ATT_MTU - 3) are segmented across consecutive GATT Write / Notification packets with chunk sequence headers.

### 3.3 GATT Service Definition

```
Primary Service UUID: FA1D0001-C34A-4836-843B-7603B5749A32 (ReFineID RAPP Service)

Characteristics:
├── RX Characteristic (Write Without Response / Write with Response)
│   UUID: FA1D0002-C34A-4836-843B-7603B5749A32
│   Direction: Requester (Client) ──> Proxy (Server)
│
├── TX Characteristic (Notify / Indicate)
│   UUID: FA1D0003-C34A-4836-843B-7603B5749A32
│   Direction: Proxy (Server) ──> Requester (Client)
│
└── L2CAP PSM Characteristic (Read, Optional)
    UUID: FA1D0004-C34A-4836-843B-7603B5749A32
    Value: 16-bit unsigned integer PSM for direct L2CAP CoC connection
```

### 3.4 Candidate Parameters in QR Pairing Offer

When the Requester advertises BLE as a transport candidate in its pairing QR code, the `transport-candidate` map contains:

```cddl
ble-parameters = {
  "service_uuid": tstr,             ; 128-bit UUID string
  ? "psm": uint,                    ; L2CAP PSM if supported
  ? "advertised_name": tstr         ; Short ephemeral advertisement name (e.g. "RF-K7P9")
}
```

### 3.5 Rendezvous Preamble
Immediately upon establishing the BLE L2CAP channel or GATT stream, before any Noise handshake bytes, the Proxy sends the standard RAPP preamble:

```cddl
ble-rendezvous = [
  "RAPP-ble-v1",
  tstr,                             ; "pairing" or "session"
  bstr                              ; empty (for pairing) or rendezvous_token (for session)
]
```

---

## 4. Architecture in `refineid-apple`

### 4.1 Module Layout under `CardCore/Sources/CardCore/`

```
CardCore/Sources/CardCore/
├── BleRelaySession.swift          ; CoreBluetooth peripheral/central session driver
├── BleRelayFraming.swift          ; Length-prefix and GATT MTU chunking/reassembly
├── BleRelayEndpoint.swift         ; BLE service UUID and connection parameters
├── BleRelayTransportError.swift   ; Strongly typed BLE error classification
└── BleL2CAPChannelHandler.swift   ; CBL2CAPChannel streaming adapter
```

### 4.2 CoreBluetooth Role Mapping

- **Requester (Mac)**:
  - Operates as `CBPeripheralManager` during pairing offer (advertising the ephemeral Service UUID) and `CBCentralManager` when connecting to stored Proxy pairings.
- **Proxy (iPhone)**:
  - Scans for the advertised Service UUID using `CBCentralManager` during QR scan pairing.
  - Connects, discovers characteristics / opens L2CAP channel, sends preamble, and attaches to `RappSessionDriver`.

### 4.3 Multi-Transport Priority Policy

When both LAN Stream (`fi.refineid.stream.v1`) and BLE (`fi.refineid.ble.v1`) are available:
1. **Discovery**: Probe LAN (TCP/mDNS) and BLE simultaneously.
2. **Selection**: Prefer LAN TCP for lower latency and higher throughput if reachable within 1.5 seconds.
3. **Fallback**: If LAN discovery times out or fails (e.g. client isolation on public Wi-Fi), automatically proceed over BLE.

---

## 5. Security & Risk Analysis

| Threat | Mitigation |
| :--- | :--- |
| **Bluetooth Eavesdropping / Sniffing** | All application payload is Noise-encrypted (`Noise_XXpsk3` / `Noise_KK`) with ChaCha20-Poly1305 before transmission over BLE. |
| **Relay / Range Extension Attack** | Requester enforces strict monotonic response timeouts (30s for card operations). The Human Authorizer must physically approve on the phone screen with CAN/PIN1. |
| **Public Wi-Fi Client Isolation** | BLE operates point-to-point without Wi-Fi routers or access points, completely bypassing network isolation. |
| **Tracking / Beaconing** | Ephemeral UUIDs and nonces are used; no static identifiers or card serials are exposed over BLE advertisements. |
| **Replay Attacks** | Noise transport nonces are strictly sequential; replayed or reordered BLE packets trigger immediate authenticated decryption failure and session teardown. |

---

## 6. Implementation Milestones

- [ ] **Phase 1 (Core Framing & Codec)**:
  - Implement `BleRelayFraming` with unit tests for GATT chunking and L2CAP byte streams.
  - Add `fi.refineid.ble.v1` profile name and preamble generator to `RappEngine`.
- [ ] **Phase 2 (Apple CoreBluetooth Integration)**:
  - Implement `BleRelaySession` on iOS and macOS using `CBCentralManager` and `CBPeripheralManager`.
  - Wire L2CAP channel support (`openL2CAPChannel`).
- [ ] **Phase 3 (Cross-Platform Verification with Linux)**:
  - Test interoperability between `refineid-apple` (iPhone) and `refineid-unix` (Linux BlueZ central).
  - Verify complete `suomi.fi` authentication journey over BLE.
