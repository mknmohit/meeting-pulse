// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MPCore",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MPCore", targets: ["MPCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.99.0")
  ],
  targets: [
    .target(
      name: "MPCore",
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "MPCoreTests",
      dependencies: [
        "MPCore",
        .product(name: "Testing", package: "swift-testing"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .unsafeFlags(["-suppress-warnings"]),
      ]
    ),
  ]
)
