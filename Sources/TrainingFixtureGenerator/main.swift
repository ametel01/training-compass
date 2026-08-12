import Foundation
import TrainingApplication

let seed: UInt64
if let seedIndex = CommandLine.arguments.firstIndex(of: "--seed"),
  CommandLine.arguments.indices.contains(seedIndex + 1),
  let parsedSeed = UInt64(CommandLine.arguments[seedIndex + 1])
{
  seed = parsedSeed
} else {
  seed = 21_571
}

let manifest = SyntheticFixtureGenerator().manifest(seed: seed)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
var output = try encoder.encode(manifest)
output.append(0x0A)
FileHandle.standardOutput.write(output)
