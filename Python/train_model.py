"""
ForexSniper Pro — LSTM AI Trainer v2.0
========================================
Architecture: LSTM + Attention (same class as AI Forex Robot $2,299)
Features: 32 features including Supply/Demand zones
Training: Real market data — 8 pairs, 2 years history
Auto-runs daily on GitHub Actions

Author: Faisal Khattak | t.me/ForexSniper7997
"""

import os, json
import numpy as np
import pandas as pd
import warnings
warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'

print("="*60)
print("  ForexSniper Pro — LSTM AI Trainer v2.0")
print("  Architecture: LSTM + Attention Network")
print("="*60)

# STEP 1: DOWNLOAD REAL PRICE DATA
print("\n[1/6] Downloading real market data...")
import yfinance as yf

PAIRS = {
    "EURUSD":"EURUSD=X","GBPUSD":"GBPUSD=X","USDJPY":"USDJPY=X",
    "AUDUSD":"AUDUSD=X","USDCAD":"USDCAD=X","XAUUSD":"GC=F",
    "BTCUSD":"BTC-USD","ETHUSD":"ETH-USD",
}

all_data = {}
for name, ticker in PAIRS.items():
    try:
        df = yf.download(ticker, period="2y", interval="1h", progress=False, auto_adjust=True)
        if len(df) > 500:
            all_data[name] = df
            print(f"  OK {name}: {len(df)} bars")
        else:
            print(f"  SKIP {name}: {len(df)} bars")
    except Exception as e:
        print(f"  FAIL {name}: {e}")

if not all_data:
    print("ERROR: No data downloaded.")
    exit(1)

# STEP 2: FEATURE ENGINEERING (32 features)
print(f"\n[2/6] Engineering features from {len(all_data)} pairs...")

def rsi(s, p=14):
    d=s.diff(); g=d.clip(lower=0).rolling(p).mean(); l=(-d.clip(upper=0)).rolling(p).mean()
    return 100-(100/(1+g/(l+1e-10)))

def atr_fn(h,l,c,p=14):
    tr=pd.concat([h-l,(h-c.shift()).abs(),(l-c.shift()).abs()],axis=1).max(axis=1)
    return tr.rolling(p).mean()

def supply_demand(h,l,c,lb=20):
    n=len(c); ds=pd.Series(0.0,index=c.index); ss=pd.Series(0.0,index=c.index)
    for i in range(lb,n):
        wh=h.iloc[i-lb:i]; wl=l.iloc[i-lb:i]; wc=c.iloc[i-lb:i]
        ll=wl.min(); li=wl.idxmin(); ca=wc[li:].max()
        if ll>0: ds.iloc[i]=(ca-ll)/ll
        lh=wh.max(); hi=wh.idxmax(); cb=wc[hi:].min()
        if lh>0: ss.iloc[i]=(lh-cb)/lh
    return ds, ss

