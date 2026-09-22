#!/bin/bash
# SwiftPM の依存解決だけを先に済ませる。
#
# SwiftLint を build tool plugin として全ターゲットに付けているため、xcodebuild は archive でも
# build-for-testing でも、まず依存をネットワークから取りに行く。ランナー側の一時的な不調
# （github.com の名前が引けないなど）でここが落ちるとビルドごと巻き添えになるので、
# 独立したステップとして切り出したうえで、間隔を空けて繰り返す。
set -euo pipefail

project="${PROJECT:?PROJECT が設定されていない}"
scheme="${SCHEME:?SCHEME が設定されていない}"

options=()
if [ -n "${DERIVED_DATA:-}" ]; then
  # ビルド本体と同じ DerivedData に解決しないと、結局もう一度ネットワークを見に行くことになる
  options+=(-derivedDataPath "$DERIVED_DATA")
fi

attempts=3
for attempt in $(seq 1 "$attempts"); do
  # 空配列の展開は set -u だと未定義扱いになるので、空のときは何も渡さない書き方にする
  if xcodebuild -resolvePackageDependencies \
    -project "$project" \
    -scheme "$scheme" \
    ${options[@]+"${options[@]}"}; then
    exit 0
  fi

  if [ "$attempt" -lt "$attempts" ]; then
    wait_seconds=$((attempt * 30))
    echo "依存解決に失敗した（${attempt}/${attempts} 回目）。${wait_seconds} 秒待って繰り返す。"
    sleep "$wait_seconds"
  fi
done

echo "::error::SwiftPM の依存解決に ${attempts} 回とも失敗した。"
exit 1
