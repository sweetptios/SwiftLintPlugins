import Foundation
import PackagePlugin

@main
struct SwiftLintCommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        Diagnostics.remark("arguments: \(arguments)")
        guard !arguments.contains("--cache-path") else {
            Diagnostics.error("Caching is managed by the plugin and so setting `--cache-path` is not allowed")
            return
        }
        var argExtractor = ArgumentExtractor(arguments)
        let targetNames = argExtractor.extractOption(named: "target")
        Diagnostics.remark("targetNames: \(targetNames)")
        let targets = targetNames.isEmpty
            ? context.package.targets
            : try context.package.targets(named: targetNames)
        guard !targets.isEmpty else {
            try run(with: context, arguments: arguments)
            return
        }
        for target in targets {
            Diagnostics.remark("target: \(target)")
            guard let target = target.sourceModule else {
                Diagnostics.warning("Target '\(target.name)' is not a source module; skipping it")
                continue
            }
            try run(in: target.directory.string, for: target.name, with: context, arguments: arguments)
        }
    }

    private func run(in directory: String = ".",
                     for targetName: String? = nil,
                     with context: PluginContext,
                     arguments: [String]) throws {
        Diagnostics.remark("directory: \(directory), taregtName: \(targetName)")
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: context.package.directory.string)
        Diagnostics.remark("currentDirectoryURL: \(process.currentDirectoryURL)")
        process.executableURL = URL(fileURLWithPath: try context.tool(named: "swiftlint").path.string)
        Diagnostics.remark("executableURL: \(process.executableURL)")

        var filteredArguments = arguments
        if let targetIndex = filteredArguments.firstIndex(of: "--target") {
            filteredArguments.removeSubrange(targetIndex...targetIndex + 1)
        }

        print("filteredArguments: \(filteredArguments)")
        process.arguments = filteredArguments

        if !arguments.contains("analyze") {
            // The analyze command does not support the `--cache-path` argument.
            process.arguments! += ["--cache-path", "\(context.pluginWorkDirectory.string)"]
        }
        process.arguments! += [directory]

        Diagnostics.remark("arguments: \(process.arguments)")
        try process.run()
        process.waitUntilExit()

        let module = targetName.map { "module '\($0)'" } ?? "package"
        switch process.terminationReason {
        case .exit:
            Diagnostics.remark("Finished running in \(module)")
        case .uncaughtSignal:
            Diagnostics.error("Got uncaught signal while running in \(module)")
        @unknown default:
            Diagnostics.error("Stopped running in \(module) due to unexpected termination reason")
        }

        if process.terminationStatus != EXIT_SUCCESS {
            Diagnostics.error("""
                Command found error violations or unsuccessfully stopped running with \
                exit code \(process.terminationStatus) in \(module)
                """
            )
        }
    }
}
