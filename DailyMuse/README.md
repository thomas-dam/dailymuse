# DailyMuse

Native macOS menu bar app that turns daily headlines into AI-generated wallpaper art. Fully BYOK (Bring Your Own Keys) — works with any OpenAI-compatible LLM and image generation endpoint.

## Architecture

```
Headlines → LLM (prompt craft) → Image Gen → Post-process → Set Wallpaper
   ↑              ↑                   ↑
   HN / RSS    LM Studio          MFlux / Krea2
               Ollama              ComfyUI
               oMLX                OpenAI
               OpenAI              Stability
               Any /v1/chat        Any image API
```

## Project Structure

```
DailyMuse/
├── DailyMuseApp.swift           # @main entry, MenuBarExtra
├── Models/
│   ├── AppState.swift           # Central state, generation pipeline
│   ├── DailyMuseError.swift     # Error types
│   └── StyleTemplate.swift      # Prompt style templates (editorial, desk, etc.)
├── Services/
│   ├── HeadlineFetcher.swift    # HN Firebase API + RSS parser
│   ├── PromptService.swift      # OpenAI-compatible /v1/chat/completions
│   ├── ImageService.swift       # Multi-backend image generation
│   ├── ImageProcessor.swift     # E-ink dithering via Core Image/Graphics
│   └── WallpaperService.swift   # NSWorkspace.setDesktopImageURL
└── Views/
    ├── MenuBarView.swift        # Menu bar dropdown UI
    └── SettingsView.swift       # Preferences: endpoints, style, schedule
```

## Setup in Xcode

1. Create a new macOS App project (SwiftUI, Swift)
2. Bundle ID: `com.yourdomain.DailyMuse`
3. Copy all `.swift` files into the project
4. Set "Application is agent (UIElement)" = YES in Info.plist
   (this hides the Dock icon — menu bar only)
5. Build target: macOS 14.0+

## Image Endpoint Types

| Type | Description | Example |
|------|-------------|---------|
| OpenAI-compatible | `/v1/images/generations` returning b64 or URL | DALL-E, FAL.ai |
| Local Direct | POST prompt → raw PNG bytes | MFlux server, Krea2 |
| ComfyUI | Queue workflow + poll for result | ComfyUI localhost |

## Output

Generated images and JSON sidecars are saved to `~/Pictures/DailyMuse/`.
Each generation produces a timestamped PNG and a matching JSON with:
- Headlines used
- LLM endpoint and model
- Image prompt generated
- Style template used

## TODO

- [ ] SMAppService login item registration
- [ ] Keychain storage for API keys
- [ ] History browser view with gallery
- [ ] Drag & drop custom style template editing
- [ ] Multiple headline source mixing
- [ ] Webhook upload support (TRMNL, etc.)
- [ ] Notification on generation complete