def build_features(df):
    c=df['Close'].squeeze(); h=df['High'].squeeze()
    l=df['Low'].squeeze();   o=df['Open'].squeeze()
    ft=pd.DataFrame(index=c.index)

    # RSI
    ft['rsi14']=rsi(c,14)/100; ft['rsi7']=rsi(c,7)/100; ft['rsi21']=rsi(c,21)/100

    # EMA
    e8=c.ewm(span=8,adjust=False).mean(); e21=c.ewm(span=21,adjust=False).mean()
    e50=c.ewm(span=50,adjust=False).mean(); e200=c.ewm(span=200,adjust=False).mean()
    ft['e8d']=(c-e8)/(c+1e-10); ft['e21d']=(c-e21)/(c+1e-10)
    ft['e50d']=(c-e50)/(c+1e-10); ft['e200d']=(c-e200)/(c+1e-10)
    ft['ema_bull']=((e8>e21)&(e21>e50)&(e50>e200)).astype(float)
    ft['ema_bear']=((e8<e21)&(e21<e50)&(e50<e200)).astype(float)

    # MACD
    ml=c.ewm(span=12,adjust=False).mean()-c.ewm(span=26,adjust=False).mean()
    sl=ml.ewm(span=9,adjust=False).mean(); hist=ml-sl
    ft['macd_hist']=hist/(c.abs()+1e-10)*1000
    ft['macd_sig']=(ml>sl).astype(float)
    ft['macd_cup']=((ml>sl)&(ml.shift()<=sl.shift())).astype(float)
    ft['macd_cdn']=((ml<sl)&(ml.shift()>=sl.shift())).astype(float)

    # Bollinger
    bm=c.rolling(20).mean(); bs=c.rolling(20).std()
    bu=bm+2*bs; bl2=bm-2*bs
    ft['bb_pos']=((c-bl2)/(bu-bl2+1e-10)).clip(0,1)
    ft['bb_wid']=((bu-bl2)/(bm+1e-10)).clip(0,0.2)/0.2
    ft['bb_sqz']=(ft['bb_wid']<ft['bb_wid'].rolling(20).mean()).astype(float)

    # ATR
    a14=atr_fn(h,l,c,14); a50=atr_fn(h,l,c,50)
    ft['atr_rat']=(a14/(a50+1e-10)).clip(0,5)/5
    ft['atr_pct']=(a14/(c+1e-10)).clip(0,0.05)/0.05
    ft['atr_up']=(a14>a50).astype(float)

    # Price action
    body=(c-o).abs(); rng=(h-l).clip(lower=1e-10)
    uw=h-pd.concat([c,o],axis=1).max(axis=1)
    lw=pd.concat([c,o],axis=1).min(axis=1)-l
    ft['body_r']=(body/rng).clip(0,1); ft['bull']=(c>o).astype(float)
    ft['pin_b']=((lw/rng>0.6)&(body/rng<0.3)).astype(float)
    ft['pin_s']=((uw/rng>0.6)&(body/rng<0.3)).astype(float)
    ft['engulf']=((c>o)&(c>o.shift())&(o<c.shift())&(body>body.shift())).astype(float)

    # Momentum
    ft['mom5']=c.pct_change(5).clip(-0.1,0.1)/0.1
    ft['mom20']=c.pct_change(20).clip(-0.2,0.2)/0.2
    ft['mom60']=c.pct_change(60).clip(-0.3,0.3)/0.3
    ft['roc']=(c/c.shift(10)-1).clip(-0.1,0.1)/0.1

    # Supply/Demand zones
    ds,ss=supply_demand(h,l,c)
    ft['demand']=ds.clip(0,0.05)/0.05
    ft['supply']=ss.clip(0,0.05)/0.05

    # Stochastic
    ll14=l.rolling(14).min(); hh14=h.rolling(14).max()
    sk=((c-ll14)/(hh14-ll14+1e-10)*100)
    ft['stoch_k']=sk.clip(0,100)/100
    ft['stoch_d']=sk.rolling(3).mean().clip(0,100)/100

    return ft.dropna()

def build_labels(df, fidx, horizon=3, thresh=0.0002):
    c=df['Close'].squeeze().reindex(fidx)
    r=c.shift(-horizon)/c-1
    lb=np.where(r>thresh,2,np.where(r<-thresh,0,1))
    return lb[:-horizon]

X_all, y_all = [], []
for name, df in all_data.items():
    try:
        ft=build_features(df); lb=build_labels(df,ft.index)
        n=len(lb); X_all.append(ft.values[:n]); y_all.append(lb)
        print(f"  {name}: {n} samples BUY:{(lb==2).sum()} HOLD:{(lb==1).sum()} SELL:{(lb==0).sum()}")
    except Exception as e:
        print(f"  SKIP {name}: {e}")

X_flat=np.vstack(X_all).astype(np.float32)
y_flat=np.concatenate(y_all).astype(np.int32)
N_FEAT=X_flat.shape[1]
SEQ_LEN=20
print(f"\n  Total: {len(X_flat)} samples | Features: {N_FEAT}")

# STEP 3: SCALE + BUILD SEQUENCES
print(f"\n[3/6] Scaling and building sequences (lookback={SEQ_LEN})...")
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import accuracy_score, classification_report
from sklearn.utils.class_weight import compute_class_weight

scaler=StandardScaler()
Xs=scaler.fit_transform(X_flat).astype(np.float32)

os.makedirs("model",exist_ok=True)
with open("model/scaler_params.json","w") as f:
    json.dump({
        "mean": scaler.mean_.tolist(),
        "scale": scaler.scale_.tolist(),
        "n_features": int(N_FEAT),
        "sequence_len": SEQ_LEN,
        "version": "2.0-LSTM"
    }, f, indent=2)

def make_seq(X,y,sl):
    Xo,yo=[],[]
    for i in range(sl,len(X)):
        Xo.append(X[i-sl:i]); yo.append(y[i])
    return np.array(Xo,dtype=np.float32),np.array(yo,dtype=np.int32)

