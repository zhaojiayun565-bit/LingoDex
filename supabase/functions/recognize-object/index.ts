// Supabase Edge Function: recognize-object
// Calls Gemini 3.1 Flash Lite with image + structured prompt; returns object metadata.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  image_base64: string;
  mime_type?: string;
  native_language: string;
  learning_language: string;
  bounding_box: string;
}

interface GeminiResponse {
  object_name: string | null;
  target_translation: string;
  phonetic_breakdown: string | null;
  category: string;
  confidence: number;
  example_sentences: string[];
  error_feedback?: string;
}

function buildPrompt(
  nativeLanguage: string,
  learningLanguage: string,
  boundingBox: string
): string {
  const systemPrompt = `You are an expert visual linguist for LingoDex, a language learning app.
Your goal is to identify a specific object within a provided image and generate educational metadata for a language learner.`;

  const userPrompt = `1. I am providing a full image. Focus your analysis on the object located at these normalized coordinates (the "Subject"): ${boundingBox}
2. Use the surrounding environment in the full image as context to ensure the identification is accurate (e.g., distinguishing a 'toy car' from a 'real car' based on scale/background).
3. Target Native Language: ${nativeLanguage}
4. Target Learning Language: ${learningLanguage}

3. Return the following data in a strictly formatted JSON object:
   - "object_name": The name of the item in ${nativeLanguage}.
   - "target_translation": The name of the item in ${learningLanguage}.
   - "phonetic_breakdown": The phonetic pronunciation of the target_translation (e.g., Romaji for Japanese, Pinyin for Mandarin, IPA for French/Spanish, or null if ${learningLanguage} is English or if not applicable).
   - "category": (e.g., Furniture, Nature, Kitchen).
   - "confidence": Your certainty score from 0.0 to 1.0.
   - "example_sentences": An array of TWO simple, beginner-level sentences in ${learningLanguage}.
   - "error_feedback": If confidence is below 0.6, provide a short instruction in ${nativeLanguage} on how the user can get a better photo (e.g., "Move closer", "Improve lighting").

RULES:
- If the object is unrecognizable, set "object_name" to null and provide "error_feedback".
- Focus on nouns that are useful for everyday conversation.
- Use the most natural, common term for the object (avoid overly technical jargon).
- Ensure "target_translation" includes any necessary gender markers or articles if applicable in ${learningLanguage}.

Respond with only the JSON object, no markdown or extra text.`;

  return `${systemPrompt}\n\nUSER PROMPT:\n${userPrompt}`;
}

function parseJsonFromText(text: string): GeminiResponse | null {
  try {
    const cleaned = text
      .replace(/^```json\s*/i, "")
      .replace(/\s*```\s*$/i, "")
      .trim();
    return JSON.parse(cleaned) as GeminiResponse;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("GEMINI_API_KEY not set");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

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

  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const {
    image_base64,
    mime_type = "image/jpeg",
    native_language,
    learning_language,
    bounding_box,
  } = body;

  if (!image_base64 || !native_language || !learning_language || !bounding_box) {
    return new Response(
      JSON.stringify({
        error: "Missing required fields: image_base64, native_language, learning_language, bounding_box",
      }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const prompt = buildPrompt(native_language, learning_language, bounding_box);

  const payload = {
    contents: [
      {
        parts: [
          { text: prompt },
          {
            inline_data: {
              mime_type,
              data: image_base64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1024,
      responseMimeType: "application/json",
      // Low resolution reduces image token usage (~280 tokens vs higher tiers).
      mediaResolution: "MEDIA_RESOLUTION_LOW",
    },
  };

  const geminiRes = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  if (!geminiRes.ok) {
    const errText = await geminiRes.text();
    console.error("Gemini API error:", geminiRes.status, errText);
    return new Response(
      JSON.stringify({ error: "Recognition service unavailable" }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const geminiJson = await geminiRes.json();
  const text = geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text;

  if (!text) {
    return new Response(
      JSON.stringify({ error: "Empty response from recognition service" }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const parsed = parseJsonFromText(text);
  if (!parsed) {
    return new Response(
      JSON.stringify({ error: "Invalid recognition response" }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(JSON.stringify(parsed), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
