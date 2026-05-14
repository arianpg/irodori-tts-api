# IrodoriTTS OpenAI API互換ラッパー

## 概要
[Irodori-TTS](https://github.com/Aratako/Irodori-TTS)の[OpenAI Text-to-Speech API](https://developers.openai.com/api/docs/guides/text-to-speech)互換ラッパーです。
以下の3モデルに対応しています。

| モデルID | HuggingFace | 特徴 |
|---|---|---|
| `irodori-tts-500m-v3` | [Aratako/Irodori-TTS-500M-v3](https://huggingface.co/Aratako/Irodori-TTS-500M-v3) | 最新版。リファレンス音声なしでも動作（no-refモード）。デュレーション予測器搭載 |
| `irodori-tts-500m-v2-voicedesign` | [Aratako/Irodori-TTS-500M-v2-VoiceDesign](https://huggingface.co/Aratako/Irodori-TTS-500M-v2-VoiceDesign) | `instructions`（自然言語キャプション）で声質・感情を制御するVoice Designモデル |
| `irodori-tts-500m-v2` | [Aratako/Irodori-TTS-500M-v2](https://huggingface.co/Aratako/Irodori-TTS-500M-v2) | リファレンス音声による話者クローンモデル |

モデルはリクエストで指定されたものを動的にロードし、一定時間（デフォルト300秒）再リクエストがなければ自動でアンロードします。
Dockerでの利用を想定しています。

Docker Hub: [arianpg/irodori-tts-api](https://hub.docker.com/r/arianpg/irodori-tts-api)

## 動作要件

- **GPU**: NVIDIA GPU（CUDA 対応）
- **VRAM**: 4GB 以上推奨（モデルは動的にロード・アンロードされます）
- **CUDA**: 12.x
- **Docker**: Docker Engine + Docker Compose Plugin（または Docker Desktop）
- **OS**: Linux（Windows/macOS の場合は Docker Desktop 経由で利用可能）

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/arianpg/irodori-tts-api.git
cd irodori-tts-api
```

### 2. 環境変数を設定

```bash
cp .env.example .env
```

`.env` を編集し、必要に応じて設定値を変更します。

### 3. 起動

```bash
docker compose up
```

Docker Hub からイメージを自動でpullして起動します。

初回起動時にモデルが自動でダウンロードされます（数 GB）。以降はキャッシュが利用されます。

モデルのロードはリクエスト時に行われます。起動直後の最初のリクエストは完了まで数分かかる場合があります。

> **ローカルビルドする場合:**
> ```bash
> docker compose -f compose.yml -f compose.dev.yml up --build
> ```

### 4. リファレンス音声の準備（`irodori-tts-500m-v2` / `irodori-tts-500m-v3` で話者クローンを使用する場合）

話者クローン用のリファレンス音声を `voices/` ディレクトリに配置するか、API でアップロードします。

```bash
# API でアップロードする場合
curl http://localhost:8880/v1/audio/voice_contents \
  -F "file=@my_voice.wav"
```

> `irodori-tts-500m-v3` はリファレンス音声なしでも動作します（no-refモード）。リファレンス音声を登録しない場合、`voice` に任意の文字列を指定するとno-refモードで合成されます。

---

## 倫理的制限に関する注意

本APIが利用を想定しているIrodori-TTS各モデルには、MITライセンスに加えて **倫理的制限（Ethical Restrictions）** が定められています。本APIを利用する際はモデルの利用規約を確認し、これに従ってください。

- [Irodori-TTS-500M-v3 — Ethical Restrictions](https://huggingface.co/Aratako/Irodori-TTS-500M-v3#ethical-restrictions)
- [Irodori-TTS-500M-v2-VoiceDesign — Ethical Restrictions](https://huggingface.co/Aratako/Irodori-TTS-500M-v2-VoiceDesign#ethical-restrictions)
- [Irodori-TTS-500M-v2 — Ethical Restrictions](https://huggingface.co/Aratako/Irodori-TTS-500M-v2#ethical-restrictions)

---

## 開発

本プロジェクトは [Claude Code](https://claude.ai/code)（Anthropic）の AI 支援のもとで作成されました。

---

## ライセンス

本プロジェクトは [MIT License](LICENSE) のもとで公開されています。

依存するコンポーネントのライセンス：

| コンポーネント | ライセンス |
|---|---|
| [Irodori-TTS](https://github.com/Aratako/Irodori-TTS) | MIT（+ 上記 Ethical Restrictions） |
| [Irodori-TTS-500M-v3](https://huggingface.co/Aratako/Irodori-TTS-500M-v3) | MIT（+ 上記 Ethical Restrictions） |
| [Irodori-TTS-500M-v2](https://huggingface.co/Aratako/Irodori-TTS-500M-v2) | MIT（+ 上記 Ethical Restrictions） |
| [Irodori-TTS-500M-v2-VoiceDesign](https://huggingface.co/Aratako/Irodori-TTS-500M-v2-VoiceDesign) | MIT（+ 上記 Ethical Restrictions） |

---

## API仕様

ベースURL: `http://localhost:8880`

---

### GET /v1/models

利用可能なモデル一覧を返します。

**レスポンス**

```json
{
  "object": "list",
  "data": [
    {
      "id": "irodori-tts-500m-v3",
      "object": "model",
      "created": 1700000000,
      "owned_by": "irodori"
    },
    {
      "id": "irodori-tts-500m-v2-voicedesign",
      "object": "model",
      "created": 1700000000,
      "owned_by": "irodori"
    },
    {
      "id": "irodori-tts-500m-v2",
      "object": "model",
      "created": 1700000000,
      "owned_by": "irodori"
    }
  ]
}
```

---

### POST /v1/audio/speech

テキストを音声に変換します。OpenAI TTS API (`POST /v1/audio/speech`) と互換性があります。

`model` フィールドによって動作が異なります。

**リクエストボディ** (`Content-Type: application/json`)

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `model` | string | ✓ | 使用するモデルID |
| `input` | string | ✓ | 読み上げるテキスト |
| `voice` | string | ✓ | `irodori-tts-500m-v2` では `/v1/audio/voice_contents` で登録したリファレンス音声のID（必須）。`irodori-tts-500m-v3` では登録済みIDを指定すると話者クローン、未登録のIDを指定するとno-refモードで動作。`irodori-tts-500m-v2-voicedesign` では OpenAI API 互換のために受け付けるが使用されない |
| `instructions` | string | | `irodori-tts-500m-v2-voicedesign` でのみ有効。声のスタイルを自然言語で指定するキャプション（Voice Design）。話者の性別・年齢・感情・話し方などを自由テキストで記述する |
| `response_format` | string | | 出力フォーマット。`mp3` / `wav` / `opus` / `flac` / `aac`。デフォルト: `mp3` |
| `speed` | number | | 再生速度（0.25〜4.0）。デフォルト: `1.0` |

> **`instructions` の記述例**（`irodori-tts-500m-v2-voicedesign` 使用時）
> ```
> 低い声の女性が、苛立ちを隠せない様子で焦って話している。クリアな音質、少し感情的なトーンで、呆れたような様子。
> ```
> `input` テキスト中に絵文字を挿入することで、文節ごとの感情をさらに細かく制御することもできます。
> ```
> これ😠、昨日からずっと机の上に置きっぱなしになってますよ😒
> ```

**ストリーミング（Chunked Transfer Encoding）**

入力テキストを句読点（。！？）で文単位に分割し、文ごとに生成・送信します。クライアントは最初の文が生成され次第、再生を開始できます。

| フォーマット | ストリーミング方式 |
|---|---|
| `mp3` / `aac` | チャンク単位でストリーミング（各文を都度送信） |
| `wav` | ストリーミングWAVヘッダー + チャンクごとに raw PCM 送信 |
| `opus` / `flac` | バッファリング（コンテナ仕様の都合により全文生成後に送信） |

**curl 利用例**

```bash
# irodori-tts-500m-v3: no-refモード（リファレンス音声なし）
curl http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "irodori-tts-500m-v3",
    "input": "こんにちは、今日もいい天気ですね。",
    "voice": "alloy"
  }' \
  --output output.mp3

# irodori-tts-500m-v3: リファレンス音声で話者をクローン
curl http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "irodori-tts-500m-v3",
    "input": "こんにちは、今日もいい天気ですね。",
    "voice": "my_voice"
  }' \
  --output output.mp3

# irodori-tts-500m-v2-voicedesign: instructions で声質を指定
curl http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "irodori-tts-500m-v2-voicedesign",
    "input": "こんにちは、今日もいい天気ですね。",
    "voice": "alloy",
    "instructions": "明るく元気な若い女性が、はきはきとした口調で話している。"
  }' \
  --output output.mp3

# irodori-tts-500m-v2: リファレンス音声で話者をクローン
curl http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "irodori-tts-500m-v2",
    "input": "こんにちは、今日もいい天気ですね。",
    "voice": "my_voice"
  }' \
  --output output.mp3
```

**レスポンス**

音声データをバイナリストリームで返します。

| ヘッダー | 値 |
|---|---|
| `Content-Type` | `audio/mpeg`（mp3時）/ `audio/wav`（wav時）など |

---

### /v1/audio/voice_contents — リファレンス音声の管理

`irodori-tts-500m-v2` および `irodori-tts-500m-v3` で `voice` パラメータに指定するリファレンス音声（話者クローン用）を管理するエンドポイント群です。

アップロードされたファイルはサーバーの `/voices` ディレクトリに保存されます。

**対応フォーマット:** `wav` / `mp3` / `flac` / `ogg`

---

#### GET /v1/audio/voice_contents

登録済みリファレンス音声の一覧を返します。

**レスポンス**

```json
{
  "object": "list",
  "data": [
    {
      "id": "my_voice",
      "object": "voice_content",
      "filename": "my_voice.wav",
      "created_at": 1700000000
    }
  ]
}
```

---

#### POST /v1/audio/voice_contents

リファレンス音声をアップロードして登録します。

**リクエスト** (`Content-Type: multipart/form-data`)

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `file` | file | ✓ | アップロードする音声ファイル（`wav` / `mp3` / `flac` / `ogg`） |
| `voice_id` | string | | ボイスIDとして使用する名前。省略時はファイル名（拡張子なし）を使用。既存 ID と重複する場合はエラー |

**レスポンス** `201 Created`

```json
{
  "id": "my_voice",
  "object": "voice_content",
  "filename": "my_voice.wav",
  "created_at": 1700000000
}
```

**curl 利用例**

```bash
curl http://localhost:8880/v1/audio/voice_contents \
  -F "file=@my_voice.wav"

# voice_id を明示的に指定する場合
curl http://localhost:8880/v1/audio/voice_contents \
  -F "file=@recording.wav" \
  -F "voice_id=my_voice"
```

---

#### GET /v1/audio/voice_contents/{voice_id}

指定したリファレンス音声のメタデータを返します。

**レスポンス**

```json
{
  "id": "my_voice",
  "object": "voice_content",
  "filename": "my_voice.wav",
  "created_at": 1700000000
}
```

---

#### PUT /v1/audio/voice_contents/{voice_id}

指定した ID のリファレンス音声ファイルを差し替えます。

**リクエスト** (`Content-Type: multipart/form-data`)

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `file` | file | ✓ | 新しい音声ファイル（`wav` / `mp3` / `flac` / `ogg`） |

**レスポンス**

```json
{
  "id": "my_voice",
  "object": "voice_content",
  "filename": "my_voice.mp3",
  "created_at": 1700001000
}
```

**curl 利用例**

```bash
curl -X PUT http://localhost:8880/v1/audio/voice_contents/my_voice \
  -F "file=@new_recording.mp3"
```

---

#### DELETE /v1/audio/voice_contents/{voice_id}

指定したリファレンス音声を削除します。

**レスポンス** `200 OK`

```json
{
  "id": "my_voice",
  "object": "voice_content",
  "deleted": true
}
```

**curl 利用例**

```bash
curl -X DELETE http://localhost:8880/v1/audio/voice_contents/my_voice
```

---

### エラーレスポンス

エラー時は OpenAI API と同形式で返します。

```json
{
  "error": {
    "message": "Voice 'unknown_voice' not found.",
    "type": "invalid_request_error",
    "param": "voice",
    "code": null
  }
}
```

| HTTPステータス | 説明 |
|---|---|
| `400` | リクエストパラメータが不正 |
| `404` | 指定したボイスが見つからない |
| `500` | 音声生成中に内部エラーが発生 |
| `503` | モデルのロードが `MODEL_LOAD_TIMEOUT` 秒を超えた |

---

### 環境変数設定

#### モデル

| 環境変数 | デフォルト | 説明 |
|---|---|---|
| `HF_CHECKPOINT_V3` | `Aratako/Irodori-TTS-500M-v3` | v3 モデルの HuggingFace リポジトリ ID |
| `HF_CHECKPOINT_VOICEDESIGN` | `Aratako/Irodori-TTS-500M-v2-VoiceDesign` | VoiceDesign モデルの HuggingFace リポジトリ ID |
| `HF_CHECKPOINT_BASE` | `Aratako/Irodori-TTS-500M-v2` | ベース（話者クローン）モデルの HuggingFace リポジトリ ID |

#### デバイス・精度

| 環境変数 | デフォルト | 説明 |
|---|---|---|
| `MODEL_DEVICE` | `cuda` | 言語モデルの実行デバイス（`cuda` / `cpu`） |
| `CODEC_DEVICE` | `cuda` | コーデック（DACVAE）の実行デバイス（`cuda` / `cpu`） |
| `MODEL_PRECISION` | `bf16` | 言語モデルの精度（`bf16` / `fp16` / `fp32`） |
| `CODEC_PRECISION` | `bf16` | コーデックの精度（`bf16` / `fp16` / `fp32`） |

#### 音声生成

| 環境変数 | デフォルト | 説明 |
|---|---|---|
| `NUM_STEPS` | `40` | Diffusionステップ数。多いほど高品質だが推論が遅くなる |
| `CFG_SCALE_TEXT` | `3.0` | テキスト誘導スケール（両モデル共通） |
| `CFG_SCALE_CAPTION` | `4.0` | キャプション誘導スケール（`irodori-tts-500m-v2-voicedesign` のみ有効） |
| `CFG_SCALE_SPEAKER` | `5.0` | スピーカー誘導スケール（`irodori-tts-500m-v2` / `irodori-tts-500m-v3` で有効） |
| `SECONDS_BUFFER_MULTIPLIER` | `1.5` | 文字数から推定した生成秒数に掛けるバッファ倍率。`irodori-tts-500m-v2` / `irodori-tts-500m-v2-voicedesign` のみ適用。`irodori-tts-500m-v3` はデュレーション予測器が自動推定するため使用されない |

#### モデルキャッシュ

| 環境変数 | デフォルト | 説明 |
|---|---|---|
| `MODEL_TTL` | `300` | モデルを VRAM に保持し続ける時間（秒）。最後のリクエストからこの時間が経過すると自動アンロード |
| `MODEL_LOAD_TIMEOUT` | `300` | モデルロード完了を待機する最大時間（秒）。超過した後続リクエストは `503` を返す |
