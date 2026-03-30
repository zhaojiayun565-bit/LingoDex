import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_TTS_MODEL = "gemini-2.5-flash-preview-tts";

const voiceByLanguage: Record<string, string> = {
  english: "Puck",
  french: "Aoede",
  spanish: "Vindemiatrix",
  mandarinChinese: "Zubenelgenubi",
  japanese: "Charon",
  korean: "Kore",
};

/** BCP-47 codes paired with app `language` keys (Gemini SpeechConfig.languageCode). */
const languageCodeByAppLanguage: Record<string, string> = {
  english: "en-US",
  french: "fr-FR",
  spanish: "es-ES",
  mandarinChinese: "cmn-CN",
  japanese: "ja-JP",
  korean: "ko-KR",
};

/** Human-readable language name for TTS prompt context (matches app `Language` display names). */
const displayLanguageByAppLanguage: Record<string, string> = {
  english: "English",
  french: "French",
  spanish: "Spanish",
  mandarinChinese: "Mandarin Chinese (Simplified)",
  japanese: "Japanese",
  korean: "Korean",
};

/** Four core harm categories with BLOCK_NONE (TTS does not support civic integrity category). */
const SAFETY_SETTINGS_BLOCK_NONE = [
  { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
  { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
] as const;

/** Prepends a 44-byte RIFF/WAV header for 24kHz mono 16-bit signed PCM. */
function pcm16MonoToWav(pcm: Uint8Array, sampleRate = 24000): Uint8Array {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
  const blockAlign = numChannels * (bitsPerSample / 8);
  const dataSize = pcm.length;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  const writeStr = (offset: number, s: string) => {
    for (let i = 0; i < s.length; i++) {
      view.setUint8(offset + i, s.charCodeAt(i));
    }
  };

  writeStr(0, "RIFF");
  view.setUint32(4, 36 + dataSize, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);
  writeStr(36, "data");
  view.setUint32(40, dataSize, true);

  const out = new Uint8Array(buffer);
  out.set(pcm, 44);
  return out;
}

function isRiffWav(bytes: Uint8Array): boolean {
  return (
    bytes.length >= 4 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46
  );
}

/** Parses rate from MIME like audio/pcm;rate=24000 */
function sampleRateFromMime(mime: string | undefined): number {
  if (!mime) return 24000;
  const m = /rate=(\d+)/i.exec(mime);
  return m ? parseInt(m[1], 10) : 24000;
}

type InlineAudio = { b64: string; mimeType: string };

/** Finds the first inline audio part (Gemini may return multiple parts). */
function extractInlineAudio(parts: unknown): InlineAudio | null {
  if (!Array.isArray(parts)) return null;
  for (const part of parts) {
    const p = part as { inlineData?: { data?: string; mimeType?: string }; inline_data?: { data?: string; mime_type?: string } };
    const inline = p?.inlineData ?? p?.inline_data;
    const b64 = inline?.data;
    if (b64 && typeof b64 === "string") {
      const mimeType = inline?.mimeType ?? inline?.mime_type ?? "";
      return { b64, mimeType };
    }
  }
  return null;
}

/** Logs non-audio diagnostics when finishReason is OTHER or audio is missing (no user text in logs). */
function logGeminiDiagnostics(label: string, geminiJson: Record<string, unknown>) {
  const c = geminiJson?.candidates as Record<string, unknown>[] | undefined;
  const cand0 = Array.isArray(c) && c.length > 0 ? (c[0] as Record<string, unknown>) : null;
  const parts = cand0?.content as { parts?: unknown[] } | undefined;
  const partsLen = Array.isArray(parts?.parts) ? parts!.parts!.length : 0;
  console.warn(`gemini-tts ${label}:`, JSON.stringify({
    promptFeedback: geminiJson.promptFeedback,
    finishReason: cand0?.finishReason,
    safetyRatings: cand0?.safetyRatings,
    blockReason: cand0?.blockReason,
    partsCount: partsLen,
  }));
}

/** Builds request body for Gemini TTS. Omit languageCode on fallback — docs say language is auto-detected. */
function buildTtsPayload(
  promptText: string,
  voiceName: string,
  languageCode: string | undefined,
) {
  return {
    contents: [{ parts: [{ text: promptText }] }],
    safetySettings: [...SAFETY_SETTINGS_BLOCK_NONE],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: {
        ...(languageCode ? { languageCode } : {}),
        voiceConfig: {
          prebuiltVoiceConfig: {
            voiceName,
          },
        },
      },
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  } catch {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const apiKey = (Deno.env.get("GEMINI_API_KEY") || "").replace(/['"]/g, "").trim();
  if (!apiKey) {
    return new Response("Server config error: Missing GEMINI_API_KEY", { status: 500, headers: corsHeaders });
  }

  const model = (Deno.env.get("GEMINI_TTS_MODEL") || DEFAULT_TTS_MODEL).trim();
  const geminiUrl =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;

  let body: { text?: string; language?: string };
  try {
    body = (await req.json()) as { text?: string; language?: string };
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { text, language } = body;
  if (!text || !language) {
    return new Response(JSON.stringify({ error: "Missing text or language" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const voiceName = voiceByLanguage[language] || "Puck";
  const languageCode = languageCodeByAppLanguage[language] ?? "en-US";
  const languageDisplay = displayLanguageByAppLanguage[language] ?? "English";
  const langHint = language === "mandarinChinese" ? "Mandarin Chinese (Simplified)" : languageDisplay;
  const ttsPrompt = `Pronounce the following ${langHint} word: ${text}`;
  const primaryPayload = buildTtsPayload(ttsPrompt, voiceName, languageCode);

  console.log("Generating audio for:", ttsPrompt, "| app language:", language, "| voice:", voiceName, "| languageCode:", languageCode);
  console.log(
    "gemini-tts payload check: safetySettings entries=",
    primaryPayload.safetySettings.length,
    "BLOCK_NONE categories=",
    primaryPayload.safetySettings.map((s) => s.category).join(",")
  );

  async function requestGemini(payload: ReturnType<typeof buildTtsPayload>) {
    const geminiRes = await fetch(geminiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      console.error("Gemini TTS API error:", geminiRes.status, errText);
      return { ok: false as const, geminiJson: null as Record<string, unknown> | null };
    }
    const geminiJson = (await geminiRes.json()) as Record<string, unknown>;
    return { ok: true as const, geminiJson };
  }

  let { ok: geminiOk, geminiJson } = await requestGemini(primaryPayload);
  if (!geminiOk || !geminiJson) {
    return new Response("Gemini TTS service unavailable", { status: 502, headers: corsHeaders });
  }

  const cand0 = geminiJson.candidates as Record<string, unknown>[] | undefined;
  const finishReason = Array.isArray(cand0) && cand0[0] ? (cand0[0] as { finishReason?: string }).finishReason : undefined;
  let parts = (cand0?.[0] as { content?: { parts?: unknown[] } } | undefined)?.content?.parts;
  let inline = extractInlineAudio(parts);

  console.log("Gemini finishReason:", finishReason, "| inline audio:", inline ? "yes" : "no");

  if (!inline && finishReason === "OTHER") {
    logGeminiDiagnostics("primary OTHER / no audio", geminiJson);
  }

  // Retry: intermittent OTHER with no audio — simpler prompt + voice only (no languageCode; model auto-detects language).
  if (!inline) {
    const fallbackPrompt = `Say: ${text.trim()}`;
    const fallbackPayload = buildTtsPayload(fallbackPrompt, voiceName, undefined);
    console.log("gemini-tts retry (fallback prompt, no languageCode):", fallbackPrompt, "| voice:", voiceName);
    const second = await requestGemini(fallbackPayload);
    if (second.ok && second.geminiJson) {
      geminiJson = second.geminiJson;
      const c2 = geminiJson.candidates as Record<string, unknown>[] | undefined;
      const fr2 = Array.isArray(c2) && c2[0] ? (c2[0] as { finishReason?: string }).finishReason : undefined;
      parts = (c2?.[0] as { content?: { parts?: unknown[] } } | undefined)?.content?.parts;
      inline = extractInlineAudio(parts);
      console.log("Gemini retry finishReason:", fr2, "| inline audio:", inline ? "yes" : "no");
      if (!inline) {
        logGeminiDiagnostics("after retry still no audio", geminiJson);
      }
    }
  }

  if (!inline) {
    return new Response("Empty audio from Gemini", { status: 502, headers: corsHeaders });
  }

  const b64 = inline.b64;
  const mimeType = inline.mimeType;

  let raw: Uint8Array;
  try {
    const binary = atob(b64);
    raw = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      raw[i] = binary.charCodeAt(i);
    }
  } catch {
    return new Response("Invalid audio data from Gemini", { status: 502, headers: corsHeaders });
  }

  let wavBytes: Uint8Array;
  const mimeLower = mimeType.toLowerCase();
  if (mimeLower.includes("mpeg") || mimeLower.includes("mp3")) {
    return new Response(raw, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "audio/mpeg",
        "Content-Length": raw.length.toString(),
      },
    });
  }

  if (isRiffWav(raw)) {
    wavBytes = raw;
  } else {
    const rate = sampleRateFromMime(mimeType);
    wavBytes = pcm16MonoToWav(raw, rate);
  }

  return new Response(wavBytes, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "audio/wav",
      "Content-Length": wavBytes.length.toString(),
    },
  });
});
