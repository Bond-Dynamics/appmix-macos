// Checks an update's EdDSA signature against a public key, the way an installed copy of AppMix will (BOND-224).
// The release signs with a CI secret; this proves that secret is the private half of the key the app ships with.
//
//   swift scripts/release/verify-update.swift <archive> <base64 signature> <base64 public key>
//
// Exits 0 when the signature verifies, 1 when it doesn't, 64 on bad arguments.
import CryptoKit
import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("verify-update: \(message)\n".utf8))
    exit(code)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else { fail("usage: verify-update.swift <archive> <signature> <public key>", code: 64) }
let (archivePath, signatureText, publicKeyText) = (arguments[1], arguments[2], arguments[3])

guard let signature = Data(base64Encoded: signatureText) else { fail("the signature is not base64", code: 64) }
guard let publicKeyData = Data(base64Encoded: publicKeyText) else { fail("the public key is not base64", code: 64) }
let publicKey: Curve25519.Signing.PublicKey
do {
    publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
} catch {
    fail("the public key is not an Ed25519 key: \(error)", code: 64)
}
let archive: Data
do {
    archive = try Data(contentsOf: URL(fileURLWithPath: archivePath), options: .mappedIfSafe)
} catch {
    fail("cannot read \(archivePath): \(error)", code: 64)
}

guard publicKey.isValidSignature(signature, for: archive) else {
    fail("the signature does not match the app's SUPublicEDKey; installed copies would reject this update", code: 1)
}
print("verify-update: signature matches SUPublicEDKey")
