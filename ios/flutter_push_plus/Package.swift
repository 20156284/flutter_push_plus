// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_push_plus",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-push-plus", targets: ["flutter_push_plus"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_push_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
