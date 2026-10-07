@testable import HmmTranscript
import XCTest

final class TranscriptTests: XCTestCase {
    private let words = [
        TranscriptWord(text: "Nobody", start: 0, end: 0.5),
        TranscriptWord(text: "could", start: 0.5, end: 0.9),
        TranscriptWord(text: "break", start: 1.0, end: 1.3),
        TranscriptWord(text: "Enigma.", start: 1.3, end: 2.0),
        TranscriptWord(text: "Until", start: 3.0, end: 3.4),
        TranscriptWord(text: "Turing", start: 3.4, end: 4.0)
    ]

    func testFindAndWordAtTime() {
        let transcript = Transcript(words: words, language: "en-US")
        XCTAssertEqual(transcript.find("enigma"), [3 ... 3])
        XCTAssertEqual(transcript.find("could BREAK"), [1 ... 2])
        XCTAssertEqual(transcript.word(at: 1.1)?.text, "break")
        XCTAssertNil(transcript.word(at: 2.5))
        XCTAssertEqual(transcript.word(at: 2.5, lookback: 1)?.text, "Enigma.")
        XCTAssertEqual(transcript.duration, 4)
        XCTAssertEqual(transcript.text, "Nobody could break Enigma. Until Turing")
    }

    func testEditingKeepsTimings() {
        let replaced = TranscriptEditing.replace(words, word: 3, with: "the Enigma")
        XCTAssertEqual(replaced.map(\.text), ["Nobody", "could", "break", "the", "Enigma", "Until", "Turing"])
        XCTAssertEqual(replaced[3].start, 1.3)
        XCTAssertEqual(replaced[4].end, 2.0)
        XCTAssertEqual(TranscriptEditing.replace(words, word: 0, with: "").count, 5)
        let merged = TranscriptEditing.merge(words, range: 0 ... 1)
        XCTAssertEqual(merged.first?.text, "Nobody could")
        XCTAssertEqual(merged.first?.end, 0.9)
        let ranged = TranscriptEditing.replace(words, range: 4 ... 5, with: "Alan")
        XCTAssertEqual(ranged.last, TranscriptWord(text: "Alan", start: 3, end: 4))
        let retimed = TranscriptEditing.retime(words, word: 1, start: 0.4, end: 1.1)
        XCTAssertEqual(retimed[0].end, 0.4)
        XCTAssertEqual(retimed[1].end, 1.1)
        XCTAssertEqual(retimed[2].start, 1.1)
    }

    func testWordsFromRecogniserRuns() {
        let split = TranscriptText.words(from: " hello  world ", start: 0, end: 1, confidence: 0.8)
        XCTAssertEqual(split.map(\.text), ["hello", "world"])
        XCTAssertEqual(split[1].end, 1)
        XCTAssertEqual(split[0].confidence, 0.8)
    }

    func testCuesBreakAtSentencesPausesAndLength() {
        let cues = Subtitles.cues(from: words, maxCharacters: 42)
        XCTAssertEqual(cues.map(\.text), ["Nobody could break Enigma.", "Until Turing"])
        let short = Subtitles.cues(from: words, maxCharacters: 12)
        XCTAssertTrue(short.allSatisfy { $0.text.count <= 14 })
    }

