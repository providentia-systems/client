.PHONY: analyze build-web contracts format get test verify

get:
	flutter pub get --enforce-lockfile

contracts:
	node tool/generate_api_client.mjs
	node tool/generate_api_client.mjs --check

format:
	dart format lib test contracts/generated/providentia_api_client/lib

analyze:
	flutter analyze --fatal-infos --fatal-warnings

test:
	flutter test

verify:
	tool/check.sh

build-web:
	flutter build web --release
