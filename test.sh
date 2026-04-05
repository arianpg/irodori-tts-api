#!/usr/bin/env bash
# test.sh — IrodoriTTS API テストスクリプト
#
# 使用方法:
#   ./test.sh                         # 全テスト実行
#   ./test.sh voicedesign             # VoiceDesign モデルのみ
#   ./test.sh base                    # ベースモデル（話者クローン）のみ
#   ./test.sh voice_contents          # voice_contents CRUD のみ
#   ./test.sh models                  # /v1/models のみ
#
# 前提:
#   - サーバーが http://localhost:8880 で起動していること
#   - ベースモデルのテストにはリファレンス音声が必要
#     (REFERENCE_AUDIO 変数にパスを指定、デフォルト: ./test_reference.wav)

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8880}"
OUTPUT_DIR="${OUTPUT_DIR:-./test_outputs}"
REFERENCE_AUDIO="${REFERENCE_AUDIO:-./test_reference.wav}"
PASS=0
FAIL=0

mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# HTTP ステータスコードを検証しつつ curl を実行
# 使用法: check_status <期待ステータス> <実際のステータス> <テスト名>
check_status() {
  local expected="$1" actual="$2" name="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$name (HTTP $actual)"
  else
    fail "$name (expected HTTP $expected, got HTTP $actual)"
  fi
}

# レスポンスボディに文字列が含まれるか検証
check_contains() {
  local body="$1" needle="$2" name="$3"
  if echo "$body" | grep -q "$needle"; then
    pass "$name (contains '$needle')"
  else
    fail "$name (expected '$needle' in: $body)"
  fi
}

# ファイルが存在し、サイズが0より大きいか検証
check_audio_file() {
  local path="$1" name="$2"
  if [[ -s "$path" ]]; then
    local size
    size=$(wc -c < "$path")
    pass "$name (${size} bytes)"
  else
    fail "$name (file missing or empty: $path)"
  fi
}

# ---------------------------------------------------------------------------
# テスト: GET /v1/models
# ---------------------------------------------------------------------------
test_models() {
  section "GET /v1/models"

  local status body
  body=$(curl -s -o /tmp/t_models.json -w "%{http_code}" "${BASE_URL}/v1/models")
  status="$body"
  body=$(cat /tmp/t_models.json)

  check_status 200 "$status" "GET /v1/models"
  check_contains "$body" "irodori-tts-500m-v2-voicedesign" "models: voicedesign が含まれる"
  check_contains "$body" "irodori-tts-500m-v2\"" "models: base が含まれる"
}

