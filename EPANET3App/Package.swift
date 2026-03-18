// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EPANET3App",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "EPANET3", targets: ["EPANET3"]),
        .library(name: "EPANET3Bridge", targets: ["EPANET3Bridge"]),
        .library(name: "EPANET3Renderer", targets: ["EPANET3Renderer"]),
        .library(name: "EPANET3AppUI", targets: ["EPANET3AppUI"]),
        .executable(name: "EPANET3CLI", targets: ["EPANET3CLI"]),
        .executable(name: "EPANET3App", targets: ["EPANET3App"]),
    ],
    targets: [
        .target(
            name: "EPANET3",
            path: "EPANET3",
            exclude: ["CLI"],
            sources: nil,
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("Core"),
                .headerSearchPath("Elements"),
                .headerSearchPath("Input"),
                .headerSearchPath("Models"),
                .headerSearchPath("Output"),
                .headerSearchPath("Solvers"),
                .headerSearchPath("Utilities"),
            ]
        ),
        .target(
            name: "EPANET3Bridge",
            dependencies: ["EPANET3"],
            path: "EPANET3Bridge"
        ),
        .executableTarget(
            name: "EPANET3CLI",
            dependencies: ["EPANET3Bridge"],
            path: "EPANET3CLI"
        ),
        .target(
            name: "EPANET3Renderer",
            path: "EPANET3Renderer/Sources/EPANET3Renderer"
        ),
        .target(
            name: "EPANET3AppUI",
            dependencies: ["EPANET3Bridge", "EPANET3Renderer"],
            path: "EPANET3App",
            sources: ["ContentView.swift", "AppState.swift", "PropertyPanelView.swift", "InpOptionsParser.swift", "InpDisplayParser.swift"]
        ),
        .executableTarget(
            name: "EPANET3App",
            dependencies: ["EPANET3AppUI"],
            path: "EPANET3App",
            sources: ["EPANET3App.swift"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
