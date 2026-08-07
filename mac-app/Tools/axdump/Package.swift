// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "axdump",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "axdump", targets: ["axdump"])
  ],
  targets: [
    .executableTarget(
      name: "axdump",
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    )
  ]
)