X_seq,y_seq=make_seq(Xs,y_flat,SEQ_LEN)
print(f"  Sequence shape: {X_seq.shape}")

sp=int(len(X_seq)*0.8)
Xtr,Xte=X_seq[:sp],X_seq[sp:]
ytr,yte=y_seq[:sp],y_seq[sp:]

# STEP 4: BUILD LSTM MODEL
print("\n[4/6] Building LSTM + Attention model...")
import tensorflow as tf

cw_v=compute_class_weight('balanced',classes=np.unique(ytr),y=ytr)
cw={i:cw_v[i] for i in range(len(cw_v))}

inp=tf.keras.Input(shape=(SEQ_LEN,N_FEAT))
x=tf.keras.layers.LSTM(128,return_sequences=True,dropout=0.2,recurrent_dropout=0.1)(inp)
x=tf.keras.layers.LSTM(64, return_sequences=True,dropout=0.2,recurrent_dropout=0.1)(x)
# Attention
at=tf.keras.layers.Dense(1,activation='tanh')(x)
at=tf.keras.layers.Flatten()(at)
at=tf.keras.layers.Activation('softmax')(at)
at=tf.keras.layers.RepeatVector(64)(at)
at=tf.keras.layers.Permute([2,1])(at)
xm=tf.keras.layers.Multiply()([x,at])
xm=tf.keras.layers.Lambda(lambda z:tf.reduce_sum(z,axis=1))(xm)
x=tf.keras.layers.Dense(64,activation='relu')(xm)
x=tf.keras.layers.BatchNormalization()(x)
x=tf.keras.layers.Dropout(0.3)(x)
x=tf.keras.layers.Dense(32,activation='relu')(x)
out=tf.keras.layers.Dense(3,activation='softmax')(x)

model=tf.keras.Model(inp,out)
model.compile(optimizer=tf.keras.optimizers.Adam(0.001),
              loss='sparse_categorical_crossentropy',metrics=['accuracy'])
print(f"  Parameters: {model.count_params():,}")

# STEP 5: TRAIN
print("\n[5/6] Training...")
model.fit(Xtr,ytr,validation_data=(Xte,yte),epochs=60,batch_size=256,
          class_weight=cw,verbose=1,
          callbacks=[
              tf.keras.callbacks.EarlyStopping(patience=10,restore_best_weights=True,monitor='val_accuracy'),
              tf.keras.callbacks.ReduceLROnPlateau(patience=5,factor=0.5,min_lr=1e-5)
          ])

yp=model.predict(Xte,verbose=0).argmax(axis=1)
acc=accuracy_score(yte,yp)
print(f"\n  Test Accuracy: {acc*100:.2f}%")
print(classification_report(yte,yp,target_names=["SELL","HOLD","BUY"]))

# STEP 6: EXPORT ONNX
print("\n[6/6] Exporting ONNX...")
import tf2onnx, onnx

sig=[tf.TensorSpec([None,SEQ_LEN,N_FEAT],tf.float32,name="input")]
tf2onnx.convert.from_keras(model,input_signature=sig,opset=12,
                            output_path="model/ForexSniper_AI.onnx")
onnx.checker.check_model(onnx.load("model/ForexSniper_AI.onnx"))
sz=os.path.getsize("model/ForexSniper_AI.onnx")/1024

with open("model/metadata.json","w") as f:
    json.dump({
        "trained_at": pd.Timestamp.now().isoformat(),
        "accuracy": float(acc),
        "architecture": "LSTM-128+LSTM-64+Attention+Dense-64-32-3",
        "sequence_len": SEQ_LEN,
        "n_features": int(N_FEAT),
        "n_samples": int(len(X_seq)),
        "pairs_used": list(all_data.keys()),
        "model_size_kb": float(sz),
        "scaler_mean": scaler.mean_.tolist(),
        "scaler_scale": scaler.scale_.tolist(),
    },f,indent=2)

print(f"\n{'='*60}")
print(f"  LSTM MODEL READY!")
print(f"  Accuracy:     {acc*100:.2f}%")
print(f"  Architecture: LSTM-128 + LSTM-64 + Attention")
print(f"  Features:     {N_FEAT} (incl. Supply/Demand)")
print(f"  Sequence:     {SEQ_LEN} candle lookback")
print(f"  Size:         {sz:.1f} KB")
print(f"{'='*60}")
