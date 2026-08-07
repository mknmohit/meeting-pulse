// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MPDetection",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MPDetection", targets: ["MPDetection"])
  ],
  dependencies: [
    .package(path: "../MPCore"),
    .package(path: "../MPSupport"),
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.99.0"),
  ],
  targets: [
    .target(
      name: "MPDetection",
      dependencies: [
        .product(name: "MPCore", package: "MPCore"),
        .product(name: "MPSupport", package: "MPSupport"),
      ],
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "MPDetectionTests",
      dependencies: [
        "MPDetection",
        .product(name: "Testing", package: "swift-testing"),
      ],
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .unsafeFlags(["-suppress-warnings"]),
      ]
    ),
  ]
)
