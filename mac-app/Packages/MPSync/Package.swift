// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MPSync",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MPSync", targets: ["MPSync"])
  ],
  dependencies: [
    .package(path: "../MPCore"),
    .package(path: "../MPSupport"),
    .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "0.99.0"),
    .package(
      url: "https://github.com/supabase/supabase-swift.git",
      from: "2.0.0"
    ),
  ],
  targets: [
    .target(
      name: "MPSync",
      dependencies: [
        .product(name: "MPCore", package: "MPCore"),
        .product(name: "MPSupport", package: "MPSupport"),
        .product(name: "Supabase", package: "supabase-swift"),
      ],
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "MPSyncTests",
      dependencies: [
        "MPSync",
        .product(name: "Testing", package: "swift-testing"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency"),
        .unsafeFlags(["-suppress-warnings"]),
      ]
    ),
  ]
)
