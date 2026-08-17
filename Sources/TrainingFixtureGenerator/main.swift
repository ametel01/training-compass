import Foundation
import TrainingApplication

let seed: UInt64 = if let seedIndex = CommandLine.arguments.firstIndex(of: "--seed"),
                      CommandLine.arguments.indices.contains(seedIndex + 1),
                      let parsedSeed = UInt64(CommandLine.arguments[seedIndex + 1])
{
    parsedSeed
} else {
    21571
}

let generator = SyntheticFixtureGenerator()
let profile: String = if let profileIndex = CommandLine.arguments.firstIndex(of: "--profile"),
                         CommandLine.arguments.indices.contains(profileIndex + 1)
{
    CommandLine.arguments[profileIndex + 1]
} else {
    "gate-zero"
}

let value: any Encodable
switch profile {
case "gate-zero":
    value = generator.manifest(seed: seed)
case "verification-envelope":
    value = generator.verificationEnvelope(seed: seed)
default:
    throw FixtureGenerationError.unknownProfile(profile)
}

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
var output = try encoder.encode(value)
output.append(0x0A)
FileHandle.standardOutput.write(output)

enum FixtureGenerationError: Error {
    case unknownProfile(String)
}
