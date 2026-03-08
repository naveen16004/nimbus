# Nimbus

Nimbus is a Flutter application scaffold currently focused on Android.
The repository currently contains the starter app entrypoint plus a pre-created
feature-oriented `lib/` folder structure for future development.

## Tech Stack

- Flutter (Dart SDK constraint: `^3.11.0`)
- Android (Kotlin host)

## Getting Started

### Prerequisites

- Flutter SDK installed and available in `PATH`
- Android Studio / Android SDK (for Android builds)

### Install dependencies

```bash
flutter pub get
```

### Run the app

```bash
# Android (device or emulator)
flutter run -d android
```

### Build artifacts

```bash
# Android APK
flutter build apk

# Android App Bundle
flutter build appbundle
```

## Project Structure

```text
nimbus-git/
|-- .github/
|-- android/
|-- assets/
|-- lib/
|   |-- core/
|   |   |-- config/
|   |   |-- constants/
|   |   |-- crypto/
|   |   |-- keystore/
|   |   |-- media/
|   |   `-- sync/
|   |-- models/
|   |-- routes/
|   |-- screens/
|   |   |-- albums/
|   |   |-- album_view/
|   |   |-- auth/
|   |   |   |-- login/
|   |   |   `-- register/
|   |   |-- home/
|   |   |-- photo_viewer/
|   |   `-- splash/
|   |-- services/
|   |-- theme/
|   |-- utils/
|   |-- widgets/
|   `-- main.dart
|-- .gitignore
|-- .metadata
|-- analysis_options.yaml
|-- LICENSE
|-- pubspec.yaml
`-- README.md
```

## Directory Usage

### Root

- `android/`: Native Android host project, Gradle config, manifests, and launcher resources.
- `.github/`: Repository support files (`screenshots/` currently stores README/demo images).
- `assets/`: Reserved for static assets (images, fonts, etc.) to be declared in `pubspec.yaml`.
- `lib/`: Main Flutter/Dart application source.
- `.gitignore`: Git ignore rules for Flutter/Dart and platform outputs.
- `.metadata`: Flutter tool metadata used by the project.
- `analysis_options.yaml`: Dart/Flutter lint and static analysis rules.
- `LICENSE`: Project license text.
- `pubspec.yaml`: Package metadata, SDK constraints, dependencies, and Flutter config.

### `lib/`

- `main.dart`: Current app entrypoint and startup widget tree.
- `core/`: Cross-cutting foundational modules.
- `core/config/`: App/environment configuration models and loaders.
- `core/constants/`: Centralized constants and shared keys.
- `core/crypto/`: Encryption/decryption and cryptographic helpers.
- `core/keystore/`: Secure key storage abstractions.
- `core/media/`: Media handling primitives (file/image/video helpers).
- `core/sync/`: Sync orchestration and background reconciliation logic.
- `models/`: Domain/data models and serialization objects.
- `routes/`: Route names, navigation maps, and router setup.
- `screens/`: Feature/page-level UI modules.
- `screens/albums/`: Album list and album management views.
- `screens/album_view/`: Single album detail and media grid.
- `screens/auth/`: Authentication-related screens.
- `screens/auth/login/`: Login flow UI/state.
- `screens/auth/register/`: Registration flow UI/state.
- `screens/home/`: Main post-auth landing/dashboard screen.
- `screens/photo_viewer/`: Fullscreen photo/media preview experience.
- `screens/splash/`: Startup/loading/initialization screen.
- `services/`: External integrations and app services (API, local storage, etc.).
- `theme/`: App color scheme, typography, and theme extensions.
- `utils/`: Reusable helpers and small shared utilities.
- `widgets/`: Shared reusable UI components used across screens.