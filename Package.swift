// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MemoryBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MemoryBar", targets: ["MemoryBar"])
    ],
    targets: [
        .executableTarget(name: "MemoryBar")
    ]
)
