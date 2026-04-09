"""
ForexSniper Pro — LSTM AI Trainer v2.1
========================================
Architecture: LSTM + Attention (same class as AI Forex Robot $2,299)
Features: 32 features including Supply/Demand zones
Fix: Rate limit handling + delays between downloads
Author: Faisal Khattak | t.me/ForexSniper7997
"""

import os, json, time, random
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

print("="*60)
print("  ForexSniper Pro LSTM AI Trainer v2.1")
print("  32 Features | Supply/Demand | Rate-limit safe")
print("="*60)

# STEP 1: DOWNLOAD WITH RATE LIMIT PROTECTION
print("\n[1/6] Downloading real market data (rate-limit safe)...")
import yfinance as yf

PAIRS = {
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "AUDUSD": "AUDUSD=X",
    "XAUUSD": "GC=F",
    "BTCUSD": "BTC-USD",
}

all_data = {}
for name, ticker in PAIRS.items():
    for attempt in range(3):  # 3 retry attempts
        try:
            time.sleep(random.uniform(3, 6))  # random delay to avoid rate limit
            df = yf.download(ticker, period="1y", interval="1h",
                           progress=False, auto_adjust=True)
            if len(df) > 300:
                # Flatten multi-level columns if present
                if isinstance(df.columns, pd.MultiIndex):
                    df.columns = df.columns.get_level_values(0)
                all_data[name] = df
                print(f"  OK {name}: {len(df)} bars")
                break
            else:
                print(f"  RETRY {name}: only {len(df)} bars (attempt {attempt+1})")
                time.sleep(10)
        except Exception as e:
            print(f"  RETRY {name} attempt {attempt+1}: {e}")
            time.sleep(15)
    else:
        print(f"  SKIP {name}: failed after 3 attempts")

if not all_data:
    print("ERROR: No data downloaded.")
    exit(1)

print(f"  Downloaded {len(all_data)} pairs")

# STEP 2: 32-FEATURE ENGINEERING
print(f"\n[2/6] Engineering 32 features...")

def rsi(s, p=14):
    d = s.diff()
    g = d.clip(lower=0).rolling(p).mean()
    l = (-d.clip(upper=0)).rolling(p).mean()
    return 100 - (100 / (1 + g / (l + 1e-10)))

def atr_fn(h, l, c, p=14):
    tr = pd.concat([h-l, (h-c.shift()).abs(), (l-c.shift()).abs()], axis=1).max(axis=1)
    return tr.rolling(p).mean()

def supply_demand(h, l, c, lb=20):
    n = len(c)
    ds = pd.Series(0.0, index=c.index)
    ss = pd.Series(0.0, index=c.index)
    for i in range(lb, n):
        wh = h.iloc[i-lb:i]
        wl = l.iloc[i-lb:i]
        wc = c.iloc[i-lb:i]
        ll = wl.min()
        li = wl.idxmin()
        ca = wc[li:].max()
        if ll > 0:
            ds.iloc[i] = (ca - ll) / ll
        lh = wh.max()
        hi2 = wh.idxmax()
        cb = wc[hi2:].min()
        if lh > 0:
            ss.iloc[i] = (lh - cb) / lh
    return ds, ss

