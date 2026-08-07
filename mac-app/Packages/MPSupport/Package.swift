// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MPSupport",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MPSupport", targets: ["MPSupport"])
  ],
  dependencies: [
    .package(path: "../MPCore"),
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.99.0"),
  ],
  targets: [
    .target(
      name: "MPSupport",
      dependencies: [
        .product(name: "MPCore", package: "MPCore")
      ],
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "MPSupportTests",
      dependencies: [
        "MPSupport",
        .product(name: "Testing", package: "swift-testing"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .unsafeFlags(["-suppress-warnings"]),
      ]
    ),
  ]
)
