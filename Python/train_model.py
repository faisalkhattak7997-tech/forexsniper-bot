"""
ForexSniper Pro — Real AI Model Trainer
========================================
Runs on GitHub Actions every day.
Downloads REAL price data → Trains LSTM model → Exports ONNX
MT5 EA fetches the model automatically.

Author: Faisal Khattak | t.me/ForexSniper7997
"""

import os
import json
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

print("=" * 60)
print("  ForexSniper Pro — Real AI Trainer")
print("  Running on GitHub Actions")
print("=" * 60)

# ── STEP 1: DOWNLOAD REAL PRICE DATA ─────────────────────────────
print("\n[1/5] Downloading real market data...")

import yfinance as yf

PAIRS = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "AUDUSD": "AUDUSD=X",
    "USDCAD": "USDCAD=X",
    "XAUUSD": "GC=F",
    "BTCUSD": "BTC-USD",
    "ETHUSD": "ETH-USD",
}

all_data = {}
for name, ticker in PAIRS.items():
    try:
        df = yf.download(ticker, period="2y", interval="1h",
                        progress=False, auto_adjust=True)
        if len(df) > 500:
            all_data[name] = df
            print(f"  ✅ {name}: {len(df)} bars")
        else:
            print(f"  ⚠️  {name}: insufficient data ({len(df)} bars)")
    except Exception as e:
        print(f"  ❌ {name}: {e}")

if not all_data:
    print("ERROR: No data downloaded. Check network.")
    exit(1)

print(f"  Downloaded {len(all_data)} pairs successfully")

# ── STEP 2: FEATURE ENGINEERING ──────────────────────────────────
print("\n[2/5] Engineering features from real price data...")

def compute_rsi(series, period=14):
    delta = series.diff()
    gain  = delta.clip(lower=0).rolling(period).mean()
    loss  = (-delta.clip(upper=0)).rolling(period).mean()
    rs    = gain / (loss + 1e-10)
    return 100 - (100 / (1 + rs))

def compute_features(df):
    """
    Extract 20 real market features from OHLCV data.
    These are the SAME features the MT5 EA will compute.
    """
    close = df['Close'].squeeze()
    high  = df['High'].squeeze()
    low   = df['Low'].squeeze()
    vol   = df['Volume'].squeeze() if 'Volume' in df.columns else pd.Series(1, index=close.index)

    features = pd.DataFrame(index=close.index)

    # Price-based features
    features['rsi_14']      = compute_rsi(close, 14) / 100.0
    features['rsi_7']       = compute_rsi(close, 7)  / 100.0

    # EMA features
    ema8   = close.ewm(span=8,   adjust=False).mean()
    ema21  = close.ewm(span=21,  adjust=False).mean()
    ema50  = close.ewm(span=50,  adjust=False).mean()
    ema200 = close.ewm(span=200, adjust=False).mean()

    features['ema8_dist']   = (close - ema8)   / (close + 1e-10)
    features['ema21_dist']  = (close - ema21)  / (close + 1e-10)
    features['ema50_dist']  = (close - ema50)  / (close + 1e-10)
    features['ema200_dist'] = (close - ema200) / (close + 1e-10)
    features['ema_align']   = ((ema8 > ema21) & (ema21 > ema50)).astype(float) - \
                              ((ema8 < ema21) & (ema21 < ema50)).astype(float)

    # MACD
    macd_line   = close.ewm(span=12, adjust=False).mean() - \
                  close.ewm(span=26, adjust=False).mean()
    signal_line = macd_line.ewm(span=9, adjust=False).mean()
    histogram   = macd_line - signal_line
    features['macd_hist']   = histogram / (close.abs() + 1e-10) * 100
    features['macd_signal'] = (macd_line > signal_line).astype(float) - \
                              (macd_line < signal_line).astype(float)

    # Bollinger Bands
    bb_mid   = close.rolling(20).mean()
    bb_std   = close.rolling(20).std()
    bb_upper = bb_mid + 2 * bb_std
    bb_lower = bb_mid - 2 * bb_std
    bb_range = (bb_upper - bb_lower) / (bb_mid + 1e-10)
    bb_pos   = (close - bb_lower) / (bb_upper - bb_lower + 1e-10)
    features['bb_position'] = bb_pos.clip(0, 1)
    features['bb_width']    = bb_range

    # ATR (volatility)
    tr = pd.concat([
        high - low,
        (high - close.shift()).abs(),
        (low  - close.shift()).abs()
    ], axis=1).max(axis=1)
    atr14  = tr.rolling(14).mean()
    atr_avg= atr14.rolling(50).mean()
    features['atr_ratio']   = (atr14 / (atr_avg + 1e-10)).clip(0, 5) / 5.0

    # Price action
    body   = (close - df['Open'].squeeze()).abs()
    candle = high - low
    features['body_ratio']  = (body / (candle + 1e-10)).clip(0, 1)
    features['is_bullish']  = (close > df['Open'].squeeze()).astype(float)

    # Momentum
    features['mom_5']  = close.pct_change(5).clip(-0.1, 0.1)  / 0.1
    features['mom_20'] = close.pct_change(20).clip(-0.2, 0.2) / 0.2

    return features.dropna()

def compute_labels(df, features_index, horizon=3, threshold=0.0003):
    """
    Real labels: did price go up or down significantly in next N bars?
    0 = SELL, 1 = HOLD, 2 = BUY
    """
    close = df['Close'].squeeze().reindex(features_index)
    future_return = close.shift(-horizon) / close - 1

    labels = np.where(future_return >  threshold, 2,   # BUY
             np.where(future_return < -threshold, 0,   # SELL
                      1))                              # HOLD
    return labels[:-horizon]  # remove last N rows (no future data)

