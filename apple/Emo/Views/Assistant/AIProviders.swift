import EmoKit

/// Which AI provider the app uses. On-device Apple for now; ticket 12 adds a choice in Settings.
enum AIProviders {
    static func current() -> any LLMProvider {
        AppleOnDeviceProvider()
    }
}
