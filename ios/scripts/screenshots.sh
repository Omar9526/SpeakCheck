#!/bin/zsh
# Скриншоты экранов из симулятора: scripts/screenshots.sh <SIM_UDID> [screens...]
SIM=$1; shift
OUT=${0:A:h}/../../docs/screenshots
mkdir -p $OUT
xcrun simctl install $SIM ${0:A:h}/../build/Build/Products/Debug-iphonesimulator/SpeakCheck.app || exit 1
for s in "$@"; do
  xcrun simctl terminate $SIM kg.speakcheck.app 2>/dev/null
  case $s in
    onboarding) xcrun simctl launch $SIM kg.speakcheck.app -AppleLanguages "(ru)" >/dev/null ;;
    home) xcrun simctl launch $SIM kg.speakcheck.app -demoData >/dev/null ;;
    *) xcrun simctl launch $SIM kg.speakcheck.app -demoData -screen $s >/dev/null ;;
  esac
  /bin/sleep 3
  xcrun simctl io $SIM screenshot $OUT/$s.png >/dev/null 2>&1 && echo "saved $s"
done
