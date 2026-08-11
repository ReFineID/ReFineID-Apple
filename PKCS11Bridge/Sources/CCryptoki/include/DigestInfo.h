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
// DigestInfo.h -- named hash algorithm identifiers for CKM_RSA_PKCS.
//
// A CKM_RSA_PKCS caller signs a DigestInfo, SEQUENCE {
// AlgorithmIdentifier, OCTET STRING }, whose OID names the hash that
// produced the digest. These are the OID contents, without the tag and
// length octets, as registered by NIST (RFC 8017 appendix B.1):
// sha1 1.3.14.3.2.26, and sha256 2.16.840.1.101.3.4.2.1, sha384 .2,
// sha512 .3, sha224 .4 under the NIST hash algorithm arc.

#ifndef REFINEID_DIGEST_INFO_H
#define REFINEID_DIGEST_INFO_H

#include "Cryptoki.h"

static const CK_BYTE DigestOidSha1[] = {0x2B, 0x0E, 0x03, 0x02, 0x1A};
static const CK_BYTE DigestOidSha224[] = {
  0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04};
static const CK_BYTE DigestOidSha256[] = {
  0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01};
static const CK_BYTE DigestOidSha384[] = {
  0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02};
static const CK_BYTE DigestOidSha512[] = {
  0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03};

#endif
