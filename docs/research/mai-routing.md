# MAI-Transcribe-2 routing from India - without an own Azure account

Date: 2026-10-15 (measurements at 20:09-20:12 IST). Scope: lowest-latency route to Microsoft MAI-Transcribe-2 from India, if possible without an own Azure subscription. No sign-ups, no API keys, no paid calls. Only free unauthenticated GETs and network timing.

Raw data: `scratchpad/mai-net/` (`timings.txt`, `vercel-models.json`, `or-mai-endpoints.json`).

## Summary table

| Route | Own Azure? | Region choice? | Keyterm passthrough? | Price | Connect / TLS from this Mac (median) |
| --- | --- | --- | --- | --- | --- |
| OpenRouter `microsoft/mai-transcribe-2` | No | No (EU/US only, Business/Enterprise; no India) | Probably: `provider.options.azure.phraseList` (forwarded "as-is", not documented for phrase list) | `0.1` (read as $0.10/h, unit not stated) | TCP 5-7 ms, TLS 10-12 ms, Cloudflare BOM edge |
| Vercel AI Gateway `microsoft/mai-transcribe-2` | No | No (`inferenceRegion` us/eu only; MAI has no `regions`) | Yes, documented: `providerOptions.azure.phraseList.phrases` | $0.00002778/s = $0.10/h | TCP ~6 ms, TLS ~13 ms at bom1 edge, but compute in **cdg1 (Paris)**: +~200 ms TTFB |
| Vercel BYOK with own Azure `resourceName` | Yes | Indirect: your resource region (centralindia) - not confirmed for STT | Yes | Azure price, no Vercel markup; BYOK needs paid Vercel credits | Same Vercel hop as above |
| OpenRouter BYOK (Azure Foundry key) | Yes | Indirect: your resource region - not confirmed for STT | Probably | Azure price + 5% fee (first $25k/month free) | Same as OpenRouter |
| Direct Azure Speech, `centralindia` | Yes | Yes (6 regions incl. centralindia) | Yes, `phraseList.phrases` | $0.10/h promo to 2026-12-31 | TCP 9 ms, TLS 26 ms, Pune IP |

## 1. OpenRouter

- STT routing: "Other routing preferences (`order`, `only`, `ignore`) are not applied to transcription requests." Only `zdr`, `data_collection` and `provider.options` apply. https://openrouter.ai/docs/guides/overview/multimodal/stt
- So a request cannot pin a provider endpoint or region for STT. For MAI there is only one endpoint anyway: `Azure | microsoft/mai-transcribe-2-20260903`, `tag: "azure"`, no region in the tag. `GET https://openrouter.ai/api/v1/models/microsoft/mai-transcribe-2/endpoints` (saved in `or-mai-endpoints.json`).
- Provider options: "Pass provider-specific parameters through `provider.options`, keyed by the provider slug". Azure is one of the providers that "forward most fields as-is, so an invalid option usually surfaces as a provider error". The documented Azure example is diarization only. A phrase list is **not documented**; `provider.options.azure.phraseList` should work by the "as-is" rule. **Not confirmed.** https://openrouter.ai/docs/guides/overview/multimodal/stt
- In-region routing: `https://eu.openrouter.ai` and `https://us.openrouter.ai`, "on the Business and Enterprise plans". Only EU and US. An endpoint is eligible only if OpenRouter has onboarded it for that region. STT is not named; "audio" is in the guardrail scope list. No India or Asia region. https://openrouter.ai/docs/guides/features/in-region-routing , https://openrouter.ai/docs/guides/routing/provider-selection
- Edge: "Edge computing using Cloudflare Workers to stay as close as possible to your application." No region list. https://openrouter.ai/docs/guides/best-practices/latency-and-performance
  - Measured: `cf-ray ...-BOM`, `/cdn-cgi/trace` gives `colo=BOM`. A 404 on `/api/v1/audio/transcriptions` comes back 22 ms after TLS, so the Worker runs in Mumbai.
- Azure upstream region for MAI: **not published.** The endpoints API and docs do not name it. **Unknown.**
- BYOK: "STT supports BYOK ... requests are routed directly to the provider using your key." https://openrouter.ai/docs/guides/overview/multimodal/stt . Azure BYOK takes `api_key`, `resource_name`, `resource_type` (Foundry); no region field; fee "5% of what the same model/provider would cost normally on OpenRouter", with a $25,000/month free allowance; default fallback to shared capacity unless set to "Never use shared capacity". https://openrouter.ai/docs/guides/overview/auth/byok . That BYOK works for MAI STT with an Azure Speech resource is **not confirmed**. BYOK still needs an own Azure account.

