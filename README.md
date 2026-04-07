# 💹 ForexSniper Pro AI Bot

Professional Auto Trading EA for MT5 + Exness by Faisal Khattak

## Setup Instructions

### Step 1 — Enable GitHub Actions
- Go to **Actions** tab
- Click **"I understand my workflows, enable them"**
- Click **ForexSniper AI Trainer** → **Run workflow**
- Wait 10 minutes — AI trains on real market data

### Step 2 — Enable GitHub Pages
- Go to **Settings** → **Pages**
- Source: **Deploy from branch**
- Branch: **main** → folder: **/docs**
- Save

### Step 3 — Configure MT5 EA
- Open MT5 → Load **ForexSniper Pro EA.mq5**
- Set `GitHubUser` = your GitHub username
- Set `GitHubRepo` = forexsniper-bot
- Bot downloads AI model automatically

## Files
- `ForexSniper Pro EA.mq5` — MT5 Expert Advisor
- `Python/train_model.py` — AI trainer script
- `.github/workflows/train_ai.yml` — Daily training workflow
- `docs/` — GitHub Pages (serves AI model)

## Contact
📲 t.me/ForexSniper7997

© 2025 Faisal Khattak
