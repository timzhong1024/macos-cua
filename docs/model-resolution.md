# Model Resolution Guide

`macos-cua` normalizes screenshots to logical action-space dimensions rather than Retina-native pixels.

That is ideal when your vision model can consume the screenshot at full useful resolution. If a model or client stack downsamples the image before inference, `image space` and `action space` stop being 1:1.

## Operating Rule

- if the screenshot stays within the model's effective vision resolution, prefer absolute coordinates
- if the screenshot must be downsampled, tiled, or compressed before inference, prefer `--relative`
- if the desktop is too large, crop first before switching modes

## Current Model Notes

As of 2026-04-18, public vendor docs indicate the following:

| Model | Publicly documented vision sizing | Operational note |
| --- | --- | --- |
| [`gpt-5.4`](https://developers.openai.com/api/docs/models/gpt-5.4) | OpenAI documents `detail: "original"` for `gpt-5.4` and future models, with up to 10,000 patches or a 6000 px max dimension. `detail: "high"` allows up to 2,500 patches or 2048 px. See the [Images and vision guide](https://developers.openai.com/api/docs/guides/images-vision). | Best default for dense UI, localization, and full-screen computer-use screenshots. |
| [`gpt-5.4-mini`](https://developers.openai.com/api/docs/models/gpt-5.4-mini) | OpenAI documents `low`, `high`, and `auto`. `high` allows up to 1,536 patches or a 2048 px max dimension. See the [Images and vision guide](https://developers.openai.com/api/docs/guides/images-vision). | Good lower-cost option, but with less headroom for full desktop screenshots. |
| [Claude Opus 4.7](https://platform.claude.com/docs/en/build-with-claude/vision) | Anthropic documents a higher native image resolution for Opus 4.7: up to 4,784 tokens and 2576 px on the long edge. | Strong Claude option for screenshot-heavy workflows. |
| [Current other Claude vision models](https://platform.claude.com/docs/en/build-with-claude/vision) | Anthropic documents 1568 px on the long edge for other models and explicitly calls out Opus 4.7 as the high-resolution exception. Their vision guide also uses Sonnet 4.6 cost examples under this shared limit. | Treat Sonnet 4.5/4.6 and pre-4.7 Opus 4.x as lower-headroom choices. Crop early and use [`--relative`](relative-mode.md) if you must downsample. |

## Claude Note

Anthropic's current public vision guide does not publish a separate sizing table for every 4.x snapshot.

The Opus 4.7 exception is explicit in the docs.

Mapping Sonnet 4.5/4.6 and pre-4.7 Opus 4.x into the shared 1568 px bucket is an inference from the current public guidance, not a separately published per-model limit.

## Recommendation Floor

Models materially weaker than `gpt-5.4-mini` or current Claude Sonnet/Opus vision models are not recommended for coordinate-driven desktop control.

In practice that means older mini, nano, or haiku-class vision models should only be used with aggressive cropping and with [`--relative`](relative-mode.md) as the safer action mode.
