// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MedievalDomain",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MedievalDomain", targets: ["MedievalDomain"]),
    ],
    targets: [
        .target(
            name: "MedievalDomain",
            path: "Medieval/Domain",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "MedievalDomainTests", dependencies: ["MedievalDomain"]),
    ]
)
