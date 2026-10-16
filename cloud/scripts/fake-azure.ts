import { FLAC_HEAD_BYTES, readStreamInfo } from "../src/flac";

/**
 * A local stand-in for Azure fast transcription (`POST /speechtotext/transcriptions:transcribe`), so `wrangler dev`
 * can run the real AzureTranscriber with no Azure account and no cost. It parses the multipart body as Azure would and
 * answers in Azure's shape. Usage: `bun run fake-azure` (port 8788, FAKE_AZURE_DELAY_MS to add a reply delay).
 */
export function serveFakeAzure(port: number, delayMs = 0) {
  return Bun.serve({
    port,
    hostname: "127.0.0.1",
    async fetch(request) {
      const url = new URL(request.url);
      if (request.method !== "POST" || url.pathname !== "/speechtotext/transcriptions:transcribe") {
        return Response.json({ error: { code: "NotFound" } }, { status: 404 });
      }
      if (!request.headers.get("Ocp-Apim-Subscription-Key")) {
        return Response.json({ error: { code: "Unauthorized" } }, { status: 401 });
      }
      const form = await request.formData();
      const definition = JSON.parse(String(form.get("definition") ?? "{}"));
      const audio = form.get("audio");
      if (typeof audio === "string" || audio === null || definition?.enhancedMode?.model !== "MAI-Transcribe-2") {
        return Response.json({ error: { code: "InvalidRequest" } }, { status: 400 });
      }
      const head = new Uint8Array(await audio.slice(0, FLAC_HEAD_BYTES).arrayBuffer());
      if (delayMs > 0) await Bun.sleep(delayMs);
      const durationMilliseconds = Math.round((readStreamInfo(head).seconds ?? 1) * 1000);
      return Response.json({
        durationMilliseconds,
        combinedPhrases: [{ text: `Fake Azure transcript of ${audio.size} bytes.` }],
        phrases: [],
      });
    },
  });
}

if (import.meta.main) {
  const server = serveFakeAzure(Number(process.env.PORT ?? 8788), Number(process.env.FAKE_AZURE_DELAY_MS ?? 0));
  console.log(`fake Azure on ${server.url}`);
}
