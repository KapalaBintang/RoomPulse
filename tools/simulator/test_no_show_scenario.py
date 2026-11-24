#!/usr/bin/env python3
"""
RoomPulse End-to-End No-Show Journey Automated Scenario Runner
Simulates the entire no-show journey with demo timers:
1. Student Alice creates booking for Room 101.
2. Device sends 'empty' telemetry (nobody arrives).
3. System transitions to 'confirm_pending' and generates user notification.
4. No confirmation arrives before deadline.
5. Rule engine releases the booking automatically.
6. Asserts room status is 'available', booking is 'released', door LED is 'green'.
"""

import sys
import time
import json
import urllib.request
import urllib.error

SUPABASE_URL = "http://127.0.0.1:54321"
EDGE_FUNCTIONS_URL = f"{SUPABASE_URL}/functions/v1"
SERVICE_ROLE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTYwMDAwMDAwMCwiZXhwIjoyMDAwMDAwMDAwfQ.dummy_service_role_key"
ROOM_101_ID = "11111111-1111-1111-1111-111111111111"
DEVICE_101_ID = "device-room-101"
SIM_KEY = "sim_key_default_dev"
STUDENT_ALICE_ID = "b2222222-2222-2222-2222-222222222222"

def db_query(sql, is_select=False):
    """Executes SQL query via Supabase internal postgres REST or pg connection."""
    # We can also call RPC via REST
    pass

def rest_call(endpoint, method="GET", body=None, headers=None):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    req_headers = {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation"
    }
    if headers:
        req_headers.update(headers)
    
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            text = resp.read().decode("utf-8")
            return resp.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(err_body)
        except Exception:
            return e.code, {"error": err_body}

def rpc_call(fn_name, params=None):
    url = f"{SUPABASE_URL}/rest/v1/rpc/{fn_name}"
    headers = {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    data = json.dumps(params or {}).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))

def post_telemetry(presence=False, moving=False, stationary=False, static_energy=0):
    url = f"{EDGE_FUNCTIONS_URL}/device-telemetry"
    body = {
        "device_id": DEVICE_101_ID,
        "presence": presence,
        "moving": moving,
        "stationary": stationary,
        "moving_energy": 0,
        "static_energy": static_energy,
        "distance_cm": 0,
        "source": "simulator"
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-device-key": SIM_KEY},
        method="POST"
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

def get_door_led():
    url = f"{EDGE_FUNCTIONS_URL}/device-state?device_id={DEVICE_101_ID}"
    req = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read().decode("utf-8"))

def run_e2e_scenario():
    print("======================================================================")
    print("RoomPulse: Running End-to-End Ghost Booking Release Scenario")
    print("======================================================================")

    # 1. Configure Demo Timers: 10s no-show check, 10s confirm window, 30s offline threshold
    print("[1/6] Configuring Demo Timers...")
    rest_call("settings?id=eq.1", "PATCH", {
        "demo_mode": True,
        "no_show_seconds": 6,
        "confirm_window_seconds": 6,
        "offline_threshold_seconds": 30,
        "presence_window_seconds": 5
    })

    # Clean existing bookings for room 101
    rest_call(f"bookings?room_id=eq.{ROOM_101_ID}", "DELETE")

    # 2. Student Alice Books Room 101 starting now
    print("[2/6] Alice creates booking for Room 101...")
    start_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    now_ms = time.time()
    no_show_at = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now_ms + 6))
    end_time = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now_ms + 3600))

    status_code, bookings = rest_call("bookings", "POST", {
        "room_id": ROOM_101_ID,
        "user_id": STUDENT_ALICE_ID,
        "start_time": start_time,
        "end_time": end_time,
        "status": "reserved",
        "no_show_check_at": no_show_at
    })
    booking = bookings[0]
    booking_id = booking["id"]
    print(f"      Booking created (ID: {booking_id}) with status 'reserved'")

    # Send empty telemetry (sensor is online, room is empty)
    post_telemetry(presence=False)
    led_state = get_door_led()
    print(f"      Current Door LED: {led_state.get('led').upper()} (Expected: YELLOW)")
    assert led_state.get("led") == "yellow", f"Expected yellow, got {led_state.get('led')}"

    # 3. Wait for no_show_seconds to elapse while sending empty telemetry
    print("[3/6] Room remains empty for 7 seconds (waiting for no-show window)...")
    for _ in range(7):
        time.sleep(1)
        post_telemetry(presence=False)

    # Trigger rule engine
    print("      Evaluating rules...")
    rpc_call("run_rules")

    _, updated_bookings = rest_call(f"bookings?id=eq.{booking_id}")
    booking_state = updated_bookings[0]
    print(f"      Booking status after no-show check: {booking_state['status'].upper()}")
    assert booking_state["status"] == "confirm_pending", f"Expected confirm_pending, got {booking_state['status']}"
    assert booking_state["confirm_deadline"] is not None, "Confirm deadline must be set"
    print(f"      Confirm deadline set to: {booking_state['confirm_deadline']}")

    # Check notification created for Alice
    _, notifications = rest_call(f"notifications?booking_id=eq.{booking_id}")
    assert len(notifications) > 0, "Expected confirmation notification for Alice"
    print(f"      Notification dispatched: '{notifications[0]['message']}'")

    # 4. Wait for confirm_deadline to expire without reply
    print("[4/6] Alice does not reply, room remains physically empty (waiting 7s)...")
    for _ in range(7):
        time.sleep(1)
        post_telemetry(presence=False)

    # Trigger rule engine to process expired confirmation
    print("      Evaluating rules...")
    rpc_call("run_rules")

    # 5. Verify booking auto-released
    print("[5/6] Verifying release outcome...")
    _, final_bookings = rest_call(f"bookings?id=eq.{booking_id}")
    final_booking = final_bookings[0]
    print(f"      Final Booking Status: {final_booking['status'].upper()}")
    assert final_booking["status"] == "released", f"Expected released, got {final_booking['status']}"

    # 6. Verify audit event and door LED returns to GREEN
    print("[6/6] Verifying audit events and Door LED...")
    _, events = rest_call(f"events?booking_id=eq.{booking_id}&kind=eq.released")
    assert len(events) > 0, "Expected release audit event"
    print(f"      Audit Event logged: {events[0]['reason']}")

    final_led = get_door_led()
    print(f"      Door LED: {final_led.get('led').upper()} (Expected: GREEN)")
    assert final_led.get("led") == "green", f"Expected green LED, got {final_led.get('led')}"

    print("\n======================================================================")
    print("SUCCESS: End-to-End Ghost Booking Release Journey Passed!")
    print("======================================================================")

if __name__ == "__main__":
    run_e2e_scenario()
