# DailyMuse

DailyMuse is an early-stage macOS app that turns the day's headlines into AI-generated wallpaper art.

It collects headlines, asks an LLM to turn them into a visual prompt, sends that prompt to an image-generation endpoint you configure, processes the resulting image, and can set it as your macOS wallpaper.

## Features

- Fetches daily headlines from Hacker News or an RSS feed.
- Uses an OpenAI-compatible chat completion endpoint, including OpenRouter, to craft image prompts.
- Supports configurable image-generation endpoints, including OpenAI-compatible APIs, direct `/generate` servers, queued `/generate` servers, fal.ai queue endpoints, and ComfyUI.
- Saves generated PNG files and JSON sidecars to `~/Pictures/DailyMuse/`.
- Can optionally process images for a monochrome e-ink target.
- Can set generated images as the macOS wallpaper.
- Includes basic scheduling for automatic daily generation.

## Screenshot

No suitable screenshot is currently included in the repository.

## Requirements

- macOS 14 or later.
- Xcode capable of building the existing `DailyMuse.xcodeproj`.
- Access to suitable LLM and image-generation endpoints.

## Project Status

DailyMuse is currently an early-stage, source-built project. It is not packaged as a finished downloadable product in this repository, and you should expect to build it locally, configure your own endpoints, and adapt settings for your own services.

Known current limitations:

- Endpoint compatibility depends on the HTTP contract exposed by the service you configure.
- API keys and service URLs must be configured by the user; no credentials are included.
- The included history support is filesystem-based rather than a full in-app gallery.
- Scheduling is implemented inside the running app, so the app must be running for scheduled generation.

## Build and Run

1. Clone the repository.
2. Open `DailyMuse.xcodeproj`.
3. Select the DailyMuse target.
4. Configure the signing team and bundle identifier if necessary.
5. Build and run.

## First-Time Configuration

On first launch, open the settings window and configure:

- An LLM base URL, model name, and optional API key. The OpenRouter preset uses `https://openrouter.ai/api/v1` with `qwen/qwen3.5-flash-02-23`.
- An image-generation base URL, endpoint type, model or endpoint identifier when needed, and optional API key.
- A headline source, either Hacker News or an RSS feed URL.
- Generation settings such as image size, style, e-ink mode, and whether generated images should be set as wallpaper automatically.
- Optional scheduling settings.

DailyMuse does not include service credentials. Use credentials from the services you choose to connect.

## Privacy

DailyMuse stores configured API keys in the macOS Keychain.

Headlines, generated prompts, and related request data may be sent to whichever external LLM and image-generation services you configure. Review those services' privacy policies and terms before using them.

Generated images and JSON sidecars are saved locally in `~/Pictures/DailyMuse/`.

## Development

Architecture notes and contributor-oriented information live in [DEVELOPMENT.md](DEVELOPMENT.md).
