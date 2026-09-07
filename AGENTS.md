# Known surprises

- A configured provider and successful `model_provider` readback do not prove inference or model-picker compatibility. Verify a stock Desktop round trip, including different model IDs, before claiming seamless switching. Keep incomplete acceptance evidence explicit in `docs/provider-compatibility.md`.
- `config/read` can include inline credentials in process memory. Never claim the switcher cannot receive secrets; do not display, log, or persist them.
- Custom Desktop backend packaging introduced in commit 944b848 was a local experiment and is excluded from the upstream provider-selection scope. Do not reintroduce backend overrides to make a provider test pass.
