.PHONY: dev build-web build-firmware start-supabase stop-supabase test-sql test-e2e sim

dev:
	npm --prefix web run dev

build-web:
	npm --prefix web run build

build-firmware:
	python -m platformio run -d firmware

start-supabase:
	supabase start

stop-supabase:
	supabase stop

db-reset:
	supabase db reset

test-sql:
	supabase db query -f supabase/tests/rule_engine_tests.sql

test-e2e:
	python tools/simulator/test_no_show_scenario.py
