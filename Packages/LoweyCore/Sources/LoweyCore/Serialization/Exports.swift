// hmm-kit's document layer (JSONValue, HmmJSON, SafeFileWriter, SchemaCoder, DocumentPackage…) is part of
// LoweyCore's public vocabulary: everything that reads or writes Maquette files uses it.
@_exported import HmmDocuments

// The brush engine (brushes, strokes into stamps, `Vec2`, `SeededRandom`) is hmm-kit's since the Schizzo board
// draws with it too; Core's drawings, flipbooks and paint speak it as their own.
@_exported import HmmBrush

/// The shared JSON configuration (pretty, sorted keys, bit-exact dates).
public typealias LoweyJSON = HmmJSON
