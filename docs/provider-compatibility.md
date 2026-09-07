# Advanced provider selection: behavior and acceptance

Account switching is the default experience. Provider selection requires explicit opt-in in Settings. A configured provider is not evidence of a usable model or successful authentication.

## Current behavior

The switcher writes only `model_provider` through Codex app-server. It does not write `model`, reasoning settings, profiles, or model catalogs. It launches the installed Desktop normally and does not replace its backend or modify conversations.

| Transition | What the switcher changes | What still needs checking |
| --- | --- | --- |
| ChatGPT account to custom provider | Active provider | Retained model ID, model picker contents, authentication, successful request |
| Custom provider to ChatGPT account | Saved account credentials and `openai` provider | Retained model ID and catalog must work with ChatGPT |
| Provider does not support retained model | Provider still changes | Requests may fail until a compatible model is selected/configured |

The Desktop picker is owned by the installed Codex version. This feature cannot guarantee automatic deployment discovery or that a custom model appears. If Desktop exposes a compatible model, select it there. Otherwise configure the model in Codex before using the destination. Returning to ChatGPT does not restore the model or catalog previously used with ChatGPT. Both transition confirmations explain this limitation.

Provider and model are separate settings in the [official configuration guide](https://learn.chatgpt.com/docs/config-file/config-advanced#custom-model-providers).

## Evidence and limits of the earlier Azure test

The earlier local test used a configured Azure provider and model `gpt-5.6-sol`, followed by a modified Codex backend that parsed Azure's model-list response and exposed `gpt-6-astra`. A protocol query returned that model as visible. This was not a stock Desktop compatibility test or a recorded three-destination round trip with different model IDs. It cannot substantiate a general claim of seamless provider/model switching.

Backend packaging and `CODEX_CLI_PATH` were introduced to deploy that local experiment. They are not necessary to select a configured provider and have been removed from this PR's final diff. Neither the local backend patches nor their binaries are part of the upstream feature.

## Required Desktop acceptance run (pending)

Use unmodified, released Codex Desktop, a saved ChatGPT account, and an authorized custom provider. Record versions, provider IDs, model IDs and results without recording tokens or full configuration. Use harmless prompts, for example `Reply with OK`.

1. Start with ChatGPT. Record the visible picker choices and selected model in a new conversation. Send the prompt and record a successful response.
2. Enable advanced provider switching and select the configured custom provider. After restart, record the new-conversation selected model and picker choices before changing anything. Send a request using an available compatible model and record any manual configuration required.
3. Repeat with a destination requiring a different model ID. Record the unsupported retained-model behavior; determine whether Desktop permits selecting the working ID or Codex configuration must be edited. Record the successful request after selection/setup.
4. Switch back to a saved ChatGPT account. Record the retained custom model ID and picker contents. If necessary choose/configure a valid OpenAI model, then record a successful response in a new conversation.
5. Disable the advanced setting. Confirm provider rows disappear and active provider/configuration remain unchanged. Confirm account switching still works.

Configuration readback, mocks, parser tests, and a visible model-list protocol response do not satisfy these Desktop acceptance steps. Until this run is complete, this feature must not be described as verified seamless switching or ready to merge on that basis.

## Proposed follow-up scope (not implemented)

If seamless switching between different model IDs is required, agree on provider-specific model settings before extending this PR. A proposal should define explicit user selection of a model per provider, restoration of the user's previous OpenAI selection, interactions with profiles and custom catalogs, and atomic application/restoration through supported Codex configuration APIs. Unknown compatibility must remain explicit; do not choose a hardcoded model, infer Azure deployment aliases, inject catalogs, or silently fall back to another provider. Acceptance remains the stock Desktop round trip above.

## Privacy

`config/read` returns the full effective configuration, including inline credentials when present. Those values can enter process memory. The UI retains provider IDs/names, and the switcher does not display, log, or persist custom-provider credentials. Disabling advanced provider UI is not a promise that configuration is never read: account switching also reads it. Codex owns provider authentication; the switcher does not independently invoke its authentication commands.