def build_features(df):
    # Ensure correct column names
    df.columns = [str(col).strip() for col in df.columns]
    c = df['Close'].squeeze()
    h = df['High'].squeeze()
    l = df['Low'].squeeze()
    o = df['Open'].squeeze()

    ft = pd.DataFrame(index=c.index)

    # RSI (3)
    ft['rsi14']  = rsi(c, 14) / 100
    ft['rsi7']   = rsi(c, 7)  / 100
    ft['rsi21']  = rsi(c, 21) / 100

    # EMA (6)
    e8   = c.ewm(span=8,   adjust=False).mean()
    e21  = c.ewm(span=21,  adjust=False).mean()
    e50  = c.ewm(span=50,  adjust=False).mean()
    e200 = c.ewm(span=200, adjust=False).mean()
    ft['e8d']    = (c - e8)   / (c + 1e-10)
    ft['e21d']   = (c - e21)  / (c + 1e-10)
    ft['e50d']   = (c - e50)  / (c + 1e-10)
    ft['e200d']  = (c - e200) / (c + 1e-10)
    ft['ebull']  = ((e8>e21) & (e21>e50) & (e50>e200)).astype(float)
    ft['ebear']  = ((e8<e21) & (e21<e50) & (e50<e200)).astype(float)

    # MACD (4)
    ml  = c.ewm(span=12,adjust=False).mean() - c.ewm(span=26,adjust=False).mean()
    sl2 = ml.ewm(span=9, adjust=False).mean()
    hist= ml - sl2
    ft['mhist'] = hist / (c.abs() + 1e-10) * 1000
    ft['msig']  = (ml > sl2).astype(float)
    ft['mcup']  = ((ml > sl2) & (ml.shift() <= sl2.shift())).astype(float)
    ft['mcdn']  = ((ml < sl2) & (ml.shift() >= sl2.shift())).astype(float)

    # Bollinger (3)
    bm  = c.rolling(20).mean()
    bs  = c.rolling(20).std()
    bu  = bm + 2*bs
    bl2 = bm - 2*bs
    ft['bbpos'] = ((c - bl2) / (bu - bl2 + 1e-10)).clip(0, 1)
    ft['bbwid'] = ((bu - bl2) / (bm + 1e-10)).clip(0, 0.2) / 0.2
    ft['bbsqz'] = (ft['bbwid'] < ft['bbwid'].rolling(20).mean()).astype(float)

    # ATR (3)
    a14 = atr_fn(h, l, c, 14)
    a50 = atr_fn(h, l, c, 50)
    ft['aratr'] = (a14 / (a50 + 1e-10)).clip(0, 5) / 5
    ft['apct']  = (a14 / (c + 1e-10)).clip(0, 0.05) / 0.05
    ft['aup']   = (a14 > a50).astype(float)

    # Price Action (5)
    body = (c - o).abs()
    rng  = (h - l).clip(lower=1e-10)
    uw   = h - pd.concat([c, o], axis=1).max(axis=1)
    lw   = pd.concat([c, o], axis=1).min(axis=1) - l
    ft['brat']  = (body / rng).clip(0, 1)
    ft['bull2'] = (c > o).astype(float)
    ft['pinb']  = ((lw/rng > 0.6) & (body/rng < 0.3)).astype(float)
    ft['pins']  = ((uw/rng > 0.6) & (body/rng < 0.3)).astype(float)
    ft['engulf']= ((c>o) & (c>o.shift()) & (o<c.shift()) & (body>body.shift())).astype(float)

    # Momentum (4)
    ft['m5']  = c.pct_change(5).clip(-0.1, 0.1) / 0.1
    ft['m20'] = c.pct_change(20).clip(-0.2, 0.2) / 0.2
    ft['m60'] = c.pct_change(60).clip(-0.3, 0.3) / 0.3
    ft['roc'] = (c / c.shift(10) - 1).clip(-0.1, 0.1) / 0.1

    # Supply/Demand zones (2)
    ds, ss = supply_demand(h, l, c)
    ft['demand'] = ds.clip(0, 0.05) / 0.05
    ft['supply'] = ss.clip(0, 0.05) / 0.05

    # Stochastic (2)
    ll14 = l.rolling(14).min()
    hh14 = h.rolling(14).max()
    sk   = ((c - ll14) / (hh14 - ll14 + 1e-10) * 100)
    ft['sk'] = sk.clip(0, 100) / 100
    ft['sd'] = sk.rolling(3).mean().clip(0, 100) / 100

    return ft.dropna()

def build_labels(df, fidx, horizon=3, thresh=0.0002):
    df.columns = [str(col).strip() for col in df.columns]
    c  = df['Close'].squeeze().reindex(fidx)
    r  = c.shift(-horizon) / c - 1
    lb = np.where(r > thresh, 2, np.where(r < -thresh, 0, 1))
    return lb[:-horizon]

X_all, y_all = [], []
feat_names   = []
for name, df in all_data.items():
    try:
        ft = build_features(df)
        lb = build_labels(df, ft.index)
        n  = len(lb)
        X_all.append(ft.values[:n])
        y_all.append(lb)
        if not feat_names:
            feat_names = list(ft.columns)
        print(f"  {name}: {n} samples | BUY:{(lb==2).sum()} HOLD:{(lb==1).sum()} SELL:{(lb==0).sum()}")
    except Exception as e:
        print(f"  SKIP {name}: {e}")

X_flat = np.vstack(X_all).astype(np.float32)
y_flat = np.concatenate(y_all).astype(np.int32)
N_FEAT = X_flat.shape[1]
SEQ_LEN = 20
print(f"\n  Total: {len(X_flat)} samples | Features: {N_FEAT}")
print(f"  Feature names: {feat_names}")

# STEP 3: SCALE + SEQUENCES
print(f"\n[3/6] Scaling and building LSTM sequences (lookback={SEQ_LEN})...")
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, classification_report
from sklearn.utils.class_weight import compute_class_weight

scaler   = StandardScaler()
Xs       = scaler.fit_transform(X_flat).astype(np.float32)

os.makedirs("model", exist_ok=True)
with open("model/scaler_params.json", "w") as f:
    json.dump({
        "mean":         scaler.mean_.tolist(),
        "scale":        scaler.scale_.tolist(),
        "n_features":   int(N_FEAT),
        "sequence_len": SEQ_LEN,
        "version":      "2.1-LSTM-32feat",
        "feature_names": feat_names
    }, f, indent=2)