    func testSRTRoundTrip() throws {
        let cues = Subtitles.cues(from: words)
        let srt = Subtitles.srt(cues)
        XCTAssertTrue(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,000\nNobody could break Enigma.\n"))
        let parsed = try Subtitles.parseSRT(srt)
        XCTAssertEqual(parsed, cues)
        XCTAssertEqual(Subtitles.words(from: parsed).count, 6)
    }

    func testVTTRoundTripAndErrors() throws {
        let cues = Subtitles.cues(from: words)
        let vtt = Subtitles.vtt(cues)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:02.000"))
        XCTAssertEqual(try Subtitles.parseVTT(vtt), cues)
        XCTAssertThrowsError(try Subtitles.parseVTT("nope"))
        XCTAssertThrowsError(try Subtitles.parseSRT("1\n00:00:xx --> 00:00:01,000\nhi\n"))
        XCTAssertEqual(Subtitles.seconds("01:02:03,500"), 3723.5)
        XCTAssertEqual(Subtitles.seconds("02:03.25"), 123.25)
        XCTAssertNil(Subtitles.seconds("abc"))
        XCTAssertEqual(Subtitles.timestamp(3723.5, separator: ","), "01:02:03,500")
    }

    func testJSONRoundTrip() throws {
        let transcript = Transcript(words: [TranscriptWord(text: "ciao", start: 0, end: 1, confidence: 0.9, speaker: "A")], language: "it-IT")
        XCTAssertEqual(try Subtitles.parseJSON(Subtitles.json(transcript)), transcript)
        XCTAssertThrowsError(try Subtitles.parseJSON(Data("[]".utf8)))
    }

    func testLegacyWordJSONStillDecodes() throws {
        let legacy = Data(#"{"text":"hi","start":1,"end":2,"confidence":0.5}"#.utf8)
        let word = try JSONDecoder().decode(TranscriptWord.self, from: legacy)
        XCTAssertEqual(word, TranscriptWord(text: "hi", start: 1, end: 2, confidence: 0.5))
    }

    func testAlignmentToleratesMishearingAndGaps() {
        let script = ["Nobody", "could", "ever", "break", "Enigma"]
        let spoken = ["nobody", "could", "break", "enemas", "um"]
        let aligned = ScriptAlignment.align(script: script, spoken: spoken)
        let matches = aligned.filter(\.isMatch).map { [$0.scriptIndex ?? -1, $0.spokenIndex ?? -1] }
        XCTAssertEqual(matches, [[0, 0], [1, 1], [3, 2], [4, 3]])
        XCTAssertTrue(aligned.contains { $0.scriptIndex == 2 && $0.spokenIndex == nil })
        XCTAssertTrue(aligned.contains { $0.scriptIndex == nil && $0.spokenIndex == 4 })
        XCTAssertEqual(ScriptAlignment.wordCost("abc", "abc"), 0)
        XCTAssertEqual(ScriptAlignment.wordCost("", "abc"), 1)
    }

    func testScriptSpellingKeepsTimes() {
        let transcript = Transcript(words: [TranscriptWord(text: "enigmas", start: 1, end: 2)], language: "en-US")
        let fixed = ScriptAlignment.applyScriptSpelling(transcript, script: "Enigma")
        XCTAssertEqual(fixed.words, [TranscriptWord(text: "Enigma", start: 1, end: 2)])
    }

    func testEngineSelectionFallsBackToAnEngineThatSupportsTheLanguage() async {
        let apple = FakeEngine(kind: .speechAnalyzer, languages: ["en-US", "it-IT"])
        let whisper = FakeEngine(kind: .whisper, languages: ["en-US", "ar-EG"])
        let arabic = await TranscriptionEngineSelector.engine(for: "ar-EG", among: [apple, whisper])
        XCTAssertEqual(arabic?.kind, .whisper)
        let english = await TranscriptionEngineSelector.engine(for: "en-US", among: [apple, whisper])
        XCTAssertEqual(english?.kind, .speechAnalyzer)
        let preferred = await TranscriptionEngineSelector.engine(for: "en-US", among: [apple, whisper], preferring: .whisper)
        XCTAssertEqual(preferred?.kind, .whisper)
        let none = await TranscriptionEngineSelector.engine(for: "ja-JP", among: [apple, whisper])
        XCTAssertNil(none)
        let languages = await TranscriptionEngineSelector.languages(among: [apple, whisper])
        XCTAssertEqual(languages, ["en-US", "it-IT", "ar-EG"])
        XCTAssertFalse(TranscriptionError.noSpeech.description.isEmpty)
    }
}

private struct FakeEngine: TranscriptionEngine {
    let kind: TranscriptionEngineKind
    let languages: [String]

    func supports(language: String) async -> Bool { languages.contains(language) }
    func supportedLanguages() async -> [String] { languages }
    func transcribe(_: URL, language: String, status _: @escaping TranscriptionStatus) async throws -> Transcript {
        Transcript(words: [], language: language)
    }
}
