import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  text: string;
  language: string;
}

interface MinimaxSuccessResponse {
  audio_base64: string;
  content_type: string;
}

const voiceByLanguage: Record<string, string> = {
  english: "male-qn-qingse",
  french: "female-tianmei-jingpin",
  spanish: "female-tianmei-jingpin",
  mandarinChinese: "female-shaonv",
  japanese: "female-tianmei-jingpin",
  korean: "female-tianmei-jingpin",
};

function buildMinimaxPayload(text: string, language: string, voiceId: string) {
  return {
    model: Deno.env.get("MINIMAX_TTS_MODEL") ?? "speech-02-hd",
    text,
    language,
    stream: false,
    audio_setting: {
      sample_rate: 32000,
      bitrate: 128000,
      format: "mp3",
      channel: 1,
    },
    voice_setting: {
      voice_id: voiceId,
      speed: 1,
      vol: 1,
      pitch: 0,
    },
  };
}

function extractAudioBase64(minimaxJson: any): string | null {
  return (
    minimaxJson?.data?.audio ??
    minimaxJson?.audio ??
    minimaxJson?.audio_base64 ??
    null
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const apiKey = Deno.env.get("MINIMAX_API_KEY");
  if (!apiKey) {
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const { text, language } = body;
  if (!text || !language) {
    return new Response(
      JSON.stringify({ error: "Missing required fields: text, language" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const voiceId = voiceByLanguage[language];
  if (!voiceId) {
    return new Response(
      JSON.stringify({ error: "Unsupported language" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const minimaxGroupId = Deno.env.get("MINIMAX_GROUP_ID");
  const minimaxBaseUrl = Deno.env.get("MINIMAX_TTS_URL") ??
    (minimaxGroupId
      ? `https://api.minimaxi.com/v1/t2a_v2?GroupId=${encodeURIComponent(minimaxGroupId)}`
      : "https://api.minimaxi.com/v1/t2a_v2");
  const payload = buildMinimaxPayload(text, language, voiceId);

  const minimaxRes = await fetch(minimaxBaseUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(payload),
  });

  if (!minimaxRes.ok) {
    const errText = await minimaxRes.text();
    console.error("Minimax API error:", minimaxRes.status, errText);
    return new Response(
      JSON.stringify({ error: "TTS service unavailable" }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const minimaxJson = await minimaxRes.json();
  const audioBase64 = extractAudioBase64(minimaxJson);
  if (!audioBase64) {
    return new Response(
      JSON.stringify({ error: "Empty audio response from TTS service" }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const responseBody: MinimaxSuccessResponse = {
    audio_base64: audioBase64,
    content_type: "audio/mpeg",
  };

  return new Response(JSON.stringify(responseBody), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
