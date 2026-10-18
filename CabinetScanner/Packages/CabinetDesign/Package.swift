// swift-tools-version: 5.9
import PackageDescription

// A concept copy of PaperDesign (~/Documents/PaperDesign), re-themed in Cabinet Lab's brand.
let package = Package(
    name: "CabinetDesign",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CabinetDesign", targets: ["CabinetDesign"]),
    ],
    targets: [
        .target(
            name: "CabinetDesign",
            resources: [.copy("Resources/Fonts")]
        ),
    ]
)
