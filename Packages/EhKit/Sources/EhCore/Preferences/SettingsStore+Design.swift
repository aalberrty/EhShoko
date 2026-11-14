import EhModels

// The design setting as a whole (`Design/designs/README.md` section 3). Each part's property
// is read at that part's switch point only; these accessors are for Settings and the wizard,
// except `look`, which every reader of the look uses.

extension SettingsStore {
    /// The look the app wears. The one place that decides it: if colours and type should
    /// follow the first screen instead, this returns `designStart` and `.look` leaves
    /// `DesignPart.choosable`.
    public var look: DesignStyle { designLook }

    /// All eight choices. Reading it observes all eight properties, so only Settings and the
    /// wizard read it. Setting it assigns only the parts that differ, and remembers a result
    /// that is not a preset in `designCustom`.
    public var designChoices: DesignChoices {
        get {
            DesignChoices(
                bar: designBar, start: designStart, list: designList, gallery: designGallery,
                reader: designReader, search: designSearch, library: designLibrary, look: designLook
            )
        }
        set {
            assign(newValue)
            if newValue.preset == nil, designCustom != newValue {
                designCustom = newValue
            }
        }
    }

    /// The preset the current choices match, or `nil` for "Custom". Derived, never stored.
    public var designPreset: DesignStyle? { designChoices.preset }

    /// Sets all eight parts to `preset`. `designCustom` is kept, so the mix can come back.
    public func applyDesignPreset(_ preset: DesignStyle) {
        assign(DesignChoices(preset: preset))
    }

    /// Sets one part; when the result is not a preset it becomes `designCustom`.
    public func setDesign(_ option: DesignOption, for part: DesignPart) {
        var choices = designChoices
        choices[part] = option
        designChoices = choices
    }

    /// Brings back the last mix, if one was made.
    public func restoreCustomDesign() {
        guard let designCustom else { return }
        assign(designCustom)
    }

    /// Assigns only what differs, so an unchanged part neither writes nor notifies its
    /// switch point.
    private func assign(_ choices: DesignChoices) {
        if designBar != choices.bar { designBar = choices.bar }
        if designStart != choices.start { designStart = choices.start }
        if designList != choices.list { designList = choices.list }
        if designGallery != choices.gallery { designGallery = choices.gallery }
        if designReader != choices.reader { designReader = choices.reader }
        if designSearch != choices.search { designSearch = choices.search }
        if designLibrary != choices.library { designLibrary = choices.library }
        if designLook != choices.look { designLook = choices.look }
    }
}
