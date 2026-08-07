// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "axhost-probe",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "axhost-probe", targets: ["axhost-probe"])
  ],
  dependencies: [
    .package(path: "../../Packages/MPDetection")
  ],
  targets: [
    .executableTarget(
      name: "axhost-probe",
      dependencies: [
        .product(name: "MPDetection", package: "MPDetection")
      ],
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    )
  ]
)
