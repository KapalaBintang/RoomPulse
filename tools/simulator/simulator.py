#!/usr/bin/env python3
"""
RoomPulse Sensor Telemetry Simulator (STACK 2026 Semifinal Prototype)
Provides simulated mmWave radar readings for local testing without physical hardware.
"""

import sys
import time
import json
import random
import argparse
import urllib.request
import urllib.error

DEFAULT_BASE_URL = "http://127.0.0.1:54321/functions/v1"
DEFAULT_DEVICE_ID = "device-room-101"
DEFAULT_SIM_KEY = "sim_key_default_dev"

def post_telemetry(base_url, device_id, sim_key, payload):
    url = f"{base_url}/device-telemetry"
    req_body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=req_body,
        headers={
            "Content-Type": "application/json",
            "x-device-key": sim_key,
        },
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = resp.read().decode("utf-8")
            return resp.status, json.loads(data)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, {"error": body}
    except Exception as e:
        return 500, {"error": str(e)}

def get_device_state(base_url, device_id):
    url = f"{base_url}/device-state?device_id={device_id}"
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = resp.read().decode("utf-8")
            return resp.status, json.loads(data)
    except Exception as e:
        return 500, {"error": str(e)}

def make_payload(device_id, presence=False, moving=False, stationary=False,
                 moving_energy=0, static_energy=0, distance_cm=0, label=None):
    return {
        "device_id": device_id,
        "presence": presence,
        "moving": moving,
        "stationary": stationary,
        "moving_energy": moving_energy,
        "static_energy": static_energy,
        "distance_cm": distance_cm,
        "source": "simulator",
        "label": label
    }

def run_empty(args):
    print(f"[*] Starting SIMULATOR [empty] mode for {args.device_id}...")
    while True:
        payload = make_payload(args.device_id, presence=False, label="empty_room")
        status, res = post_telemetry(args.base_url, args.device_id, args.key, payload)
        _, state = get_device_state(args.base_url, args.device_id)
        led = state.get("led", "unknown")
        print(f"[{time.strftime('%H:%M:%S')}] Empty sent -> HTTP {status} | LED: {led.upper()}")
        if args.once:
            break
        time.sleep(args.interval)

def run_present(args):
    print(f"[*] Starting SIMULATOR [present] mode for {args.device_id}...")
    while True:
        payload = make_payload(
            args.device_id,
            presence=True,
            moving=random.choice([True, False]),
            stationary=True,
            moving_energy=random.randint(20, 60),
            static_energy=random.randint(60, 95),
            distance_cm=random.randint(110, 160),
            label="seated_studying"
        )
        status, res = post_telemetry(args.base_url, args.device_id, args.key, payload)
        _, state = get_device_state(args.base_url, args.device_id)
        led = state.get("led", "unknown")
        print(f"[{time.strftime('%H:%M:%S')}] Presence sent (Energy: {payload['static_energy']}) -> HTTP {status} | LED: {led.upper()}")
        if args.once:
            break
        time.sleep(args.interval)

def run_present_then_leave(args):
    duration = args.duration or 15
    print(f"[*] Starting SIMULATOR [present-then-leave] for {args.device_id} ({duration}s occupied, then empty)...")
    start = time.time()
    while time.time() - start < duration:
        payload = make_payload(args.device_id, presence=True, moving=True, stationary=True,
                               moving_energy=30, static_energy=80, distance_cm=140, label="present_phase")
        post_telemetry(args.base_url, args.device_id, args.key, payload)
        print(f"[{time.strftime('%H:%M:%S')}] Phase: Present ({int(duration - (time.time() - start))}s left)")
        time.sleep(args.interval)

    print("[*] Transitioning to EMPTY phase...")
    while True:
        payload = make_payload(args.device_id, presence=False, label="vacated_phase")
        post_telemetry(args.base_url, args.device_id, args.key, payload)
        _, state = get_device_state(args.base_url, args.device_id)
        print(f"[{time.strftime('%H:%M:%S')}] Phase: Empty | LED: {state.get('led', 'unknown').upper()}")
        if args.once:
            break
        time.sleep(args.interval)

def run_flaky(args):
    print(f"[*] Starting SIMULATOR [flaky] mode for {args.device_id}...")
    while True:
        presence = random.random() > 0.5
        payload = make_payload(
            args.device_id,
            presence=presence,
            moving=presence,
            stationary=presence,
            moving_energy=random.randint(10, 50) if presence else 0,
            static_energy=random.randint(30, 80) if presence else 0,
            distance_cm=130 if presence else 0,
            label="flaky_intermittent"
        )
        status, _ = post_telemetry(args.base_url, args.device_id, args.key, payload)
        print(f"[{time.strftime('%H:%M:%S')}] Flaky packet (Presence: {presence}) -> HTTP {status}")
        time.sleep(args.interval)

def run_offline(args):
    print(f"[*] Simulator [offline] triggered: stopping telemetry transmission for {args.device_id}.")
    print("[*] Device will be detected as OFFLINE once offline_threshold_seconds expires.")

def main():
    parser = argparse.ArgumentParser(description="RoomPulse mmWave Sensor Simulator CLI")
    parser.add_argument("script", choices=["empty", "present", "present-then-leave", "flaky", "offline"],
                        help="Telemetry scenario script")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="Supabase edge functions base URL")
    parser.add_argument("--device-id", default=DEFAULT_DEVICE_ID, help="Target device ID")
    parser.add_argument("--key", default=DEFAULT_SIM_KEY, help="API key / Simulator key")
    parser.add_argument("--interval", type=int, default=3, help="Polling interval in seconds")
    parser.add_argument("--duration", type=int, default=15, help="Duration for present phase in present-then-leave")
    parser.add_argument("--once", action="store_true", help="Send a single reading and exit")

    args = parser.parse_args()

    if args.script == "empty":
        run_empty(args)
    elif args.script == "present":
        run_present(args)
    elif args.script == "present-then-leave":
        run_present_then_leave(args)
    elif args.script == "flaky":
        run_flaky(args)
    elif args.script == "offline":
        run_offline(args)

if __name__ == "__main__":
    main()
