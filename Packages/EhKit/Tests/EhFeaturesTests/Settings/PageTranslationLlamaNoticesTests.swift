import EhFeatures
import Foundation
import Testing

/// The notices of what llama.cpp b12359's library contains, as found in the shipped framework.
@Suite struct PageTranslationLlamaNoticesTests {
    @Test func theListIsWhatTheLibraryContains() {
        #expect(PageTranslationNotice.llamaParts.map(\.name) == [
            "miniaudio v0.11.26",
            "rotate-bits.h",
            "SHA-1 in C",
            "sha256.c",
            "stb_image v2.30",
            "tinyBLAS (llamafile)",
            "Unicode Character Database 15.1.0 and 16.0.0",
            "xxHash v0.8.3",
            "YaRN",
        ])
    }

    @Test func eachNoticeKeepsItsCopyrightOrDedication() {
        let expected = [
            "Copyright 2026 David Reid",
            "Copyright (c) 2021 William Casarin <jb55@jb55.com>",
            "By Steve Reid <steve@edmweb.com>\n100% Public Domain",
            "2010-06-11 : Igor Pavlov : Public domain",
            "Copyright (c) 2017 Sean Barrett",
            "Copyright 2024 Mozilla Foundation",
            "Copyright © 1991-2026 Unicode, Inc.",
            "Copyright (c) 2012-2021 Yann Collet",
            "Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng",
        ]
        let notices = PageTranslationNotice.llamaParts
        #expect(notices.count == expected.count)
        for (notice, line) in zip(notices, expected) {
            #expect(notice.text.contains(line), "\(notice.name)")
        }
        // xxHash's licence asks for its notice in binary copies: its conditions are kept whole.
        let xxHash = notices.first { $0.name.hasPrefix("xxHash") }
        #expect(xxHash?.text.contains("Redistributions in binary form must reproduce") == true)
        // Unicode's licence asks for its notice to appear with all copies: it is kept whole.
        let unicode = notices.first { $0.name.hasPrefix("Unicode") }
        #expect(unicode?.text.hasPrefix("UNICODE LICENSE V3\n\nCOPYRIGHT AND PERMISSION NOTICE") == true)
        #expect(unicode?.text.hasSuffix("authorization of the copyright holder.") == true)
    }

    @Test func eachSourceNamesItsPinnedCommitOrVersion() throws {
        let unicode = try #require(PageTranslationNotice.llamaParts.first { $0.name.hasPrefix("Unicode") })
        // The Unicode data has no commit: its source names the version and file the tables
        // were generated from.
        #expect(unicode.source?.absoluteString == "https://www.unicode.org/Public/15.1.0/ucd/UnicodeData.txt")
        for notice in PageTranslationNotice.llamaParts where notice != unicode {
            let source = try #require(notice.source, "\(notice.name)")
            #expect(source.host() == "github.com")
            let commit = try #require(source.pathComponents.dropFirst(4).first, "\(notice.name)")
            #expect(commit.count == 40 && commit.allSatisfy(\.isHexDigit), "\(notice.name)")
        }
        #expect(Set(PageTranslationNotice.llamaParts.map(\.id)).count == PageTranslationNotice.llamaParts.count)
    }
}
