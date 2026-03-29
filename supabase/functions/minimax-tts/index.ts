import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(jwt);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } catch {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const apiKey = Deno.env.get("MINIMAX_API_KEY");
  const groupId = Deno.env.get("MINIMAX_GROUP_ID");

  if (!apiKey || !groupId) {
    return new Response("Server config error: Missing API Key or Group ID", { status: 500, headers: corsHeaders });
  }

  const { text, language } = await req.json();

  const voiceId = voiceByLanguage[language] || "Wise_Woman";

  // International keys (minimax.io) use https://api.minimax.io. China accounts may use https://api.minimaxi.com — set MINIMAX_API_BASE_URL if needed.
  const baseRaw = Deno.env.get("MINIMAX_API_BASE_URL") ?? "https://api.minimax.io";
  const base = baseRaw.replace(/\/$/, "");
  const minimaxUrl = `${base}/v1/t2a_v2?GroupId=${encodeURIComponent(groupId)}`;
  
  const minimaxRes = await fetch(minimaxUrl, {
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

  if (minimaxJson.base_resp && minimaxJson.base_resp.status_code !== 0) {
    const errorMsg = minimaxJson.base_resp.status_msg || "Unknown Minimax Error";
    return new Response(`Minimax API Error: ${errorMsg}`, { status: 502, headers: corsHeaders });
  }

  const audioBase64 = minimaxJson?.data?.audio || minimaxJson?.audio_base64;
  if (!audioBase64) return new Response("Empty audio response", { status: 502, headers: corsHeaders });

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