## 2. Vercel AI Gateway

- Model ids (from `GET https://ai-gateway.vercel.sh/v1/models`, no key):
  - `microsoft/mai-transcribe-2`, type `transcription`, `zdr: "all"`, `transcription_duration_cost_per_second: "0.00002778"` = **$0.10/h**. Single endpoint `azure | microsoft/mai-transcribe-2` (`/v1/models/microsoft/mai-transcribe-2/endpoints`).
  - `microsoft/mai-transcribe-2-streaming`, tag `websocket-transcription`, pricing `{}` in the API. Model page says $0.54/h (search result, not fetched). https://vercel.com/ai-gateway/models/mai-transcribe-2-streaming . Launched on the gateway 2026-10-01. https://vercel.com/changelog/microsoft-ai-models-are-now-available-on-ai-gateway
- Transcription API: `POST https://ai-gateway.vercel.sh/v4/ai/transcription-model`, headers `ai-model-id`, `ai-gateway-protocol-version: 0.0.1`, `ai-transcription-model-specification-version: 4`, JSON body `{audio: <base64>, mediaType}`. "Multipart file uploads are not supported." AI SDK: `transcribe({ model: gateway.transcriptionModel('microsoft/mai-transcribe-2'), ... })`. Speech to text is "in beta and access is rolling out gradually". https://vercel.com/docs/ai-gateway/modalities/speech-to-text
- Keyterms: documented. "AI Gateway serves Microsoft models through Azure, so their options go under `providerOptions.azure`", example with `timestamps`, `transcribeStyle: 'clean'`, `diarization`, `phraseList: { phrases: [...] }`. MAI accepts "WAV, MP3, FLAC, and Ogg/Opus audio, but not WebM or MP4". https://vercel.com/docs/ai-gateway/modalities/speech-to-text
  - Note: the AI SDK Azure provider page says WAV/MP3/FLAC only. The two pages disagree on Ogg/Opus. https://ai-sdk.dev/providers/ai-sdk-providers/azure
- Region choice:
  - `order`/`only`/`sort` exist, but MAI has one provider (`azure`), so they do nothing. https://vercel.com/docs/ai-gateway/models-and-providers/provider-filtering-and-ordering
  - `inferenceRegion` takes only `us` or `eu`; "a model with no `regions` field doesn't support regional routing". Both MAI models have no `regions` field (checked in `vercel-models.json`). https://vercel.com/docs/ai-gateway/security-and-compliance/regional-inference
  - Gateway compute location: "your request can terminate and be processed in any Vercel region before AI Gateway forwards it to the provider. Region-pinned gateway hosts ... are coming." Same page.
  - Fluid compute regions: not applicable. The gateway is a Vercel-run service; your own Vercel function region does not set the gateway's region. **Inference, not stated in docs.**
- BYOK with own Azure: credential `{ apiKey, resourceName }`, per request through `providerOptions.gateway.byok.azure`. BYOK "is available on the paid tier" and needs purchased credits. Failed BYOK falls back to system credentials. https://vercel.com/docs/ai-gateway/authentication-and-byok/byok . The AI SDK Azure provider sends MAI to `https://{resourceName}.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe` and requires a resource in centralindia, eastus, northeurope, southeastasia, westus or westus2. https://ai-sdk.dev/providers/ai-sdk-providers/azure . So a `centralindia` resource would pin inference to India, but that the gateway BYOK path uses this code for transcription is **not confirmed**.
- Where Vercel serves us (measured):
  - `x-vercel-id: bom1::cdg1::...` on every hit of `/v4/ai/transcription-model` (3 of 3) and on `/v1/models` (cache MISS). bom1 = Mumbai edge, cdg1 = Paris compute.
  - Unauthenticated GET to the transcription path returns 400 "Missing or empty model identifier" **203 ms** (median) after TLS. OpenRouter's 404 at the BOM edge returns in 22 ms. The ~180 ms gap is the Mumbai to Paris round trip plus function time.
  - Then Paris calls Azure in an unknown region. For a real request, audio uploads go India -> Paris -> Azure. **This makes Vercel the slowest route from India today.** One sample only; the compute region can change.

## 3. Other routes without an own Azure account

