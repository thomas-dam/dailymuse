# DailyMuse Development

This document contains internal development and architecture notes for DailyMuse. For a public overview, setup summary, and user-facing project status, see [README.md](README.md).

DailyMuse is a native macOS app that turns daily headlines into AI-generated wallpaper art. The app opens a setup window for preferences, then can stay running for scheduled wallpaper generation. It is BYOK (Bring Your Own Keys) and is designed to work with configurable LLM and image-generation endpoints.

## Architecture

```
Headlines -> LLM (prompt craft) -> Image Gen -> Post-process -> Set Wallpaper
   ^              ^                   ^
   HN / RSS    LM Studio          MFlux / Krea2
               Ollama              ComfyUI
               oMLX                fal.ai
               OpenAI              OpenAI-compatible APIs
               OpenRouter
               Any /v1/chat        Direct / queued image APIs
```

## Project Structure

```
DailyMuse/
|-- DailyMuseApp.swift           # @main entry, menu bar app and settings window
|-- Info.plist
|-- Models/
|   |-- AppState.swift           # Central state, persistence, scheduling, generation pipeline
|   |-- DailyMuseError.swift     # Error types
|   |-- StyleTemplate.swift      # Prompt style templates
|   |-- GenerationTarget.swift   # Web and e-ink generation target descriptions
|   `-- ImagePromptResult.swift  # Structured LLM prompt output
|-- Services/
|   |-- HeadlineFetcher.swift    # HN Firebase API + RSS parser
|   |-- ImageProcessor.swift     # E-ink dithering via Core Image/Graphics
|   |-- ImageService.swift       # Multi-backend image generation
|   |-- PromptService.swift      # OpenAI-compatible /v1/chat/completions
|   |-- WallpaperService.swift   # NSWorkspace.setDesktopImageURL
|   `-- KeychainHelper.swift     # macOS Keychain storage for API keys
`-- Views/
    |-- MenuBarView.swift        # Menu bar popover controls
    `-- SettingsView.swift       # Preferences: endpoints, generation, schedule
```

## Setup in Xcode

1. Open `DailyMuse.xcodeproj`
2. Select the DailyMuse target
3. Set your bundle identifier and signing team in Xcode if needed
4. Build target: macOS 14.0+

DailyMuse is a normal macOS app with a Dock icon and standard Xcode project settings. Use the setup window to configure endpoints, API keys, style, and schedule.

The LLM endpoint expects an OpenAI-compatible chat completions API. The OpenRouter preset sets the base URL to `https://openrouter.ai/api/v1` and the model to `qwen/qwen3.5-flash-02-23`.

## Image Endpoint Types

| Type | Description | Example |
|------|-------------|---------|
| OpenAI-compatible | `/v1/images/generations` returning b64 or URL | DALL-E-compatible APIs, fal.ai-compatible proxies |
| Local Direct | POST prompt -> raw PNG, base64, or image URL in the same response | MFlux server, Krea2-style local server |
| Queued /generate | POST prompt -> job/status/result URL, then poll for result | Generic queued image server |
| fal.ai Queue | Submit to fal.ai queue, poll status, fetch result image URL | `fal-ai/flux-2/klein/9b`, `fal-ai/z-image/turbo` |
| ComfyUI | Queue workflow + poll for result | ComfyUI localhost |

## Output

Generated images and JSON sidecars are saved to `~/Pictures/DailyMuse/`.

Each generation produces a timestamped PNG and a matching JSON with:

- Headlines used
- LLM endpoint, model, and raw prompt response
- Image endpoint, model, and response format
- Image prompt generated
- Style template and output target used

## TODO

- [ ] History browser view with gallery
- [ ] Drag-and-drop custom style template editing
- [ ] Multiple headline source mixing
- [ ] Webhook upload support
