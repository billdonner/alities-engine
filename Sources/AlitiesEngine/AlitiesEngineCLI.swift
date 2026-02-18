import Foundation
import ArgumentParser

@main
struct AlitiesEngineCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alities-engine",
        abstract: "Alities trivia engine — generate, import, profile, and export trivia content",
        subcommands: [
            // Generator commands (from trivia-gen-daemon)
            RunCommand.self,
            ListProvidersCommand.self,
            StatusCommand.self,
            GenImportCommand.self,
            // Profile commands (from trivia-profile)
            ProfileImportCommand.self,
            ExportCommand.self,
            ReportCommand.self,
            StatsCommand.self,
            CategoriesCommand.self,
            // Control commands (HTTP client to running daemon)
            HarvestCommand.self,
            CtlCommand.self,
        ],
        defaultSubcommand: StatsCommand.self
    )
}
