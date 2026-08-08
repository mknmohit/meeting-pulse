// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MPUI",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "MPUI", targets: ["MPUI"]),
    .executable(name: "MPUIVisualReview", targets: ["MPUIVisualReview"])
  ],
  dependencies: [
    .package(path: "../MPCore"),
    .package(path: "../MPSupport")
  ],
  targets: [
    .target(
      name: "MPUI",
      dependencies: [
        .product(name: "MPCore", package: "MPCore"),
        .product(name: "MPSupport", package: "MPSupport")
      ],
      resources: [
        .process("Resources")
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .executableTarget(
      name: "MPUIVisualReview",
      dependencies: ["MPUI"],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "MPUITests",
      dependencies: [
        "MPUI",
        .product(name: "MPCore", package: "MPCore")
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    )
  ]
)
