#if canImport(ReFineIDRapp)
import Foundation

extension RappOperationDriver.KeyProfile {
    public init(_ profile: CardKeyProfile) {
        self = switch profile {
        case .ecdsaP256: .ecdsaP256
        case .ecdsaP384: .ecdsaP384
        case .rsa2048: .rsa2048
        case .rsa3072: .rsa3072
        }
    }

    public var cardKeyProfile: CardKeyProfile {
        switch self {
        case .ecdsaP256: .ecdsaP256
        case .ecdsaP384: .ecdsaP384
        case .rsa2048: .rsa2048
        case .rsa3072: .rsa3072
        }
    }
}

extension RappOperationDriver.SignatureAlgorithm {
    public init?(_ algorithm: SigningAlgorithm) {
        switch (algorithm.scheme, algorithm.hash) {
        case (.ecdsa, .sha224): self = .ecdsaSHA224
        case (.ecdsa, .sha256): self = .ecdsaSHA256
        case (.ecdsa, .sha384): self = .ecdsaSHA384
        case (.ecdsa, .sha512): self = .ecdsaSHA512
        case (.rsaPkcs1, .sha256): self = .rsaPkcs1SHA256
        case (.rsaPkcs1, .sha384): self = .rsaPkcs1SHA384
        case (.rsaPkcs1, .sha512): self = .rsaPkcs1SHA512
        case (.rsaPss, .sha256): self = .rsaPssSHA256
        default: return nil
        }
    }

    public var signingAlgorithm: SigningAlgorithm {
        switch self {
        case .ecdsaSHA224: SigningAlgorithm(hash: .sha224, scheme: .ecdsa)
        case .ecdsaSHA256: SigningAlgorithm(hash: .sha256, scheme: .ecdsa)
        case .ecdsaSHA384: SigningAlgorithm(hash: .sha384, scheme: .ecdsa)
        case .ecdsaSHA512: SigningAlgorithm(hash: .sha512, scheme: .ecdsa)
        case .rsaPkcs1SHA256: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1)
        case .rsaPkcs1SHA384: SigningAlgorithm(hash: .sha384, scheme: .rsaPkcs1)
        case .rsaPkcs1SHA512: SigningAlgorithm(hash: .sha512, scheme: .rsaPkcs1)
        case .rsaPssSHA256: SigningAlgorithm(hash: .sha256, scheme: .rsaPss)
        }
    }
}
#endif
