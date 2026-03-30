import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_TTS_MODEL = "gemini-2.5-flash-lite-preview-tts";

const voiceByLanguage: Record<string, string> = {
  english: "Puck",
  french: "Charon",
  spanish: "Vindemiatrix",
  mandarinChinese: "Kore",
  japanese: "Kore",
  korean: "Sulafat",
};

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

  const payload = {
    contents: [{ parts: [{ text }] }],
    generationConfig: {
      responseModalities: ["AUDIO"],
      speechConfig: {
        voiceConfig: {
          prebuiltVoiceConfig: {
            voiceName,
          },
        },
      },
    },
  };

  const geminiRes = await fetch(geminiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!geminiRes.ok) {
    const errText = await geminiRes.text();
    console.error("Gemini TTS API error:", geminiRes.status, errText);
    return new Response("Gemini TTS service unavailable", { status: 502, headers: corsHeaders });
  }

  const geminiJson = await geminiRes.json();
  const parts = geminiJson?.candidates?.[0]?.content?.parts;
  const part = Array.isArray(parts) ? parts[0] : null;
  const inline = part?.inlineData ?? part?.inline_data;
  const b64 = inline?.data;
  const mimeType = inline?.mimeType ?? inline?.mime_type ?? "";

  if (!b64 || typeof b64 !== "string") {
    return new Response("Empty audio from Gemini", { status: 502, headers: corsHeaders });
  }

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
