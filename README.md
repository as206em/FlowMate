# FlowMate

A macOS menu bar application that provides AI-powered text proofreading capabilities. The app integrates with both Ollama and OpenAI services to offer flexible proofreading options.

## Features

- Menu bar application for quick access
- Support for both Ollama and OpenAI services
- Customizable proofreading instructions
- Keyboard shortcut support
- Real-time connection status monitoring
- Configurable AI models and settings

## Architecture

The application follows modern Swift development practices with clear separation of concerns:

- **UI Layer**: SwiftUI views in `Sources/UI/Views/`
- **Business Logic**: Services in `Sources/Core/Services/`
- **Data Models**: Configuration models in `Sources/Models/Configuration/`
- **App Structure**: App delegate and state management in `Sources/App/`

## Setup

1. Ensure you have Swift 5.9+ installed
2. Clone the repository
3. Run `swift build` to build the project
4. Run `swift run` to start the application

## Development

The project uses Swift Package Manager for dependency management. Key dependencies include:
- Alamofire for HTTP networking
- SwiftUI for UI components

## Configuration

The app stores configuration in `~/Application Support/FlowMate/config.json` and supports:
- Provider settings (Ollama/OpenAI URLs and API keys)
- Proofreading preferences
- App settings (theme, auto-check updates, etc.)

## Testing

Run tests with `swift test` to ensure all functionality works correctly.

## Signing the app:
1. Create a Self-Signed Code Signing Certificate
- Open Keychain Access (Applications → Utilities → Keychain Access).
- From the menu: Keychain Access → Certificate Assistant → Create a Certificate.
- Fill in:
    - Name: FlowMate Dev Certificate (must match exactly what you'll use in the script).
    - Identity Type: Self Signed Root.
    - Certificate Type: Code Signing.
    - Check Let me override defaults.
    - On the next screens, accept defaults until you see Key Usage, make sure Code Signing is included.
    - Finish, and the certificate will appear in login → Certificates in Keychain.
2. Trust the Certificate
- Double click the new certificate in Keychain.
- Expand Trust and set Code Signing → Always Trust.
- Close, enter your password if prompted.


# Progress:
- refactor:
- rename app into flow mate
- update dropdown menu and remove sleected model
- think about the test connection work
- add Qwen provider
- improve proofreading excperince
- remove gequ from everywehre and check rights
