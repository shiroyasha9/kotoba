// STT variants and the latency sample size, shared by the run and the report.

import { GROK, MAI, type SttVariant } from "../stt.ts";

export const VARIANTS: SttVariant[] = [
	{ key: "mai+auto", model: MAI, language: null },
	{ key: "mai+hi", model: MAI, language: "hi" },
	{ key: "grok+auto", model: GROK, language: null },
	// Today's setting: forced English. Same key as in kotoba-bench-v1.
	{ key: "mai", model: MAI },
];

/** Hinglish clips in the sequential latency pass. */
export const LATENCY_CLIPS = 20;
