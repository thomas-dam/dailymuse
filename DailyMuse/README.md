# DailyMuse

Native macOS app that turns daily headlines into AI-generated wallpaper art. DailyMuse opens a setup window for preferences, then can stay running for scheduled wallpaper generation. Fully BYOK (Bring Your Own Keys) — works with any OpenAI-compatible LLM and image generation endpoint.

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
├── DailyMuseApp.swift           # @main entry, setup window
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
    └── SettingsView.swift       # Preferences: endpoints, style, schedule
```

## Setup in Xcode

1. Open `DailyMuse.xcodeproj`
2. Select the DailyMuse target
3. Set your bundle identifier and signing team in Xcode
4. Build target: macOS 14.0+

DailyMuse is a normal macOS app with a Dock icon and standard Xcode project settings. Use the setup window to configure endpoints, API keys, style, and schedule.

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
- LLM endpoint, model, and raw prompt response
- Image prompt generated
- Style template and output target used

## TODO

- [ ] History browser view with gallery
- [ ] Drag & drop custom style template editing
- [ ] Multiple headline source mixing
- [ ] Webhook upload support (TRMNL, etc.)
