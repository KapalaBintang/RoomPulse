import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-device-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function sha256(str: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const deviceKey = req.headers.get("x-device-key");
  if (!deviceKey) {
    return new Response(JSON.stringify({ error: "Missing x-device-key header" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: any;
  try {
    body = await req.json();
  } catch (_e) {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const {
    device_id,
    presence,
    moving,
    stationary,
    moving_energy,
    static_energy,
    distance_cm,
    source,
    label,
  } = body || {};

  // Validate body fields
  if (
    typeof device_id !== "string" ||
    typeof presence !== "boolean" ||
    typeof moving !== "boolean" ||
    typeof stationary !== "boolean" ||
    typeof moving_energy !== "number" ||
    typeof static_energy !== "number" ||
    typeof distance_cm !== "number"
  ) {
    return new Response(
      JSON.stringify({
        error: "Malformed body: device_id, presence, moving, stationary, moving_energy, static_energy, distance_cm are required",
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // Authenticate device via hash
  const keyHash = await sha256(deviceKey);
  const isSimulatorMasterKey = deviceKey === "sim_key_default_dev";

  const { data: device, error: deviceErr } = await supabase
    .from("devices")
    .select("id, api_key_hash")
    .eq("id", device_id)
    .maybeSingle();

  if (deviceErr || !device) {
    return new Response(JSON.stringify({ error: "Unknown device" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (device.api_key_hash !== keyHash && !isSimulatorMasterKey) {
    return new Response(JSON.stringify({ error: "Invalid device key" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Determine source: simulator if simulator key used or explicitly tagged as simulator
  const sourceValue = isSimulatorMasterKey || source === "simulator" ? "simulator" : "device";

  // Ingest reading
  const { error: insertErr } = await supabase.from("sensor_readings").insert({
    device_id,
    presence,
    moving,
    stationary,
    moving_energy,
    static_energy,
    distance_cm,
    source: sourceValue,
    label: label ?? null,
  });

  if (insertErr) {
    return new Response(JSON.stringify({ error: insertErr.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Update device heartbeat last_seen_at
  await supabase
    .from("devices")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("id", device_id);

  return new Response(
    JSON.stringify({
      success: true,
      device_id,
      recorded_source: sourceValue,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
});
