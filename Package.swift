// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ThemeSwitcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ThemeSwitcher")
    ]
)