def make_seq(X, y, sl):
    Xo, yo = [], []
    for i in range(sl, len(X)):
        Xo.append(X[i-sl:i])
        yo.append(y[i])
    return np.array(Xo, np.float32), np.array(yo, np.int32)

X_seq, y_seq = make_seq(Xs, y_flat, SEQ_LEN)
print(f"  Sequence shape: {X_seq.shape}")

sp   = int(len(X_seq) * 0.8)
Xtr, Xte = X_seq[:sp], X_seq[sp:]
ytr, yte  = y_seq[:sp], y_seq[sp:]

# STEP 4: LSTM MODEL
print("\n[4/6] Building LSTM + Attention model...")
import tensorflow as tf

cw_v = compute_class_weight('balanced', classes=np.unique(ytr), y=ytr)
cw   = {i: cw_v[i] for i in range(len(cw_v))}

inp  = tf.keras.Input(shape=(SEQ_LEN, N_FEAT))
x    = tf.keras.layers.LSTM(128, return_sequences=True, dropout=0.2, recurrent_dropout=0.1)(inp)
x    = tf.keras.layers.LSTM(64,  return_sequences=True, dropout=0.2, recurrent_dropout=0.1)(x)
at   = tf.keras.layers.Dense(1, activation='tanh')(x)
at   = tf.keras.layers.Flatten()(at)
at   = tf.keras.layers.Activation('softmax')(at)
at   = tf.keras.layers.RepeatVector(64)(at)
at   = tf.keras.layers.Permute([2, 1])(at)
xm   = tf.keras.layers.Multiply()([x, at])
xm   = tf.keras.layers.Lambda(lambda z: tf.reduce_sum(z, axis=1))(xm)
x    = tf.keras.layers.Dense(64, activation='relu')(xm)
x    = tf.keras.layers.BatchNormalization()(x)
x    = tf.keras.layers.Dropout(0.3)(x)
x    = tf.keras.layers.Dense(32, activation='relu')(x)
out  = tf.keras.layers.Dense(3,  activation='softmax')(x)

model = tf.keras.Model(inp, out)
model.compile(optimizer=tf.keras.optimizers.Adam(0.001),
              loss='sparse_categorical_crossentropy',
              metrics=['accuracy'])
print(f"  Parameters: {model.count_params():,}")

# STEP 5: TRAIN
print("\n[5/6] Training LSTM model...")
model.fit(Xtr, ytr,
          validation_data=(Xte, yte),
          epochs=60, batch_size=256,
          class_weight=cw, verbose=1,
          callbacks=[
              tf.keras.callbacks.EarlyStopping(patience=10, restore_best_weights=True,
                                               monitor='val_accuracy'),
              tf.keras.callbacks.ReduceLROnPlateau(patience=5, factor=0.5, min_lr=1e-5)
          ])

yp  = model.predict(Xte, verbose=0).argmax(axis=1)
acc = accuracy_score(yte, yp)
print(f"\n  Test Accuracy: {acc*100:.2f}%")
print(classification_report(yte, yp, target_names=["SELL","HOLD","BUY"]))

# STEP 6: EXPORT ONNX
print("\n[6/6] Exporting ONNX...")
import tf2onnx, onnx

sig = [tf.TensorSpec([None, SEQ_LEN, N_FEAT], tf.float32, name="input")]
tf2onnx.convert.from_keras(model, input_signature=sig, opset=12,
                            output_path="model/ForexSniper_AI.onnx")
onnx.checker.check_model(onnx.load("model/ForexSniper_AI.onnx"))
sz = os.path.getsize("model/ForexSniper_AI.onnx") / 1024

with open("model/metadata.json", "w") as f:
    json.dump({
        "trained_at":    pd.Timestamp.now().isoformat(),
        "accuracy":      float(acc),
        "architecture":  "LSTM-128+LSTM-64+Attention+Dense-64-32-3",
        "sequence_len":  SEQ_LEN,
        "n_features":    int(N_FEAT),
        "n_samples":     int(len(X_seq)),
        "pairs_used":    list(all_data.keys()),
        "model_size_kb": float(sz),
        "version":       "2.1-LSTM-32feat",
        "scaler_mean":   scaler.mean_.tolist(),
        "scaler_scale":  scaler.scale_.tolist(),
    }, f, indent=2)

print(f"\n{'='*60}")
print(f"  LSTM MODEL v2.1 COMPLETE!")
print(f"  Accuracy:     {acc*100:.2f}%")
print(f"  Architecture: LSTM-128 + LSTM-64 + Attention")
print(f"  Features:     {N_FEAT} (incl. Supply/Demand zones)")
print(f"  Sequence:     {SEQ_LEN} candle lookback")
print(f"  Size:         {sz:.1f} KB")
print(f"{'='*60}")
