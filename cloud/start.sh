#!/bin/bash
# Entrypoint Mây trên cloud (Railway/VPS). State ở /data/.openclaw (gắn Volume vào /data).
# Seed config+persona+skills lần đầu; ghi .env từ Variables; điền owner nếu cần; chạy gateway.
set -e
H=/data/.openclaw
mkdir -p "$H"

# 1) Seed openclaw.json + workspace lần đầu (KHÔNG đè để giữ trí nhớ Mây học trên cloud)
if [ ! -f "$H/openclaw.json" ]; then
  cp /app/seed/openclaw.json "$H/openclaw.json"
  # Sinh gateway token (chỉ lần đầu) — bảo vệ control plane; không commit vào repo
  GTOK="$(node -e 'console.log(require("crypto").randomBytes(24).toString("hex"))')"
  node -e 'const f=process.argv[1],t=process.argv[2];const c=require(f);c.gateway=c.gateway||{mode:"local"};c.gateway.auth={mode:"token",token:t};require("fs").writeFileSync(f,JSON.stringify(c,null,2))' "$H/openclaw.json" "$GTOK"
  echo "[start] đã seed openclaw.json + sinh gateway token"
fi
# Refresh "code" (skills + persona tĩnh) MỖI lần deploy để git push tới được bot;
# GIỮ NGUYÊN USER.md (trí nhớ Mây học về người dùng) + memory.
mkdir -p "$H/workspace"
rm -rf "$H/workspace/skills"
cp -r /app/seed/workspace/skills "$H/workspace/skills"
for f in SOUL.md AGENTS.md IDENTITY.md; do
  [ -f "/app/seed/workspace/$f" ] && cp "/app/seed/workspace/$f" "$H/workspace/$f"
done
# USER.md: chỉ tạo nếu chưa có (đừng đè trí nhớ đã học)
[ -f "$H/workspace/USER.md" ] || cp /app/seed/workspace/USER.md "$H/workspace/USER.md"
echo "[start] refresh skills + persona (giữ USER.md)"

# 2) Owner: LUÔN đồng bộ từ OWNER_TELEGRAM_ID mỗi lần chạy.
#    (Quan trọng: openclaw.json nằm trên Volume nên KHÔNG seed lại; phải GHI ĐÈ owner ở đây,
#     nếu không thì đổi Variable + redeploy sẽ không có tác dụng — owner kẹt giá trị cũ.)
if [ -n "${OWNER_TELEGRAM_ID}" ]; then
  node -e 'const fs=require("fs"),f=process.argv[1],id=process.argv[2];const c=JSON.parse(fs.readFileSync(f,"utf8"));c.channels=c.channels||{};c.channels.telegram=c.channels.telegram||{};c.channels.telegram.dmPolicy="allowlist";c.channels.telegram.allowFrom=[String(id)];c.commands=c.commands||{};c.commands.ownerAllowFrom=["telegram:"+id];fs.writeFileSync(f,JSON.stringify(c,null,2))' "$H/openclaw.json" "${OWNER_TELEGRAM_ID}"
  echo "[start] owner đồng bộ từ Variable: ${OWNER_TELEGRAM_ID}"
fi

# 3) .env (state-dir, trusted) — ghi mỗi lần chạy → đổi Variables trên Railway là cập nhật
{
  echo "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}"
  echo "TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}"
  echo "JINA_API_KEY=${JINA_API_KEY}"
  echo "APIFY_TOKEN=${APIFY_TOKEN}"
  echo "COACHIO_API_KEY=${COACHIO_API_KEY}"
  echo "GROQ_API_KEY=${GROQ_API_KEY}"
} > "$H/.env"

# 4) Provision lần đầu: plugin deepseek + đăng ký key vào AUTH STORE.
#    DeepSeek V4 là reasoning model → cần plugin @openclaw/deepseek-provider để xử lý
#    đúng định dạng thinking; và key phải nằm trong auth store (paste-api-key), chỉ .env KHÔNG đủ.
if [ ! -f "$H/.coachio-provisioned" ]; then
  echo "[start] cài plugin deepseek…"
  openclaw plugins install @openclaw/deepseek-provider 2>&1 | tail -2 || true
  if [ -n "${DEEPSEEK_API_KEY}" ]; then
    printf '%s\n' "${DEEPSEEK_API_KEY}" | openclaw models auth paste-api-key --provider deepseek 2>&1 | tail -1 || true
    echo "[start] đã đăng ký auth deepseek vào auth store"
  fi
  touch "$H/.coachio-provisioned"
fi

echo "[start] khởi động gateway…"
exec openclaw gateway run
