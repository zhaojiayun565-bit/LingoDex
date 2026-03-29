import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Updated to use standard default System Voice IDs for each language
const voiceByLanguage: Record<string, string> = {
  english: "English_radiant_girl",
  french: "French_standard_female",
  spanish: "Spanish_standard_female",
  mandarinChinese: "Chinese (Mandarin)_Sweet_Lady",
  japanese: "Japanese_standard_female",
  korean: "Korean_standard_female",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  const apiKey = Deno.env.get("MINIMAX_API_KEY");
  if (!apiKey) return new Response("Server configuration error", { status: 500, headers: corsHeaders });

  const { text, language } = await req.json();

  // Fallback to a generic clear voice if the language isn't in our map
  const voiceId = voiceByLanguage[language] || "English_radiant_girl";

  // Minimax API Call
  const minimaxRes = await fetch("https://api.minimaxi.com/v1/t2a_v2", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: "speech-02-hd",
      text,
      stream: false,
      audio_setting: {
        sample_rate: 32000,
        bitrate: 128000,
        format: "mp3",
        channel: 1
      },
      voice_setting: {
        voice_id: voiceId,
        speed: 1,
        vol: 1,
        pitch: 0
      },
    }),
  });

  if (!minimaxRes.ok) return new Response("TTS service unavailable", { status: 502, headers: corsHeaders });

  const minimaxJson = await minimaxRes.json();
  const audioBase64 = minimaxJson?.data?.audio || minimaxJson?.audio_base64;
  if (!audioBase64) return new Response("Empty audio response", { status: 502, headers: corsHeaders });

  // Convert Base64 to binary raw MP3 buffer
  const audioBuffer = Uint8Array.from(atob(audioBase64), (c) => c.charCodeAt(0));

  return new Response(audioBuffer, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "audio/mpeg",
      "Content-Length": audioBuffer.length.toString()
    },
  });
});
