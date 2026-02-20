import Foundation
import ArgumentParser

@main
struct AlitiesEngineCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alities-engine",
        abstract: "Alities trivia engine — daemon with HTTP API and studio web app",
        subcommands: [
            RunCommand.self,
            ListProvidersCommand.self,
            StatusCommand.self,
            HarvestCommand.self,
            CtlCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )
}
