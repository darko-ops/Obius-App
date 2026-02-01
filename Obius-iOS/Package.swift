// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Obius",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Obius", targets: ["Obius"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Obius",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Obius"
        )
    ]
)

