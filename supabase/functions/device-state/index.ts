import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-device-key",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const url = new URL(req.url);
  const deviceId = url.searchParams.get("device_id");

  if (!deviceId) {
    return new Response(JSON.stringify({ error: "Missing device_id query parameter" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  // 1. Fetch device and settings
  const { data: device, error: devErr } = await supabase
    .from("devices")
    .select("id, last_seen_at")
    .eq("id", deviceId)
    .maybeSingle();

  if (devErr || !device) {
    return new Response(JSON.stringify({ error: "Device not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const { data: settings } = await supabase
    .from("settings")
    .select("offline_threshold_seconds")
    .eq("id", 1)
    .single();

  const offlineThreshold = settings?.offline_threshold_seconds ?? 120;
  const now = Date.now();
  const lastSeenMs = device.last_seen_at ? new Date(device.last_seen_at).getTime() : 0;
  const isOffline = now - lastSeenMs > offlineThreshold * 1000;

  // LED Logic Rule:
  // "unknown" = sensor offline
  if (isOffline) {
    return new Response(JSON.stringify({ led: "unknown", reason: "sensor_offline" }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 2. Fetch room associated with device
  const { data: room } = await supabase
    .from("rooms")
    .select("id")
    .eq("device_id", deviceId)
    .maybeSingle();

  // 3. Fetch latest sensor reading
  const { data: latestReading } = await supabase
    .from("sensor_readings")
    .select("presence, recorded_at")
    .eq("device_id", deviceId)
    .order("recorded_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const presenceDetected = latestReading?.presence === true;

  if (!room) {
    // No room linked to device
    const led = presenceDetected ? "red" : "green";
    return new Response(JSON.stringify({ led }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 4. Fetch current active or pending booking for this room
  const nowIso = new Date().toISOString();
  const { data: activeBooking } = await supabase
    .from("bookings")
    .select("id, status, start_time, end_time")
    .eq("room_id", room.id)
    .in("status", ["reserved", "confirm_pending", "active"])
    .lte("start_time", nowIso)
    .gt("end_time", nowIso)
    .order("start_time", { ascending: true })
    .limit(1)
    .maybeSingle();

  let led: "green" | "yellow" | "red" | "unknown" = "green";

  // Specification LED logic:
  // red = active booking with presence, or presence with no booking
  // yellow = reserved or confirm_pending
  // green = free
  // unknown = sensor offline
  if (!activeBooking) {
    if (presenceDetected) {
      led = "red"; // presence with no booking (walk-in or unexpected)
    } else {
      led = "green"; // free
    }
  } else {
    if (activeBooking.status === "active") {
      led = "red"; // occupied / active
    } else if (activeBooking.status === "reserved" || activeBooking.status === "confirm_pending") {
      led = "yellow";
    }
  }

  return new Response(
    JSON.stringify({
      led,
      device_id: deviceId,
      room_id: room.id,
      booking_status: activeBooking?.status ?? null,
      presence: presenceDetected,
    }),
    {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
});
