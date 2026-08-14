// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InterviewCopilot",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "InterviewCopilot",
            path: "Sources/InterviewCopilot"
        )
    ]
)