# ---------------------------------------------------------------------------
# テスト: POST /v1/audio/speech — VoiceDesign モデル
#
# 聴き比べ用ファイル構成 (test_outputs/voicedesign/):
#   01_no_instructions.mp3        — instructions なし（モデルデフォルト）
#   02_bright.mp3                 — 明るい女性
#   03_calm_male.mp3              — 落ち着いた男性
#   04_angry.mp3                  — 苛立ちを隠せない
#   05_emoji_neutral.mp3          — 絵文字による感情制御（通常）
#   06_emoji_angry.mp3            — 絵文字による感情制御（怒り）
#   07_speed_0.75.mp3             — 同テキスト speed=0.75
#   08_speed_1.00.mp3             — 同テキスト speed=1.00（基準）
#   09_speed_1.50.mp3             — 同テキスト speed=1.50
# ---------------------------------------------------------------------------
test_voicedesign() {
  section "POST /v1/audio/speech (irodori-tts-500m-v2-voicedesign)"

  local vd_dir="${OUTPUT_DIR}/voicedesign"
  mkdir -p "$vd_dir"

  local status

  # 聴き比べ用共通テキスト
  local TEXT_COMMON="こんにちは。今日もいい天気ですね。どうぞよろしくお願いします。"
  local TEXT_EMOJI="これ😠、昨日からずっと机の上に置きっぱなしになってますよ😒。片付けてください😤。"
  local TEXT_SPEED="本日はお越しいただきありがとうございます。どうぞよろしくお願いいたします。"

  # --- 01: instructions なし（モデルデフォルト）---
  local out="${vd_dir}/01_no_instructions.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_COMMON}\",\"voice\":\"alloy\"}")
  check_status 200 "$status" "voicedesign: 01 instructions なし"
  check_audio_file "$out" "voicedesign: 01 ファイル生成"

  # --- 02: 明るい女性 ---
  out="${vd_dir}/02_bright.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_COMMON}\",\"voice\":\"alloy\",\"instructions\":\"明るく元気な若い女性が、はきはきとした口調で話している。\"}")
  check_status 200 "$status" "voicedesign: 02 明るい女性"
  check_audio_file "$out" "voicedesign: 02 ファイル生成"

  # --- 03: 落ち着いた男性 ---
  out="${vd_dir}/03_calm_male.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_COMMON}\",\"voice\":\"alloy\",\"instructions\":\"落ち着いた中年男性が、丁寧でゆっくりとした口調で話している。低めの声で、穏やかなトーン。\"}")
  check_status 200 "$status" "voicedesign: 03 落ち着いた男性"
  check_audio_file "$out" "voicedesign: 03 ファイル生成"

  # --- 04: 苛立ちを隠せない ---
  out="${vd_dir}/04_angry.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_COMMON}\",\"voice\":\"alloy\",\"instructions\":\"低い声の女性が、苛立ちを隠せない様子で焦って話している。クリアな音質、少し感情的なトーンで、呆れたような様子。\"}")
  check_status 200 "$status" "voicedesign: 04 苛立ちを隠せない"
  check_audio_file "$out" "voicedesign: 04 ファイル生成"

  # --- 05: 絵文字による感情制御（通常テキスト、絵文字なし比較用）---
  out="${vd_dir}/05_emoji_neutral.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d '{"model":"irodori-tts-500m-v2-voicedesign","input":"これ、昨日からずっと机の上に置きっぱなしになってますよ。片付けてください。","voice":"alloy"}')
  check_status 200 "$status" "voicedesign: 05 絵文字なし（比較用）"
  check_audio_file "$out" "voicedesign: 05 ファイル生成"

  # --- 06: 絵文字による感情制御（怒り）---
  out="${vd_dir}/06_emoji_angry.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_EMOJI}\",\"voice\":\"alloy\"}")
  check_status 200 "$status" "voicedesign: 06 絵文字あり（怒り）"
  check_audio_file "$out" "voicedesign: 06 ファイル生成"

  # --- 07〜09: 同テキストで speed 聴き比べ ---
  for speed_label in "07_speed_0.75:0.75" "08_speed_1.00:1.0" "09_speed_1.50:1.5"; do
    local label="${speed_label%%:*}"
    local speed="${speed_label##*:}"
    out="${vd_dir}/${label}.mp3"
    status=$(curl -s -o "$out" -w "%{http_code}" \
      -X POST "${BASE_URL}/v1/audio/speech" \
      -H "Content-Type: application/json" \
      --max-time 600 \
      -d "{\"model\":\"irodori-tts-500m-v2-voicedesign\",\"input\":\"${TEXT_SPEED}\",\"voice\":\"alloy\",\"speed\":${speed}}")
    check_status 200 "$status" "voicedesign: ${label} speed=${speed}"
    check_audio_file "$out" "voicedesign: ${label} ファイル生成"
  done

  echo "  → 出力: ${vd_dir}/"

  # --- 異常系 ---
  local body
  status=$(curl -s -o /tmp/t_vd_empty.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{"model":"irodori-tts-500m-v2-voicedesign","input":"","voice":"alloy"}')
  body=$(cat /tmp/t_vd_empty.json)
  check_status 400 "$status" "voicedesign: input 空 → 400"
  check_contains "$body" "input" "voicedesign: input 空 エラー param"

  status=$(curl -s -o /tmp/t_vd_fmt.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{"model":"irodori-tts-500m-v2-voicedesign","input":"test","voice":"alloy","response_format":"xyz"}')
  check_status 400 "$status" "voicedesign: 不正 format → 400"

  status=$(curl -s -o /tmp/t_vd_speed.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{"model":"irodori-tts-500m-v2-voicedesign","input":"test","voice":"alloy","speed":10}')
  check_status 400 "$status" "voicedesign: speed 範囲外 → 400"

  status=$(curl -s -o /tmp/t_vd_model.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{"model":"unknown-model","input":"test","voice":"alloy"}')
  check_status 400 "$status" "voicedesign: 不明モデル → 400"
}

# ---------------------------------------------------------------------------
# テスト: /v1/audio/voice_contents CRUD
# ---------------------------------------------------------------------------
test_voice_contents() {
  section "/v1/audio/voice_contents (CRUD)"

  local test_voice_id="test_voice_$$"
  local tmp_wav="/tmp/${test_voice_id}.wav"

  # テスト用ダミーWAVを生成 (1秒, 16kHz, モノラル, 無音)
  python3 - <<EOF
import struct, wave
with wave.open("$tmp_wav", "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(16000)
    f.writeframes(b"\x00\x00" * 16000)
EOF

  # --- POST: アップロード ---
  local status body
  status=$(curl -s -o /tmp/t_vc_post.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/voice_contents" \
    -F "file=@${tmp_wav}" \
    -F "voice_id=${test_voice_id}")
  body=$(cat /tmp/t_vc_post.json)
  check_status 201 "$status" "voice_contents: POST アップロード"
  check_contains "$body" "\"id\":\"${test_voice_id}\"" "voice_contents: POST レスポンス id"

  # --- POST: 重複エラー ---
  status=$(curl -s -o /tmp/t_vc_dup.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/voice_contents" \
    -F "file=@${tmp_wav}" \
    -F "voice_id=${test_voice_id}")
  check_status 400 "$status" "voice_contents: POST 重複 → 400"

  # --- GET 一覧: アップロードしたIDが含まれる ---
  status=$(curl -s -o /tmp/t_vc_list.json -w "%{http_code}" \
    "${BASE_URL}/v1/audio/voice_contents")
  body=$(cat /tmp/t_vc_list.json)
  check_status 200 "$status" "voice_contents: GET 一覧"
  check_contains "$body" "$test_voice_id" "voice_contents: GET 一覧にアップロード済みIDが含まれる"

  # --- GET 個別: 存在するID ---
  status=$(curl -s -o /tmp/t_vc_get.json -w "%{http_code}" \
    "${BASE_URL}/v1/audio/voice_contents/${test_voice_id}")
  body=$(cat /tmp/t_vc_get.json)
  check_status 200 "$status" "voice_contents: GET 個別"
  check_contains "$body" "\"id\":\"${test_voice_id}\"" "voice_contents: GET 個別 id"

  # --- GET 個別: 存在しないID ---
  status=$(curl -s -o /tmp/t_vc_404.json -w "%{http_code}" \
    "${BASE_URL}/v1/audio/voice_contents/nonexistent_voice_$$")
  check_status 404 "$status" "voice_contents: GET 存在しないID → 404"

  # --- PUT: 差し替え ---
  local tmp_wav2="/tmp/${test_voice_id}_new.wav"
  cp "$tmp_wav" "$tmp_wav2"
  status=$(curl -s -o /tmp/t_vc_put.json -w "%{http_code}" \
    -X PUT "${BASE_URL}/v1/audio/voice_contents/${test_voice_id}" \
    -F "file=@${tmp_wav2}")
  check_status 200 "$status" "voice_contents: PUT 差し替え"

  # --- PUT: 存在しないID ---
  status=$(curl -s -o /tmp/t_vc_put404.json -w "%{http_code}" \
    -X PUT "${BASE_URL}/v1/audio/voice_contents/nonexistent_voice_$$" \
    -F "file=@${tmp_wav}")
  check_status 404 "$status" "voice_contents: PUT 存在しないID → 404"

  # --- DELETE ---
  status=$(curl -s -o /tmp/t_vc_del.json -w "%{http_code}" \
    -X DELETE "${BASE_URL}/v1/audio/voice_contents/${test_voice_id}")
  body=$(cat /tmp/t_vc_del.json)
  check_status 200 "$status" "voice_contents: DELETE"
  check_contains "$body" "\"deleted\":true" "voice_contents: DELETE レスポンス"

  # --- DELETE: 削除済みID ---
  status=$(curl -s -o /tmp/t_vc_del404.json -w "%{http_code}" \
    -X DELETE "${BASE_URL}/v1/audio/voice_contents/${test_voice_id}")
  check_status 404 "$status" "voice_contents: DELETE 削除済みID → 404"

  rm -f "$tmp_wav" "$tmp_wav2"
}

# ---------------------------------------------------------------------------
# テスト: POST /v1/audio/speech — ベースモデル（話者クローン）
#
# 聴き比べ用ファイル構成 (test_outputs/base/):
#   01_clone_text1.mp3            — リファレンス音声に近いテキスト
#   02_clone_text2.mp3            — 別テキスト（同話者）
#   03_clone_speed_0.75.mp3       — speed=0.75
#   04_clone_speed_1.00.mp3       — speed=1.00（基準）
#   05_clone_speed_1.50.mp3       — speed=1.50
#
# 前提: REFERENCE_AUDIO に実際の話者音声を指定してください
#   例: REFERENCE_AUDIO=./my_voice.wav ./test.sh base
# ---------------------------------------------------------------------------
test_base() {
  section "POST /v1/audio/speech (irodori-tts-500m-v2)"

  if [[ ! -f "$REFERENCE_AUDIO" ]]; then
    echo -e "${YELLOW}[INFO]${NC} REFERENCE_AUDIO が見つかりません。voicedesign モデルで仮音声を生成してリファレンスとして使用します。"
    local generated_ref="${OUTPUT_DIR}/base/generated_reference.mp3"
    mkdir -p "${OUTPUT_DIR}/base"
    local gen_status
    gen_status=$(curl -s -o "$generated_ref" -w "%{http_code}" \
      -X POST "${BASE_URL}/v1/audio/speech" \
      -H "Content-Type: application/json" \
      --max-time 600 \
      -d '{"model":"irodori-tts-500m-v2-voicedesign","input":"こんにちは。本日はよろしくお願いします。少しお時間をいただいてもよろしいでしょうか。","voice":"alloy","instructions":"落ち着いた若い女性が、丁寧な口調でゆっくりと話している。"}')
    if [[ "$gen_status" != "200" ]] || [[ ! -s "$generated_ref" ]]; then
      fail "base: 仮リファレンス音声の生成に失敗しました (HTTP ${gen_status})"
      return
    fi
    pass "base: 仮リファレンス音声を生成しました (${generated_ref})"
    REFERENCE_AUDIO="$generated_ref"
  fi

  local base_dir="${OUTPUT_DIR}/base"
  mkdir -p "$base_dir"

  # リファレンス音声をアップロード
  local ref_voice_id="test_ref_$$"
  local status
  status=$(curl -s -o /tmp/t_base_upload.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/voice_contents" \
    -F "file=@${REFERENCE_AUDIO}" \
    -F "voice_id=${ref_voice_id}")
  check_status 201 "$status" "base: リファレンス音声アップロード"

  local TEXT1="こんにちは。今日もいい天気ですね。どうぞよろしくお願いします。"
  local TEXT2="本日はお越しいただきありがとうございます。またいつでもお気軽にご連絡ください。"
  local TEXT_SPEED="本日はお越しいただきありがとうございます。どうぞよろしくお願いいたします。"

  # --- 01: テキスト1 ---
  local out="${base_dir}/01_clone_text1.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2\",\"input\":\"${TEXT1}\",\"voice\":\"${ref_voice_id}\"}")
  check_status 200 "$status" "base: 01 テキスト1"
  check_audio_file "$out" "base: 01 ファイル生成"

  # --- 02: テキスト2 ---
  out="${base_dir}/02_clone_text2.mp3"
  status=$(curl -s -o "$out" -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    --max-time 600 \
    -d "{\"model\":\"irodori-tts-500m-v2\",\"input\":\"${TEXT2}\",\"voice\":\"${ref_voice_id}\"}")
  check_status 200 "$status" "base: 02 テキスト2"
  check_audio_file "$out" "base: 02 ファイル生成"

  # --- 03〜05: 同テキストで speed 聴き比べ ---
  for speed_label in "03_speed_0.75:0.75" "04_speed_1.00:1.0" "05_speed_1.50:1.5"; do
    local label="${speed_label%%:*}"
    local speed="${speed_label##*:}"
    out="${base_dir}/${label}.mp3"
    status=$(curl -s -o "$out" -w "%{http_code}" \
      -X POST "${BASE_URL}/v1/audio/speech" \
      -H "Content-Type: application/json" \
      --max-time 600 \
      -d "{\"model\":\"irodori-tts-500m-v2\",\"input\":\"${TEXT_SPEED}\",\"voice\":\"${ref_voice_id}\",\"speed\":${speed}}")
    check_status 200 "$status" "base: ${label} speed=${speed}"
    check_audio_file "$out" "base: ${label} ファイル生成"
  done

  echo "  → 出力: ${base_dir}/"

  # --- 異常系: 存在しない voice ---
  status=$(curl -s -o /tmp/t_base_novoice.json -w "%{http_code}" \
    -X POST "${BASE_URL}/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{"model":"irodori-tts-500m-v2","input":"test","voice":"nonexistent_voice"}')
  check_status 404 "$status" "base: 存在しない voice → 404"

  # クリーンアップ
  curl -s -o /dev/null -X DELETE "${BASE_URL}/v1/audio/voice_contents/${ref_voice_id}"
}

# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------
TARGET="${1:-all}"

case "$TARGET" in
  models)        test_models ;;
  voicedesign)   test_models; test_voicedesign ;;
  base)          test_models; test_base ;;
  voice_contents) test_voice_contents ;;
  all)           test_models; test_voicedesign; test_voice_contents; test_base ;;
  *)
    echo "Usage: $0 [all|models|voicedesign|base|voice_contents]"
    exit 1
    ;;
esac

echo ""
echo "----------------------------------------"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "Output files: ${OUTPUT_DIR}/"
echo "----------------------------------------"

[[ $FAIL -eq 0 ]]