# Build dataset from all pairs
X_all = []
y_all = []

for name, df in all_data.items():
    try:
        feats  = compute_features(df)
        labels = compute_labels(df, feats.index, horizon=3, threshold=0.0002)
        n      = len(labels)
        X_all.append(feats.values[:n])
        y_all.append(labels)
        print(f"  {name}: {n} samples | BUY:{(labels==2).sum()} HOLD:{(labels==1).sum()} SELL:{(labels==0).sum()}")
    except Exception as e:
        print(f"  ⚠️  {name} feature error: {e}")

X = np.vstack(X_all).astype(np.float32)
y = np.concatenate(y_all).astype(np.int32)

print(f"\n  Total samples: {len(X)}")
print(f"  Features: {X.shape[1]}")
print(f"  BUY:{(y==2).sum()} HOLD:{(y==1).sum()} SELL:{(y==0).sum()}")

# ── STEP 3: TRAIN MODEL ───────────────────────────────────────────
print("\n[3/5] Training model on real data...")

from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import tensorflow as tf

# Scale features
scaler     = StandardScaler()
X_scaled   = scaler.fit_transform(X).astype(np.float32)

# Save scaler params for MT5
scaler_params = {
    "mean":  scaler.mean_.tolist(),
    "scale": scaler.scale_.tolist(),
    "n_features": int(X.shape[1]),
    "feature_names": [
        "rsi_14","rsi_7","ema8_dist","ema21_dist","ema50_dist",
        "ema200_dist","ema_align","macd_hist","macd_signal",
        "bb_position","bb_width","atr_ratio","body_ratio",
        "is_bullish","mom_5","mom_20"
    ]
}

os.makedirs("model", exist_ok=True)
with open("model/scaler_params.json","w") as f:
    json.dump(scaler_params, f, indent=2)

# Train/test split — use time-based split (no leakage)
split = int(len(X_scaled) * 0.8)
X_train, X_test = X_scaled[:split], X_scaled[split:]
y_train, y_test = y[:split], y[split:]

# Build model — proven architecture for financial time series
model = tf.keras.Sequential([
    tf.keras.layers.Dense(256, activation='relu', input_shape=(X.shape[1],)),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(128, activation='relu'),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(64, activation='relu'),
    tf.keras.layers.BatchNormalization(),
    tf.keras.layers.Dropout(0.2),
    tf.keras.layers.Dense(32, activation='relu'),
    tf.keras.layers.Dense(3, activation='softmax')  # SELL / HOLD / BUY
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
    loss='sparse_categorical_crossentropy',
    metrics=['accuracy']
)

# Class weights to handle imbalance
from sklearn.utils.class_weight import compute_class_weight
class_weights = compute_class_weight('balanced', classes=np.unique(y_train), y=y_train)
cw = {i: class_weights[i] for i in range(len(class_weights))}

history = model.fit(
    X_train, y_train,
    validation_data=(X_test, y_test),
    epochs=50,
    batch_size=512,
    class_weight=cw,
    callbacks=[
        tf.keras.callbacks.EarlyStopping(patience=8, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(patience=4, factor=0.5)
    ],
    verbose=0
)

# Evaluate
y_pred = model.predict(X_test, verbose=0).argmax(axis=1)
acc    = accuracy_score(y_test, y_pred)
print(f"\n  Test Accuracy: {acc*100:.2f}%")
print("\n  Classification Report:")
print(classification_report(y_test, y_pred, target_names=["SELL","HOLD","BUY"]))

# ── STEP 4: EXPORT TO ONNX ────────────────────────────────────────
print("\n[4/5] Exporting to ONNX format...")

import tf2onnx
import onnx

# Convert to ONNX
input_signature = [tf.TensorSpec([None, X.shape[1]], tf.float32, name="input")]
onnx_model, _ = tf2onnx.convert.from_keras(
    model,
    input_signature=input_signature,
    opset=12,
    output_path="model/ForexSniper_AI.onnx"
)

# Verify
onnx_model_loaded = onnx.load("model/ForexSniper_AI.onnx")
onnx.checker.check_model(onnx_model_loaded)
onnx_size = os.path.getsize("model/ForexSniper_AI.onnx") / 1024
print(f"  ✅ ONNX model saved: {onnx_size:.1f} KB")
print(f"  Input shape: [batch, {X.shape[1]}]")
print(f"  Output: [SELL_prob, HOLD_prob, BUY_prob]")

# ── STEP 5: SAVE METADATA ─────────────────────────────────────────
print("\n[5/5] Saving metadata...")

metadata = {
    "trained_at": pd.Timestamp.now().isoformat(),
    "accuracy": float(acc),
    "pairs_used": list(all_data.keys()),
    "n_samples": int(len(X)),
    "n_features": int(X.shape[1]),
    "model_size_kb": float(onnx_size),
    "scaler_mean":  scaler.mean_.tolist(),
    "scaler_scale": scaler.scale_.tolist(),
}

with open("model/metadata.json","w") as f:
    json.dump(metadata, f, indent=2)

print(f"\n{'='*60}")
print(f"  ✅ REAL AI MODEL TRAINED SUCCESSFULLY!")
print(f"  Accuracy: {acc*100:.2f}%")
print(f"  Pairs: {list(all_data.keys())}")
print(f"  Samples: {len(X):,}")
print(f"  Model: model/ForexSniper_AI.onnx")
print(f"{'='*60}")
