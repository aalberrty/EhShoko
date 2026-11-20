// Every figure measured for the choices, in the order a selection screen shows them. The
// research's table of measured figures is the authority; an opt-in test compares the two row
// for row. A new measurement replaces its `.notMeasured` row here. A new choice or a new kind
// of figure is added here and in the tests, which then ask for it for every choice of the
// same kind.
extension PageTranslationMeasurements {
    static let table: [Row] = [
        row(.detector(.k2xl), .balloonTextFound, .tally(87, of: 93), .pagesPhone),
        row(.detector(.k2xl), .notesFound, .tally(48, of: 58), .pagesPhone),
        row(.detector(.k2xl), .timePerPage, .seconds(0.343), .phone),
        row(.detector(.k2xl), .memory, .megabytes(59), .phone),
        row(.detector(.k2xl), .firstLoad, .seconds(9.4), .phone),

        row(.detector(.yolo26s), .balloonTextFound, .tally(84, of: 93), .pagesPhone),
        row(.detector(.yolo26s), .notesFound, .tally(41, of: 58), .pagesPhone),
        row(.detector(.yolo26s), .timePerPage, .seconds(0.027), .phone),
        row(.detector(.yolo26s), .memory, .megabytes(183), .phone),
        row(.detector(.yolo26s), .firstLoad, .seconds(1.65), .phone),

        row(.detector(.v4s), .balloonTextFound, .tally(83, of: 93), .pagesPhone),
        row(.detector(.v4s), .notesFound, .tally(38, of: 58), .pagesPhone),
        row(.detector(.v4s), .timePerPage, .seconds(0.041), .phone),
        row(.detector(.v4s), .memory, .megabytes(42), .phone),
        row(.detector(.v4s), .firstLoad, .seconds(4.3), .phone),

        row(.detector(.rtmdet2), .balloonTextFound, .tally(77, of: 93), .pagesMac),
        row(.detector(.rtmdet2), .notesFound, .tally(36, of: 58), .pagesMac),
        row(.detector(.rtmdet2), .timePerPage, .seconds(0.024), .phone),
        row(.detector(.rtmdet2), .memory, .megabytes(70), .phone),
        row(.detector(.rtmdet2), .firstLoad, .seconds(0.9), .phone),

        row(.reader(.cpt2), .linesReadExactly, .tally(143, of: 149), .pagesMac),
        row(.reader(.cpt2), .timePerBlock, .seconds(0.0179), .phone),
        row(.reader(.cpt2), .memory, .megabytes(35), .phone),
        row(.reader(.cpt2), .firstLoad, .seconds(6.7), .phone),

        row(.reader(.narSmall), .linesReadExactly, .tally(126, of: 149), .pagesMac),
        row(.reader(.narSmall), .timePerBlock, .seconds(0.0105), .phone),
        row(.reader(.narSmall), .memory, .notMeasured, .phone),
        row(.reader(.narSmall), .firstLoad, .seconds(5.8), .phone),

        row(.translator(.jmtFast1), .linesFullyRight, .tally(81, of: 101), .pagesMac),
        row(.translator(.jmtFast1), .linesWithSeriousError, .tally(12, of: 101), .pagesMac),
        row(.translator(.jmtFast1), .timePerPage, .seconds(0.30), .phone),
        row(.translator(.jmtFast1), .memory, .megabytes(99), .phone),
        row(.translator(.jmtFast1), .graphicsMemory, .megabytes(0), .phone),
        row(.translator(.jmtFast1), .firstLoad, .seconds(27.8), .phone),
        row(.translator(.jmtFast1), .heat, .coolFor(pages: 40), .phone),

        row(.translator(.galTransl4B), .linesFullyRight, .tally(74, of: 101), .pagesMac),
        row(.translator(.galTransl4B), .linesWithSeriousError, .tally(12, of: 101), .pagesMac),
        row(.translator(.galTransl4B), .timePerPage, .seconds(15.0), .phone),
        row(.translator(.galTransl4B), .memory, .megabytes(253), .phone),
        row(.translator(.galTransl4B), .graphicsMemory, .megabytes(2839), .phone),
        row(.translator(.galTransl4B), .firstLoad, .seconds(4.7), .phone),
        row(.translator(.galTransl4B), .heat, .hotFrom(page: 5), .phone),

        row(.translator(.sakura1_5B), .linesFullyRight, .tally(69, of: 101), .pagesMac),
        row(.translator(.sakura1_5B), .linesWithSeriousError, .tally(16, of: 101), .pagesMac),
        row(.translator(.sakura1_5B), .timePerPage, .notMeasured, .phone),
        row(.translator(.sakura1_5B), .memory, .notMeasured, .phone),
        row(.translator(.sakura1_5B), .graphicsMemory, .notMeasured, .phone),
        row(.translator(.sakura1_5B), .firstLoad, .notMeasured, .phone),
        row(.translator(.sakura1_5B), .heat, .notMeasured, .phone),

        row(.translator(.hyMT2), .linesFullyRight, .tally(57, of: 101), .pagesMac, .largerFile),
        row(.translator(.hyMT2), .linesWithSeriousError, .tally(28, of: 101), .pagesMac, .largerFile),
        row(.translator(.hyMT2), .timePerPage, .seconds(6.0), .phone),
        row(.translator(.hyMT2), .memory, .megabytes(163), .phone),
        row(.translator(.hyMT2), .graphicsMemory, .megabytes(1394), .phone),
        row(.translator(.hyMT2), .firstLoad, .seconds(1.3), .phone),
        row(.translator(.hyMT2), .heat, .hotFrom(page: 11), .phone),

        row(.translator(.qwen35_4B), .linesFullyRight, .tally(53, of: 101), .pagesMac),
        row(.translator(.qwen35_4B), .linesWithSeriousError, .tally(34, of: 101), .pagesMac),
        row(.translator(.qwen35_4B), .timePerPage, .seconds(14.3), .phone),
        row(.translator(.qwen35_4B), .memory, .megabytes(216), .phone),
        row(.translator(.qwen35_4B), .graphicsMemory, .megabytes(2942), .phone),
        row(.translator(.qwen35_4B), .firstLoad, .seconds(2.5), .phone),
        row(.translator(.qwen35_4B), .heat, .hotFrom(page: 4), .phone),

        row(.repaint(.off), .timePerPage, .notMeasured, .phone),

        row(.repaint(.lamaManga), .pictureMatches, .tally(10, of: 10), .phone),
        row(.repaint(.lamaManga), .timePerTile, .seconds(0.494), .phone),
        row(.repaint(.lamaManga), .memory, .megabytes(406), .phone),
        row(.repaint(.lamaManga), .firstLoad, .seconds(1.6), .phone),

        row(.repaint(.bigLama), .pictureMatches, .tally(10, of: 10), .phone),
        row(.repaint(.bigLama), .timePerTile, .seconds(0.624), .phone),
        row(.repaint(.bigLama), .memory, .megabytes(731), .phone),
        row(.repaint(.bigLama), .firstLoad, .seconds(1.6), .phone),

        row(.pair(.k2xl, .cpt2), .linesReadExactly, .tally(115, of: 149), .pagesMac),
        row(.pair(.k2xl, .narSmall), .linesReadExactly, .tally(108, of: 149), .pagesMac),
        row(.pair(.yolo26s, .cpt2), .linesReadExactly, .tally(109, of: 149), .pagesMac),
        row(.pair(.yolo26s, .narSmall), .linesReadExactly, .tally(104, of: 149), .pagesMac),
        row(.pair(.rtmdet2, .cpt2), .linesReadExactly, .tally(87, of: 149), .pagesMac),
        row(.pair(.rtmdet2, .narSmall), .linesReadExactly, .tally(79, of: 149), .pagesMac),
        row(.pair(.v4s, .cpt2), .linesReadExactly, .notMeasured, .pagesMac),
        row(.pair(.v4s, .narSmall), .linesReadExactly, .notMeasured, .pagesMac),
    ]

    private static func row(
        _ subject: Subject, _ kind: MeasuredFigure.Kind, _ value: MeasuredFigure.Value,
        _ basis: MeasuredFigure.Basis, _ note: MeasuredFigure.Note? = nil
    ) -> Row {
        Row(subject: subject, figure: MeasuredFigure(kind: kind, value: value, basis: basis, note: note))
    }
}