- Microsoft Foundry (serverless / catalog): needs an Azure subscription and a Foundry resource. https://ai.azure.com/catalog/models/MAI-Transcribe-2 , https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- Gateways LiteLLM, Portkey, Helicone, Kong: listed as routes to MAI only through Microsoft Foundry, so they need your own Azure key. Source is an aggregator. https://www.llmreference.com/model/mai-transcribe-2
- MAI Playground (microsoft.ai): try-out UI. No public API found. **Not confirmed.**
- No other hosted aggregator (fal, Replicate, DeepInfra, Together, Eden AI) lists MAI-Transcribe-2 in search results. **Not confirmed; absence of evidence only.**
- Result: OpenRouter and Vercel AI Gateway are the only two found routes without an own Azure account.

## 4. Network timing from this Mac

Method: `curl -o /dev/null -s -w '%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{remote_ip}'`, 5 runs per URL, two passes at 20:09 and 20:12 IST. TCP = connect - DNS; TLS = appconnect - connect. Medians below. Some single runs had 1-3 s spikes (local Wi-Fi); medians ignore them.

| Host (path) | IP, geo (ipinfo) | DNS | TCP | TLS | Connect total | TTFB after TLS | Region header |
| --- | --- | --- | --- | --- | --- | --- | --- |
| openrouter.ai (`/api/v1/models/.../endpoints`) | 104.18.2.115, Cloudflare anycast | 4 | 7 | 12 | 23 | 40 | `cf-ray ...-BOM` |
| openrouter.ai (`/api/v1/audio/transcriptions`, 404) | 104.18.2/3.115 | 4 | 5 | 10 | 18 | 22 | `cf-ray ...-BOM` |
| ai-gateway.vercel.sh (`/v1/models`) | 64.239.109.65, AWS anycast | 6 | 6 | 12 | 24 | 23 | `x-vercel-id bom1::cdg1::` |
| ai-gateway.vercel.sh (`/v4/ai/transcription-model`, 400) | 64.239.109.129 | 5 | 55* | 13 | 74* | **203** | `x-vercel-id bom1::cdg1::` |
| centralindia.api.cognitive.microsoft.com (`/`) | 20.192.170.56, Pune IN, AS8075 | 5 | 9 | 26 | 41 | 10 | none |
| centralindia.stt.speech.microsoft.com (`/`, 404) | 20.192.44.106 | 4 | 10 | 14 | 28 | 11 | none |
| southeastasia.api.cognitive.microsoft.com (`/`) | 23.98.109.37 | 7 | 63 | 137 | 205 | 63 | none |

All values in ms. *Two spike runs in that pass; across all 10 Vercel runs the TCP median is ~6 ms and TLS ~13 ms.

Reading:
- All three first hops terminate in Mumbai/Pune within ~10 ms TCP. The first hop is not the difference.
- The difference is the second hop: OpenRouter (BOM Worker) -> Azure region unknown; Vercel (Paris compute) -> Azure region unknown; direct -> Pune.
- The MAI resource host is `<resource>.cognitiveservices.azure.com`; we could not time it without a resource. The `centralindia.*` hosts are a proxy for the same Pune region.

## Recommendation

- Without an own Azure account: use **OpenRouter** `microsoft/mai-transcribe-2`. Its edge runs in Mumbai; Vercel adds a measured Paris detour (~200 ms per request). Same $0.10/h. Pass the phrase list as `provider.options.azure.phraseList.phrases` and check the first response for a provider error.
- Before choosing, run a small paid A/B (for example 20 clips of 10-20 s, about 400 s of audio per route, so about $0.01 per route at $0.10/h) on OpenRouter vs Vercel to get real p50/p90 hotkey-to-text. That needs keys and a go.
- For the lowest latency, a direct Azure Speech resource in `centralindia` stays the best route (Pune, ~9 ms TCP, region pinned). It needs an own Azure account. Keep it as the upgrade path.

## Unresolved questions

1. Which Azure region serves OpenRouter's and Vercel's MAI traffic? Neither publishes it. A paid request with timing (or response headers such as `X-Provider-Name`) may give a hint.
2. Does OpenRouter forward `provider.options.azure.phraseList` to MAI? The docs imply yes; a paid call must confirm.
3. Is OpenRouter's `0.1` price per hour? A `usage.cost` check on one paid call would confirm.
4. Does Vercel always run gateway compute in cdg1 for India, or does it change with load? Repeat the header check on other days.
5. Do OpenRouter and Vercel BYOK work for MAI STT with an Azure Speech (Foundry) resource in `centralindia`? Docs do not say per model.
6. Vercel docs say MAI accepts Ogg/Opus; the AI SDK Azure page and Microsoft docs say WAV/MP3/FLAC only. Which is true for the gateway path?
7. Is Vercel transcription "beta, rolling out gradually" open to a new team today?
