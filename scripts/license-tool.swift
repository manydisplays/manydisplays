#!/usr/bin/env swift
// Licence key tool for Many Displays (Ed25519, same format as Sources/ManyDisplaysCore/License.swift).
//
//   swift scripts/license-tool.swift generate-keys      prints a new key pair (store the private one in the shop's secrets)
//   swift scripts/license-tool.swift sign --private <base64> --email <email> [--until YYYY-MM-DD] [--issued YYYY-MM-DD]
//   swift scripts/license-tool.swift verify --public <base64> --key <licence text>
import CryptoKit
import Foundation

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func fromBase64URL(_ s: String) -> Data? {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 {
        t += "="
    }
    return Data(base64Encoded: t)
}

let day: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("usage: license-tool.swift generate-keys | sign | verify"); exit(2)
}

args.removeFirst()
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch command {
case "generate-keys":
    let key = Curve25519.Signing.PrivateKey()
    print("private (keep secret): \(key.rawRepresentation.base64EncodedString())")
    print("public  (in the app):  \(key.publicKey.rawRepresentation.base64EncodedString())")
case "sign":
    guard let priv = option("--private").flatMap({ Data(base64Encoded: $0) }), let email = option("--email") else {
        print("sign needs --private and --email"); exit(2)
    }
    let issued = option("--issued").flatMap(day.date) ?? Date()
    let until = option("--until").flatMap(day.date)
        ?? Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: issued)!
    let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: priv)
    let payload = Data("\(email)|\(day.string(from: issued))|\(day.string(from: until))".utf8)
    let signature = try signing.signature(for: payload)
    print("MD1.\(base64URL(payload)).\(base64URL(signature))")
case "verify":
    guard let pub = option("--public").flatMap({ Data(base64Encoded: $0) }), let text = option("--key") else {
        print("verify needs --public and --key"); exit(2)
    }
    let parts = text.split(separator: ".")
    guard parts.count == 3, let payload = fromBase64URL(String(parts[1])), let sig = fromBase64URL(String(parts[2])) else {
        print("malformed"); exit(1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: pub)
    print(key.isValidSignature(sig, for: payload) ? "valid: \(String(decoding: payload, as: UTF8.self))" : "INVALID signature")
default:
    print("unknown command \(command)"); exit(2)
}
