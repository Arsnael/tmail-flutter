#!/bin/bash
# CI integration test script.
# The Android emulator is managed by reactivecircus/android-emulator-runner
# and is already running when this script executes.
#
# Usage:
#   ./scripts/patrol-integration-test-with-docker.sh
set -e

echo "Installing patrol CLI..."
dart pub global activate patrol_cli 4.3.1

cd backend-docker

openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out jwt_privatekey 2>/dev/null
openssl rsa -in jwt_privatekey -pubout -out jwt_publickey 2>/dev/null

# 10.0.2.2 is the QEMU alias for the host machine inside the Android emulator.
sed -i.bak "s|url.prefix=.*|url.prefix=http://10.0.2.2|" jmap.properties
sed -i.bak "s|websocket.url.prefix=.*|websocket.url.prefix=ws://10.0.2.2|" jmap.properties

echo "Starting tmail-backend..."
docker compose up -d tmail-backend --quiet-pull
# Cap the wait so a stuck backend fails fast instead of consuming the runner timeout.
deadline=$(( SECONDS + 180 ))
until docker compose logs tmail-backend 2>/dev/null | grep -qi "JAMES server started"; do
    if (( SECONDS >= deadline )); then
        echo "tmail-backend did not start within 180s; recent logs:"
        docker compose logs --tail=200 tmail-backend
        exit 1
    fi
    echo "Waiting for tmail-backend..."
    sleep 2
done

export BOB="bob"
export ALICE="alice"
export DOMAIN="example.com"

docker exec tmail-backend /root/conf/integration_test/provisioning.sh >/dev/null 2>&1

cd ..

export BASIC_AUTH_URL="http://10.0.2.2"
export RESET_PORT=9999

RESET_SERVER_LOG="/tmp/backend-reset-server.log"
echo "Starting backend reset server on port $RESET_PORT (logs: $RESET_SERVER_LOG)..."
RESET_PORT="$RESET_PORT" python3 scripts/backend-reset-server.py > "$RESET_SERVER_LOG" 2>&1 &
RESET_SERVER_PID=$!

cleanup() {
    echo "Cleaning up..."
    kill "$RESET_SERVER_PID" 2>/dev/null || true
    cd backend-docker
    docker compose down --remove-orphans 2>/dev/null
    cd ..
}
trap cleanup EXIT

echo "Running Patrol tests..."
echo "google cli auth"
gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
gcloud config set project "$FIREBASE_PROJECT_ID"

echo "Flutter build apk"
flutter build apk --config-only --quiet
echo "Patrol build apk"
patrol build android -v \
    --tags=android \
    --dart-define=USERNAME="$BOB" \
    --dart-define=PASSWORD="$BOB" \
    --dart-define=ADDITIONAL_MAIL_RECIPIENT="$ALICE@$DOMAIN" \
    --dart-define=BASIC_AUTH_EMAIL="$BOB@$DOMAIN" \
    --dart-define=BASIC_AUTH_URL="$BASIC_AUTH_URL" \
    --dart-define=RESET_SERVER_URL="http://10.0.2.2:$RESET_PORT"

echo "start firebase tests"
gcloud firebase test android run \
    --type instrumentation \
    --app build/app/outputs/apk/debug/app-debug.apk \
    --test build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk \
    --device model=MediumPhone.arm,version=34 \
    --timeout 60m \
    --use-orchestrator \
    --environment-variables clearPackageData=true