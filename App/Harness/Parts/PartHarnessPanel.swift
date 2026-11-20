#if DEBUG || HARNESS
import EhFeatures
import EhModels
import SwiftUI

/// The harness's options, as a sheet over the stage.
struct PartHarnessPanel: View {
    @Bindable var model: PartHarnessModel
    let close: (() -> Void)?
    @State private var heap: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker("Part", $model.options.part, PartHarnessPart.allCases) { $0.rawValue }
                    picker("Width", $model.options.width, [0, 320, 430, 1_000]) { $0 == 0 ? "window" : "\($0) pt" }
                    picker("Appearance", $model.options.scheme, PartHarnessScheme.allCases) { $0.rawValue }
                    Toggle(isOn: $model.options.usesLargestText) { Text(verbatim: "Largest text") }
                }
                Section {
                    Picker(selection: preset) {
                        ForEach(DesignStyle.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag(Optional($0)) }
                        Text(verbatim: "custom").tag(DesignStyle?.none)
                    } label: {
                        Text(verbatim: "Preset")
                    }
                    picker("Bar", $model.options.choices.bar, BarStyle.allCases) { $0.rawValue }
                    picker("First screen", $model.options.choices.start, DesignStyle.allCases) { $0.rawValue }
                    picker("Lists", $model.options.choices.list, DesignStyle.allCases) { $0.rawValue }
                    picker("Gallery", $model.options.choices.gallery, DesignStyle.allCases) { $0.rawValue }
                    picker("Reader", $model.options.choices.reader, DesignStyle.allCases) { $0.rawValue }
                    picker("Search", $model.options.choices.search, DesignStyle.allCases) { $0.rawValue }
                    picker("Library", $model.options.choices.library, DesignStyle.allCases) { $0.rawValue }
                    picker("Look", $model.options.choices.look, DesignStyle.allCases) { $0.rawValue }
                } header: {
                    Text(verbatim: "Designs")
                }
                Section {
                    picker("Kind", $model.options.kind, PartHarnessListKind.allCases) { $0.rawValue }
                    picker("State", $model.options.state, PartHarnessListState.allCases) { $0.rawValue }
                    picker("Header", $model.options.header, PartHarnessHeaderMode.allCases) { $0.rawValue }
                    Toggle(isOn: $model.options.showsTags) { Text(verbatim: "Tags in lists") }
                    picker("Wall density", $model.options.density, WallDensity.allCases) { $0.rawValue }
                } header: {
                    Text(verbatim: "Lists")
                }
                Section {
                    picker("Opens", $model.options.presentation, PartHarnessPresentation.allCases) { $0.rawValue }
                    picker("Search scope", $model.options.scope, SearchScope.allCases) { $0.rawValue }
                } header: {
                    Text(verbatim: "Gallery and search")
                }
                Section {
                    Button { heap = PartHarnessHeap.writeReport() } label: {
                        Text(verbatim: "List per-design objects in memory")
                    }
                    if let heap {
                        Text(verbatim: heap)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text(verbatim: "Memory")
                }
                if let close {
                    Section {
                        Button(role: .destructive, action: close) { Text(verbatim: "Close the harness") }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Part harness"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var preset: Binding<DesignStyle?> {
        Binding(
            get: { model.options.choices.preset },
            set: { if let preset = $0 { model.options.choices = DesignChoices(preset: preset) } }
        )
    }

    private func picker<Value: Hashable>(
        _ title: String, _ selection: Binding<Value>, _ values: [Value], name: @escaping (Value) -> String
    ) -> some View {
        Picker(selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(verbatim: name(value)).tag(value)
            }
        } label: {
            Text(verbatim: title)
        }
    }
}
#endif
