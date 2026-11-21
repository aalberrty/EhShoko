#if DEBUG || HARNESS
import EhCore
import EhPageTranslation

/// How the harness's pipeline gets a language model as its translator.
///
/// This is the app's own way (`PageTranslationService.languageModelLoader`), so a run measures
/// what the reader would get. Until the llama.cpp translators are wired into the service it
/// is `nil`, and a run with `-TranslationHarnessTranslator galTransl4B` (or another language
/// model) fails to load and says so in its result.
///
/// Two of the language-model runs' wishes need those translators' types and are added here
/// with them: `-TranslationHarnessContext` (load the engine with that context instead of the
/// profile's) and, for each page, what `LanguageModelTranslator.translateRecording` gives
/// (tokens in and out, both durations, how each answer ended, how many requests).
nonisolated enum TranslationHarnessLanguageModel {
    static func loader(_ options: TranslationHarnessOptions) -> PageTranslatorLoader.LanguageModelLoader? {
        PageTranslationService.languageModelLoader
    }

    /// Whether `-TranslationHarnessContext` reaches the engine in this build.
    static let appliesContextLength = false
}
#endif
