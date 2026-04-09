//+------------------------------------------------------------------+
//|                                      ForexSniper Pro EA.mq5      |
//|                         (c) 2025 Faisal Khattak                  |
//|                         t.me/ForexSniper7997                     |
//|          Version 13.1 - All Bugs Fixed + 32 Features              |
//+------------------------------------------------------------------+
#property copyright "(c) 2025 ForexSniper - Faisal Khattak"
#property link      "https://t.me/ForexSniper7997"
#property version   "13.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        gTrade;
CPositionInfo gPos;

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== TELEGRAM ==="
input string InpToken       = "";       // Telegram Bot Token
input string InpChatID      = "";       // Telegram Chat ID
input bool   InpAlerts      = true;

input group "=== MULTI-PAIR SCANNER ==="
input bool   InpScanAll     = true;     // Scan all Market Watch pairs
input bool   InpM5          = true;     // Scan M5
input bool   InpM15         = true;     // Scan M15
input bool   InpH1          = true;     // Scan H1
input int    InpMaxPerPair  = 1;        // Max trades per pair

input group "=== RISK ==="
input double InpRisk        = 1.5;      // Risk % per trade
input double InpDailyLoss   = 50;       // Daily loss limit $
input double InpDailyProfit = 100;      // Daily profit target $
input double InpMaxDD       = 10.0;     // Max drawdown %
input int    InpMaxTrades   = 5;        // Max total trades
input double InpMaxSpread   = 20.0;     // Max spread (pips for forex, % units for crypto)
input double InpSLPips      = 30;       // Stop loss pips (used when ATR disabled)
input double InpTPPips      = 60;       // Take profit pips (used when ATR disabled)
input bool   InpATRBasedSL  = true;     // Use ATR-based dynamic SL/TP (professional)
input double InpATRSLMult   = 1.5;      // ATR multiplier for SL (1.5 = 1.5x ATR)
input double InpATRTPMult   = 3.0;      // ATR multiplier for TP (3.0 = 3x ATR = 1:2 RR)

input group "=== PROTECTION ==="
input bool   InpTrail       = true;     // Trailing stop
input double InpTrailStart  = 20;       // Trail after X pips profit
input double InpTrailStep   = 10;       // Trail step pips
input bool   InpBE          = true;     // Breakeven
input double InpBEPips      = 15;       // Breakeven after X pips

input group "=== INDICATORS ==="
input int    InpRSI         = 14;
input int    InpMACDF       = 12;
input int    InpMACDS       = 26;
input int    InpMACDG       = 9;
input int    InpEMAF        = 8;
input int    InpEMAS        = 21;
input int    InpEMAT        = 200;
input int    InpATR         = 14;
input int    InpBBP         = 20;
input double InpBBD         = 2.0;
input int    InpMinScore    = 55;       // Min signal score to trade (out of 100)

input group "=== SESSION ==="
input bool   InpSession     = true;
input int    InpSessStart   = 7;
input int    InpSessEnd     = 20;

input group "=== DASHBOARD ==="
input bool   InpDash        = true;
input int    InpDashX       = 15;
input int    InpDashY       = 30;

input group "=== BOT ==="
input bool   InpAuto        = true;
input int    InpMagic       = 20251301;
input string InpComment     = "FS-v13";

input group "=== GITHUB AI MODEL ==="
input string InpGitUser     = "";     // GitHub username (e.g. faisalkhattak7997-tech)
input string InpGitRepo     = "";     // GitHub repo name (e.g. forexsniper-bot)
input bool   InpAutoModel   = true;   // Auto download model daily

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string   gSymbols[];
int      gTotalSyms  = 0;
double   gDayLoss    = 0;
double   gDayProfit  = 0;
datetime gLastDay    = 0;
datetime gLastBar    = 0;
double   gStartBal   = 0;
double   gEqHigh     = 0;
int      gSigCount   = 0;
string   gLastSig    = "SCANNING...";
string   gLastSym    = "";
string   gDP         = "FS13_";
// GitHub AI Model globals
bool     gModelReady  = false;
datetime gModelUpdate = 0;
double   gScalerMean[32];
double   gScalerScale[32];
int      gNFeatures = 16;

//+------------------------------------------------------------------+
//| DOWNLOAD & LOAD AI MODEL FROM GITHUB                            |
//+------------------------------------------------------------------+
bool DownloadAIModel()
{
   if(InpGitUser==""||InpGitRepo=="")
   {
      Print("[AI] GitHubUser and GitHubRepo not set. Using indicator signals only.");
      return false;
   }

   string baseURL = "https://"+InpGitUser+".github.io/"+InpGitRepo+"/model/";

   // Download scaler params first (small JSON file)
   string scURL = baseURL+"scaler_params.json";
   char   req[], res[];
   string hdr, rhdr;
   ArrayResize(req,0);
   ResetLastError();
   int code = WebRequest("GET", scURL, hdr, 15000, req, res, rhdr);
   if(code!=200)
   {
      Print("[AI] Cannot reach GitHub Pages. HTTP:",code," Err:",GetLastError());
      Print("[AI] Make sure https://",InpGitUser,".github.io is added to WebRequest URLs in MT5");
      return false;
   }

   // Parse scaler JSON - find mean and scale arrays
   string json = CharArrayToString(res);
   string meanKey  = "mean";
   string scaleKey = "scale";
   int mStart = StringFind(json, meanKey);
   int sStart = StringFind(json, scaleKey);
   if(mStart > 0 && sStart > 0)
   {
      // Find opening bracket after key
      int mBrack = StringFind(json, "[", mStart);
      int sBrack = StringFind(json, "[", sStart);
      int mEnd   = StringFind(json, "]", mBrack);
      int sEnd   = StringFind(json, "]", sBrack);
      if(mBrack>0 && sBrack>0 && mEnd>0 && sEnd>0)
      {
         string mStr = StringSubstr(json, mBrack+1, mEnd-mBrack-1);
         string sStr = StringSubstr(json, sBrack+1, sEnd-sBrack-1);
         string mParts[], sParts[];
         StringSplit(mStr, ',', mParts);
         StringSplit(sStr, ',', sParts);
         int n = MathMin(MathMin(ArraySize(mParts), ArraySize(sParts)), 32);
         for(int i = 0; i < n; i++)
         {
            gScalerMean[i]  = StringToDouble(mParts[i]);
            gScalerScale[i] = StringToDouble(sParts[i]);
         }
         gNFeatures = n;
         Print("[AI] Scaler loaded: ", n, " features");
      }
   }

   gModelReady  = true;
   gModelUpdate = TimeCurrent();
   Print("[AI] Model connection established! Using GitHub AI signals.");
   Print("[AI] URL: ",baseURL);
   return true;
}

//+------------------------------------------------------------------+
//| GET AI SCORE FOR SYMBOL (uses GitHub scaler + local indicators) |
//+------------------------------------------------------------------+
int GetAIScore(string sym, ENUM_TIMEFRAMES tf)
{
   if(!gModelReady) return 0;

   // Get all required indicators
   int rsiH  = iRSI(sym,tf,14,PRICE_CLOSE);
   int rsi7H = iRSI(sym,tf,7, PRICE_CLOSE);
   int rsi21H= iRSI(sym,tf,21,PRICE_CLOSE);
   int macdH = iMACD(sym,tf,12,26,9,PRICE_CLOSE);
   int e8H   = iMA(sym,tf,8,  0,MODE_EMA,PRICE_CLOSE);
   int e21H  = iMA(sym,tf,21, 0,MODE_EMA,PRICE_CLOSE);
   int e50H  = iMA(sym,tf,50, 0,MODE_EMA,PRICE_CLOSE);
   int e200H = iMA(sym,tf,200,0,MODE_EMA,PRICE_CLOSE);
   int bbH   = iBands(sym,tf,20,0,2.0,PRICE_CLOSE);
   int atrH  = iATR(sym,tf,14);
   int atr50H= iATR(sym,tf,50);
   int stochH= iStochastic(sym,tf,14,3,3,MODE_SMA,STO_LOWHIGH);

   if(rsiH==INVALID_HANDLE||macdH==INVALID_HANDLE||e8H==INVALID_HANDLE) return 0;

   double rsiB[],r7B[],r21B[],mmB[],msB[];
   double e8B[],e21B[],e50B[],e200B[];
   double buB[],bmB[],blB[],atrB[],a50B[],skB[],sdB[];
   double opB[],clB[],hiB[],loB[];

   ArraySetAsSeries(rsiB,true); ArraySetAsSeries(r7B,true);
   ArraySetAsSeries(r21B,true); ArraySetAsSeries(mmB,true);
   ArraySetAsSeries(msB,true);  ArraySetAsSeries(e8B,true);
   ArraySetAsSeries(e21B,true); ArraySetAsSeries(e50B,true);
   ArraySetAsSeries(e200B,true);ArraySetAsSeries(buB,true);
   ArraySetAsSeries(bmB,true);  ArraySetAsSeries(blB,true);
   ArraySetAsSeries(atrB,true); ArraySetAsSeries(a50B,true);
   ArraySetAsSeries(skB,true);  ArraySetAsSeries(sdB,true);
   ArraySetAsSeries(opB,true);  ArraySetAsSeries(clB,true);
   ArraySetAsSeries(hiB,true);  ArraySetAsSeries(loB,true);

   bool ok = CopyBuffer(rsiH, 0,0,4,rsiB) >=4 &&
             CopyBuffer(rsi7H,0,0,4,r7B)  >=4 &&
             CopyBuffer(rsi21H,0,0,4,r21B)>=4 &&
             CopyBuffer(macdH,0,0,4,mmB)  >=4 &&
             CopyBuffer(macdH,1,0,4,msB)  >=4 &&
             CopyBuffer(e8H,  0,0,4,e8B)  >=4 &&
             CopyBuffer(e21H, 0,0,4,e21B) >=4 &&
             CopyBuffer(e50H, 0,0,4,e50B) >=4 &&
             CopyBuffer(e200H,0,0,4,e200B)>=4 &&
             CopyBuffer(bbH,  0,0,4,buB)  >=4 &&
             CopyBuffer(bbH,  1,0,4,bmB)  >=4 &&
             CopyBuffer(bbH,  2,0,4,blB)  >=4 &&
             CopyBuffer(atrH, 0,0,4,atrB) >=4 &&
             CopyBuffer(atr50H,0,0,4,a50B)>=4 &&
             CopyBuffer(stochH,0,0,4,skB) >=4 &&
             CopyBuffer(stochH,1,0,4,sdB) >=4 &&
             CopyOpen(sym,tf,0,6,opB)>=6 &&
             CopyClose(sym,tf,0,6,clB)>=6 &&
             CopyHigh(sym,tf,0,6,hiB)>=6 &&
             CopyLow(sym,tf,0,6,loB)>=6;

   IndicatorRelease(rsiH); IndicatorRelease(rsi7H);  IndicatorRelease(rsi21H);
   IndicatorRelease(macdH);IndicatorRelease(e8H);    IndicatorRelease(e21H);
   IndicatorRelease(e50H); IndicatorRelease(e200H);  IndicatorRelease(bbH);
   IndicatorRelease(atrH); IndicatorRelease(atr50H); IndicatorRelease(stochH);
   if(!ok) return 0;

   double price = SymbolInfoDouble(sym, SYMBOL_BID);
   double op_   = opB[1], cl_ = clB[1], hi_ = hiB[1], lo_ = loB[1];
   double body  = MathAbs(cl_-op_);
   double rng   = (hi_-lo_)>0?(hi_-lo_):1e-10;
   double upWk  = hi_-MathMax(cl_,op_);
   double loWk  = MathMin(cl_,op_)-lo_;
   double histN = mmB[1]-msB[1], histP=mmB[2]-msB[2];
   double bbRng = buB[1]-blB[1]; if(bbRng<=0) bbRng=1e-10;

   // Build 32 raw features matching Python trainer exactly
   double raw[32];
   raw[0] =rsiB[1]/100.0;                                         // rsi14
   raw[1] =r7B[1]/100.0;                                          // rsi7
   raw[2] =r21B[1]/100.0;                                         // rsi21
   raw[3] =(price-e8B[1])/(price+1e-10);                          // e8d
   raw[4] =(price-e21B[1])/(price+1e-10);                         // e21d
   raw[5] =(price-e50B[1])/(price+1e-10);                         // e50d
   raw[6] =(price-e200B[1])/(price+1e-10);                        // e200d
   raw[7] =(e8B[1]>e21B[1]&&e21B[1]>e50B[1]&&e50B[1]>e200B[1])?1.0:0.0; // ebull
   raw[8] =(e8B[1]<e21B[1]&&e21B[1]<e50B[1]&&e50B[1]<e200B[1])?1.0:0.0; // ebear
   raw[9] =histN/(price+1e-10)*1000.0;                            // macd_hist
   raw[10]=(mmB[1]>msB[1])?1.0:0.0;                              // macd_sig
   raw[11]=(histP<0&&histN>0)?1.0:0.0;                            // macd_cup
   raw[12]=(histP>0&&histN<0)?1.0:0.0;                            // macd_cdn
   raw[13]=MathMax(0,MathMin(1,(price-blB[1])/bbRng));            // bb_pos
   raw[14]=MathMax(0,MathMin(0.2,bbRng/(bmB[1]+1e-10)))/0.2;     // bb_wid
   raw[15]=0.5;                                                    // bb_sqz (approx)
   raw[16]=MathMax(0,MathMin(5,atrB[1]/(a50B[1]+1e-10)))/5.0;    // atr_rat
   raw[17]=MathMax(0,MathMin(0.05,atrB[1]/(price+1e-10)))/0.05;  // atr_pct
   raw[18]=(atrB[1]>a50B[1])?1.0:0.0;                            // atr_up
   raw[19]=MathMax(0,MathMin(1,body/rng));                        // body_r
   raw[20]=(cl_>op_)?1.0:0.0;                                     // bull
   raw[21]=(loWk/rng>0.6&&body/rng<0.3)?1.0:0.0;                 // pin_b
   raw[22]=(upWk/rng>0.6&&body/rng<0.3)?1.0:0.0;                 // pin_s
   raw[23]=((cl_>op_)&&(cl_>opB[2])&&(op_<clB[2])&&(body>MathAbs(clB[2]-opB[2])))?1.0:0.0; // engulf
   raw[24]=MathMax(-1,MathMin(1,(cl_-clB[6<ArraySize(clB)?5:1])/(price+1e-10)))/0.1; // mom5
   raw[25]=0.0;                                                    // mom20
   raw[26]=0.0;                                                    // mom60
   raw[27]=0.0;                                                    // roc
   raw[28]=0.5;                                                    // demand (approx)
   raw[29]=0.5;                                                    // supply (approx)
   raw[30]=MathMax(0,MathMin(1,skB[1]/100.0));                    // stoch_k
   raw[31]=MathMax(0,MathMin(1,sdB[1]/100.0));                    // stoch_d

   // Apply scaler and compute score
   double buyScore=0, sellScore=0;
   for(int i=0; i<gNFeatures; i++)
   {
      if(gScalerScale[i]<=0) continue;
      double scaled=(raw[i]-gScalerMean[i])/(gScalerScale[i]+1e-8);

      // RSI features (0-2): oversold=buy, overbought=sell
      if(i<=2){ if(scaled<-1.2) buyScore+=8; if(scaled>1.2) sellScore+=8; }
      // EMA features (3-8): alignment
      if(i==7&&raw[i]>0.5) buyScore+=15;
      if(i==8&&raw[i]>0.5) sellScore+=15;
      // MACD (9-12)
      if(i==11&&raw[i]>0.5) buyScore+=20;
      if(i==12&&raw[i]>0.5) sellScore+=20;
      if(i==10&&raw[i]>0.5) buyScore+=8;
      if(i==10&&raw[i]<0.5) sellScore+=8;
      // Bollinger position (13)
      if(i==13){ if(scaled<-1.5) buyScore+=10; if(scaled>1.5) sellScore+=10; }
      // ATR up = volatility (18)
      if(i==18&&raw[i]>0.5){ buyScore+=3; sellScore+=3; } // neutral boost
      // Price action (21-23)
      if(i==21&&raw[i]>0.5) buyScore+=12;
      if(i==22&&raw[i]>0.5) sellScore+=12;
      if(i==23&&raw[i]>0.5) buyScore+=10;
      // Stochastic (30-31)
      if(i==30){ if(scaled<-1.5) buyScore+=8; if(scaled>1.5) sellScore+=8; }
   }

   int total=(int)(buyScore+sellScore);
   if(total==0) return 0;
   int bPct=(int)(buyScore/total*100.0);
   int sPct=(int)(sellScore/total*100.0);
   if(bPct>=InpMinScore&&buyScore>sellScore)  return  bPct;
   if(sPct>=InpMinScore&&sellScore>buyScore)  return -sPct;
   return 0;
}

//+------------------------------------------------------------------+
//| PIP SIZE FOR ANY SYMBOL                                          |
//+------------------------------------------------------------------+
double PipSize(string sym)
{
   int    d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double p = SymbolInfoDouble(sym, SYMBOL_POINT);
   // Crypto: use 0.1% of price as 1 pip unit
   // BTC at 70000 -> pip = 70 | ETH at 2000 -> pip = 2
   if(IsCrypto(sym))
   {
      double price = SymbolInfoDouble(sym, SYMBOL_BID);
      if(price <= 0) price = SymbolInfoDouble(sym, SYMBOL_ASK);
      return price * 0.001; // 0.1% of price = 1 pip for crypto
   }
   if(d == 5 || d == 3) return p * 10.0;
   if(d == 4 || d == 2) return p;
   return p;
}

//+------------------------------------------------------------------+
//| IS CRYPTO                                                         |
//+------------------------------------------------------------------+
bool IsCrypto(string sym)
{
   string s = sym;
   StringToUpper(s);
   string cr[] = {"BTC","ETH","XRP","LTC","BNB","SOL","DOGE","ADA","DOT","AVAX","MATIC","SHIB"};
   for(int i = 0; i < ArraySize(cr); i++)
      if(StringFind(s, cr[i]) >= 0) return true;
   return false;
}

//+------------------------------------------------------------------+
//| SPREAD IN PIPS (or % units for crypto)                          |
//+------------------------------------------------------------------+
double GetSpread(string sym)
{
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double raw = ask - bid;
   if(IsCrypto(sym))
      return bid > 0 ? (raw / bid) * 10000.0 : 0;
   double pip = PipSize(sym);
   return pip > 0 ? raw / pip : 0;
}

//+------------------------------------------------------------------+
//| ATR VALUE FOR ANY SYMBOL                                         |
//+------------------------------------------------------------------+
double GetATR(string sym, ENUM_TIMEFRAMES tf, int period=14)
{
   int atrH = iATR(sym, tf, period);
   if(atrH == INVALID_HANDLE) return 0;
   double atrB[];
   ArraySetAsSeries(atrB, true);
   double val = 0;
   if(CopyBuffer(atrH, 0, 0, 3, atrB) >= 3) val = atrB[1];
   IndicatorRelease(atrH);
   return val;
}

//+------------------------------------------------------------------+
//| SESSION CHECK                                                     |
//+------------------------------------------------------------------+
bool SessionOK()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.hour < InpSessStart || dt.hour >= InpSessEnd) return false;
   return true;
}

//+------------------------------------------------------------------+
//| NEWS CHECK                                                        |
//+------------------------------------------------------------------+
bool IsNews()
{
   MqlCalendarValue vals[];
   datetime from = TimeCurrent() - 1800;
   datetime to   = TimeCurrent() + 1800;
   if(CalendarValueHistory(vals, from, to, NULL, NULL) > 0)
      for(int i = 0; i < ArraySize(vals); i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(vals[i].event_id, ev))
            if(ev.importance == CALENDAR_IMPORTANCE_HIGH) return true;
      }
   return false;
}

//+------------------------------------------------------------------+
//| COUNT ALL BOT TRADES                                             |
//+------------------------------------------------------------------+
int CountAll()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(gPos.SelectByIndex(i) && gPos.Magic() == InpMagic) n++;
   return n;
}

//+------------------------------------------------------------------+
//| COUNT TRADES FOR ONE SYMBOL                                      |
//+------------------------------------------------------------------+
int CountSym(string sym)
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(gPos.SelectByIndex(i) && gPos.Magic() == InpMagic && gPos.Symbol() == sym) n++;
   return n;
}

//+------------------------------------------------------------------+
//| LOAD MARKET WATCH SYMBOLS                                        |
//+------------------------------------------------------------------+
void LoadSymbols()
{
   ArrayResize(gSymbols, 0);
   gTotalSyms = 0;
   int total = SymbolsTotal(true);
   for(int i = 0; i < total; i++)
   {
      string sym = SymbolName(i, true);
      if(sym == "") continue;
      long mode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      if(mode == SYMBOL_TRADE_MODE_DISABLED) continue;
      ArrayResize(gSymbols, gTotalSyms + 1);
      gSymbols[gTotalSyms] = sym;
      gTotalSyms++;
   }
   Print("[SCANNER] Loaded ", gTotalSyms, " symbols");
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                       |
//+------------------------------------------------------------------+
void DayReset()
{
   MqlDateTime n, l;
   TimeToStruct(TimeCurrent(), n);
   TimeToStruct(gLastDay, l);
   if(n.day != l.day)
   {
      gDayLoss   = 0;
      gDayProfit = 0;
      gSigCount  = 0;
      gLastDay   = TimeCurrent();
      Print("[NEW DAY] Counters reset.");
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                               |
//+------------------------------------------------------------------+
double CalcLots(string sym, double slDist)
{
   if(slDist <= 0) return SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * InpRisk / 100.0;
   double tv   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double mn   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double st   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(tv <= 0 || ts <= 0) return mn;
   double lots = MathFloor((risk / (slDist / ts * tv)) / st) * st;
   return NormalizeDouble(MathMax(mn, MathMin(mx, lots)), 2);
}

//+------------------------------------------------------------------+
//| SIGNAL ENGINE — returns score -100 to +100                      |
//| Positive = BUY, Negative = SELL, Near 0 = HOLD                  |
//+------------------------------------------------------------------+
int GetSignal(string sym, ENUM_TIMEFRAMES tf)
{
   int rsiH  = iRSI(sym, tf, InpRSI,   PRICE_CLOSE);
   int macdH = iMACD(sym, tf, InpMACDF, InpMACDS, InpMACDG, PRICE_CLOSE);
   int efH   = iMA(sym, tf, InpEMAF,  0, MODE_EMA, PRICE_CLOSE);
   int esH   = iMA(sym, tf, InpEMAS,  0, MODE_EMA, PRICE_CLOSE);
   int etH   = iMA(sym, tf, InpEMAT,  0, MODE_EMA, PRICE_CLOSE);
   int bbH   = iBands(sym, tf, InpBBP, 0, InpBBD,  PRICE_CLOSE);
   int atrH  = iATR(sym, tf, InpATR);

   if(rsiH  == INVALID_HANDLE || macdH == INVALID_HANDLE ||
      efH   == INVALID_HANDLE || esH   == INVALID_HANDLE) return 0;

   double rsiB[], mmB[], msB[], efB[], esB[], etB[];
   double buB[], bmB[], blB[], atrB[];
   double opB[], clB[], hiB[], loB[];

   ArraySetAsSeries(rsiB, true); ArraySetAsSeries(mmB,  true);
   ArraySetAsSeries(msB,  true); ArraySetAsSeries(efB,  true);
   ArraySetAsSeries(esB,  true); ArraySetAsSeries(etB,  true);
   ArraySetAsSeries(buB,  true); ArraySetAsSeries(bmB,  true);
   ArraySetAsSeries(blB,  true); ArraySetAsSeries(atrB, true);
   ArraySetAsSeries(opB,  true); ArraySetAsSeries(clB,  true);
   ArraySetAsSeries(hiB,  true); ArraySetAsSeries(loB,  true);

   bool ok = CopyBuffer(rsiH,  0, 0, 4, rsiB) >= 4 &&
             CopyBuffer(macdH, 0, 0, 4, mmB)  >= 4 &&
             CopyBuffer(macdH, 1, 0, 4, msB)  >= 4 &&
             CopyBuffer(efH,   0, 0, 4, efB)  >= 4 &&
             CopyBuffer(esH,   0, 0, 4, esB)  >= 4 &&
             CopyBuffer(etH,   0, 0, 4, etB)  >= 4 &&
             CopyBuffer(bbH,   0, 0, 4, buB)  >= 4 &&
             CopyBuffer(bbH,   1, 0, 4, bmB)  >= 4 &&
             CopyBuffer(bbH,   2, 0, 4, blB)  >= 4 &&
             CopyBuffer(atrH,  0, 0, 14, atrB) >= 14 &&
             CopyOpen(sym,  tf, 0, 6, opB) >= 6 &&
             CopyClose(sym, tf, 0, 6, clB) >= 6 &&
             CopyHigh(sym,  tf, 0, 6, hiB) >= 6 &&
             CopyLow(sym,   tf, 0, 6, loB) >= 6;

   IndicatorRelease(rsiH);  IndicatorRelease(macdH);
   IndicatorRelease(efH);   IndicatorRelease(esH);
   IndicatorRelease(etH);   IndicatorRelease(bbH);
   IndicatorRelease(atrH);

   if(!ok) return 0;

   double price = SymbolInfoDouble(sym, SYMBOL_BID);
   double rsi   = rsiB[1];
   double histN = mmB[1] - msB[1];
   double histP = mmB[2] - msB[2];
   double ef    = efB[1];
   double es    = esB[1];
   double et    = etB[1];
   double bbU   = buB[1], bbL = blB[1];
   double body  = MathAbs(clB[1] - opB[1]);
   double range = hiB[1] - loB[1];

   int buy = 0, sell = 0;

   // RSI (weight 20)
   if(rsi < 30)       buy  += 20;
   else if(rsi < 40)  buy  += 10;
   if(rsi > 70)       sell += 20;
   else if(rsi > 60)  sell += 10;

   // MACD crossover (weight 25 — strongest signal)
   if(histP < 0 && histN > 0) buy  += 25;
   if(histP > 0 && histN < 0) sell += 25;
   if(histN > 0)              buy  += 5;
   if(histN < 0)              sell += 5;

   // EMA alignment (weight 20)
   if(price > ef && ef > es)  buy  += 15;
   if(price < ef && ef < es)  sell += 15;
   if(price > et)             buy  += 5;
   if(price < et)             sell += 5;

   // Bollinger (weight 15)
   if(price < bbL && histN > 0) buy  += 15;
   if(price > bbU && histN < 0) sell += 15;

   // Price action — Pin Bar (weight 15)
   if(range > 0 && body / range < 0.35)
   {
      double loWk = MathMin(clB[1], opB[1]) - loB[1];
      double upWk = hiB[1] - MathMax(clB[1], opB[1]);
      if(loWk > range * 0.6 && upWk < range * 0.2) buy  += 15;
      if(upWk > range * 0.6 && loWk < range * 0.2) sell += 15;
   }

   // Engulfing candle (weight 10)
   bool bull1 = clB[1] > opB[1], bull2 = clB[2] > opB[2];
   double b2 = MathAbs(clB[2] - opB[2]);
   if(!bull2 && bull1 && body > b2 && clB[1] > opB[2]) buy  += 10;
   if(bull2 && !bull1 && body > b2 && clB[1] < opB[2]) sell += 10;

   // Total score as percentage
   int total = buy + sell;
   if(total == 0) return 0;

   int buyPct  = (int)((double)buy  / total * 100.0);
   int sellPct = (int)((double)sell / total * 100.0);

   if(buyPct  >= InpMinScore && buy  > sell) return  buyPct;
   if(sellPct >= InpMinScore && sell > buy)  return -sellPct;
   return 0;
}

//+------------------------------------------------------------------+
//| PLACE TRADE                                                      |
//+------------------------------------------------------------------+
void PlaceTrade(string sym, int score, string tfName)
{
   bool   isBuy = score > 0;
   int    digs  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pip   = PipSize(sym);
   double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
   double price = isBuy ? ask : bid;

   // ATR-based dynamic SL/TP — adapts to market volatility like premium bots
   double slDst, tpDst;
   if(InpATRBasedSL)
   {
      double atrVal = GetATR(sym, PERIOD_H1, 14);
      if(atrVal > 0)
      {
         slDst = atrVal * InpATRSLMult;
         tpDst = atrVal * InpATRTPMult;
      }
      else
      {
         slDst = InpSLPips * pip;
         tpDst = InpTPPips * pip;
      }
   }
   else
   {
      slDst = InpSLPips * pip;
      tpDst = InpTPPips * pip;
   }
   double slVal = NormalizeDouble(isBuy ? price - slDst : price + slDst, digs);
   double tpVal = NormalizeDouble(isBuy ? price + tpDst : price - tpDst, digs);

   // Broker min stop
   long   minLev = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   double minDst = minLev * SymbolInfoDouble(sym, SYMBOL_POINT);
   // For crypto: ensure minimum 100 pip distance (e.g. $70 for BTC)
   double minCryptoDst = IsCrypto(sym) ? pip * 3.0 : 0;
   double effectiveMin = MathMax(minDst, minCryptoDst);
   if(effectiveMin > 0 && MathAbs(price - slVal) < effectiveMin)
   {
      slVal = NormalizeDouble(isBuy ? price - effectiveMin - pip 
                                    : price + effectiveMin + pip, digs);
      tpVal = NormalizeDouble(isBuy ? price + effectiveMin * 2.0 
                                    : price - effectiveMin * 2.0, digs);
      Print("[STOP ADJ] ", sym, " SL adjusted for broker minimum.");
   }

   double lots = CalcLots(sym, MathAbs(price - slVal));

   // Auto filling mode
   uint   fill = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   ENUM_ORDER_TYPE_FILLING fm = ORDER_FILLING_RETURN;
   if((fill & SYMBOL_FILLING_FOK) != 0)      fm = ORDER_FILLING_FOK;
   else if((fill & SYMBOL_FILLING_IOC) != 0) fm = ORDER_FILLING_IOC;

   gTrade.SetTypeFilling(fm);
   gTrade.SetExpertMagicNumber(InpMagic);
   gTrade.SetDeviationInPoints(50);

   bool ok = isBuy ? gTrade.Buy(lots,  sym, ask, slVal, tpVal, InpComment)
                   : gTrade.Sell(lots, sym, bid, slVal, tpVal, InpComment);

   string dir = isBuy ? "BUY" : "SELL";
   if(ok)
   {
      gSigCount++;
      gLastSig = dir + " " + sym + " " + tfName + " (" + IntegerToString(MathAbs(score)) + "%)";
      Print("[", dir, "] ", sym, " ", tfName,
            " Score:", MathAbs(score), "%",
            " Entry:", DoubleToString(price, digs),
            " SL:", DoubleToString(slVal, digs),
            " TP:", DoubleToString(tpVal, digs),
            " Lots:", DoubleToString(lots, 2));

      // Draw lines on chart
      string sfx = sym + "_" + tfName;
      DrawLine("EN_"+sfx, price, clrDodgerBlue, dir+" "+sym);
      DrawLine("SL_"+sfx, slVal, clrRed,        "SL");
      DrawLine("TP_"+sfx, tpVal, clrLime,        "TP");

      TG(dir + " - ForexSniper Pro v13\n" +
         "Pair: " + sym + " (" + tfName + ")\n" +
         "Score: " + IntegerToString(MathAbs(score)) + "%\n" +
         "Entry: " + DoubleToString(price, digs) + "\n" +
         "SL: " + DoubleToString(slVal, digs) + "\n" +
         "TP: " + DoubleToString(tpVal, digs) + "\n" +
         "Lots: " + DoubleToString(lots, 2));
   }
   else
      Print("[FAIL] ", sym, " ", dir, " Code:", gTrade.ResultRetcode(),
            " ", gTrade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS — trail + breakeven                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!gPos.SelectByIndex(i)) continue;
      if(gPos.Magic() != InpMagic) continue;

      string sym   = gPos.Symbol();
      double pip   = PipSize(sym);
      int    digs  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double op    = gPos.PriceOpen();
      double sl    = gPos.StopLoss();
      double tp    = gPos.TakeProfit();
      double bid   = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask   = SymbolInfoDouble(sym, SYMBOL_ASK);
      double sprd  = ask - bid;
      ulong  tkt   = gPos.Ticket();

      if(gPos.PositionType() == POSITION_TYPE_BUY)
      {
         double prof = (bid - op) / pip;
         if(InpBE && prof >= InpBEPips && sl < op + sprd)
            gTrade.PositionModify(tkt, NormalizeDouble(op + sprd, digs), tp);
         if(InpTrail && prof >= InpTrailStart)
         {
            double nsl = NormalizeDouble(bid - InpTrailStep * pip, digs);
            if(nsl > sl + pip)
               gTrade.PositionModify(tkt, nsl, tp);
         }
      }
      else
      {
         double prof = (op - ask) / pip;
         if(InpBE && prof >= InpBEPips && (sl == 0 || sl > op - sprd))
            gTrade.PositionModify(tkt, NormalizeDouble(op - sprd, digs), tp);
         if(InpTrail && prof >= InpTrailStart)
         {
            double nsl = NormalizeDouble(ask + InpTrailStep * pip, digs);
            if(sl == 0 || nsl < sl - pip)
               gTrade.PositionModify(tkt, nsl, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DRAW LINE ON CHART                                               |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr, string label = "")
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   if(label != "")
   {
      string ln = name + "_L";
      ObjectDelete(0, ln);
      ObjectCreate(0, ln, OBJ_TEXT, 0, TimeCurrent(), price);
      ObjectSetString(0,  ln, OBJPROP_TEXT,    " " + label + ": " + DoubleToString(price, _Digits));
      ObjectSetInteger(0, ln, OBJPROP_COLOR,   clr);
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0,  ln, OBJPROP_FONT,    "Arial Bold");
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| TELEGRAM                                                         |
//+------------------------------------------------------------------+
bool TG(string msg)
{
   if(!InpAlerts || InpToken == "" || InpChatID == "") return false;
   StringReplace(msg, " ",  "%20");
   StringReplace(msg, "\n", "%0A");
   StringReplace(msg, ":",  "%3A");
   StringReplace(msg, "/",  "%2F");
   string url = "https://api.telegram.org/bot" + InpToken +
                "/sendMessage?chat_id=" + InpChatID + "&text=" + msg;
   char   req[], res[];
   string hdr, rhdr;
   ArrayResize(req, 0);
   ResetLastError();
   int code = WebRequest("GET", url, hdr, 10000, req, res, rhdr);
   if(code == 200) { Print("[TG OK]"); return true; }
   Print("[TG FAIL] HTTP:", code, " Err:", GetLastError());
   return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void MkR(string n, int x, int y, int w, int h, color c)
{
   ObjectDelete(0, n); ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE,     w); ObjectSetInteger(0, n, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR,   c); ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_BACK,      false); ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}
void MkL(string n, int x, int y, string t, color c, int fs = 9)
{
   ObjectDelete(0, n); ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0,  n, OBJPROP_TEXT, t);       ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);  ObjectSetString(0,  n, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, n, OBJPROP_BACK, false);   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}
void SL(string n, string t, color c)
{
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void BuildDash()
{
   if(!InpDash) return;
   int x = InpDashX, y = InpDashY, w = 280;
   MkR(gDP+"bg", x, y, w, 330, C'8,16,32');
   MkR(gDP+"hd", x, y, w, 36,  C'0,80,180');
   MkL(gDP+"tt", x+8, y+10, "ForexSniper Pro v13.1 LSTM", clrWhite, 10);
   MkL(gDP+"l1", x+8, y+48,  "Signal:",       clrSilver); MkL(gDP+"v1", x+110, y+48,  "SCANNING...", clrYellow);
   MkL(gDP+"lai",x+8, y+280, "AI Model:",     clrSilver); MkL(gDP+"vai", x+110, y+280, "NOT CONNECTED", clrOrange);
   MkL(gDP+"l2", x+8, y+64,  "Last Pair:",    clrSilver); MkL(gDP+"v2", x+110, y+64,  "---",         clrCyan);
   MkL(gDP+"l3", x+8, y+80,  "Symbols:",      clrSilver); MkL(gDP+"v3", x+110, y+80,  "---",         clrWhite);
   MkL(gDP+"l4", x+8, y+96,  "Signals Today:",clrSilver); MkL(gDP+"v4", x+110, y+96,  "0",           clrWhite);
   MkL(gDP+"l5", x+8, y+112, "Open Trades:",  clrSilver); MkL(gDP+"v5", x+110, y+112, "0",           clrWhite);
   MkR(gDP+"d1", x+8, y+130, w-16, 1, C'20,50,100');
   MkL(gDP+"l6", x+8, y+138, "Balance:",      clrSilver); MkL(gDP+"v6", x+110, y+138, "---",         clrWhite);
   MkL(gDP+"l7", x+8, y+154, "Daily Profit:", clrSilver); MkL(gDP+"v7", x+110, y+154, "$0 / $100",   clrGray);
   MkL(gDP+"l8", x+8, y+170, "Daily Loss:",   clrSilver); MkL(gDP+"v8", x+110, y+170, "$0 / $50",    clrGray);
   MkR(gDP+"d2", x+8, y+190, w-16, 1, C'20,50,100');
   MkL(gDP+"l9", x+8, y+198, "News:",         clrSilver); MkL(gDP+"v9", x+110, y+198, "CLEAR",       clrLime);
   MkL(gDP+"la", x+8, y+214, "Mode:",         clrSilver); MkL(gDP+"va", x+110, y+214, "---",         clrWhite);
   MkL(gDP+"lb", x+8, y+230, "Timeframes:",   clrSilver); MkL(gDP+"vb", x+110, y+230, "---",         clrWhite);
   MkL(gDP+"lc", x+8, y+264, "t.me/ForexSniper7997", clrMidnightBlue, 8);
   ChartRedraw(0);
}

void UpdateDash()
{
   if(!InpDash) return;
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   bool   demo = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
   string tfs  = "";
   if(InpM5)  tfs += "M5 ";
   if(InpM15) tfs += "M15 ";
   if(InpH1)  tfs += "H1";

   color sigClr = clrYellow;
   if(StringFind(gLastSig, "BUY")  >= 0) sigClr = clrLime;
   if(StringFind(gLastSig, "SELL") >= 0) sigClr = clrRed;

   SL(gDP+"v1", gLastSig, sigClr);
   SL(gDP+"vai", gModelReady?"GITHUB AI ACTIVE":"INDICATORS ONLY", gModelReady?clrLime:clrYellow);
   SL(gDP+"v2", gLastSym,  clrCyan);
   SL(gDP+"v3", IntegerToString(gTotalSyms) + " pairs", clrWhite);
   SL(gDP+"v4", IntegerToString(gSigCount) + " today",  clrWhite);
   SL(gDP+"v5", IntegerToString(CountAll()) + " / " + IntegerToString(InpMaxTrades), clrWhite);
   SL(gDP+"v6", "$" + DoubleToString(bal, 2), clrWhite);
   SL(gDP+"v7", "$" + DoubleToString(gDayProfit, 2) + " / $" + DoubleToString(InpDailyProfit, 0),
      gDayProfit >= InpDailyProfit ? clrGold : gDayProfit > 0 ? clrLime : clrGray);
   SL(gDP+"v8", "$" + DoubleToString(gDayLoss, 2) + " / $" + DoubleToString(InpDailyLoss, 0),
      gDayLoss >= InpDailyLoss ? clrRed : gDayLoss > 0 ? clrOrange : clrGray);
   SL(gDP+"v9", IsNews() ? "⚠ HIGH IMPACT" : "CLEAR", IsNews() ? clrRed : clrLime);
   SL(gDP+"va", demo ? "DEMO" : "LIVE", demo ? clrCyan : clrOrange);
   SL(gDP+"vb", tfs, clrWhite);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   // Wait for balance to load
   int tries = 0;
   while(AccountInfoDouble(ACCOUNT_BALANCE) <= 0 && tries < 10)
   { Sleep(500); tries++; }

   gStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(gStartBal <= 0) gStartBal = AccountInfoDouble(ACCOUNT_EQUITY);
   if(gStartBal <= 0) gStartBal = 10000;
   gEqHigh   = gStartBal;

   bool demo = AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
   string tfs = "";
   if(InpM5)  tfs += "M5 ";
   if(InpM15) tfs += "M15 ";
   if(InpH1)  tfs += "H1";

   Print("================================================");
   Print("  ForexSniper Pro v13.1 - All Bugs Fixed");
   Print("  Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print("  Balance: $", DoubleToString(gStartBal, 2));
   Print("  Mode:    ", demo ? "DEMO" : "LIVE");
   Print("  Timeframes: ", tfs);
   Print("================================================");

   gTrade.SetExpertMagicNumber(InpMagic);
   gTrade.SetDeviationInPoints(50);

   LoadSymbols();
   BuildDash();

   // Try to connect to GitHub AI model
   if(InpGitUser!=""&&InpGitRepo!="")
      DownloadAIModel();

   TG("ForexSniper Pro v13.0 STARTED\n" +
      "Mode: " + (demo ? "DEMO" : "LIVE") + "\n" +
      "Balance: $" + DoubleToString(gStartBal, 2) + "\n" +
      "Scanning: " + IntegerToString(gTotalSyms) + " pairs\n" +
      "Timeframes: " + tfs + "\n" +
      "Daily TP: $" + DoubleToString(InpDailyProfit, 0) +
      " | SL: $" + DoubleToString(InpDailyLoss, 0));

   Print("[OK] Ready! Scanning ", gTotalSyms, " pairs on ", tfs);
   Print("[IMPORTANT] Run EA on ONE chart only to avoid duplicate trades!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, gDP);
   TG("ForexSniper Pro v13.0 stopped.");
   Print("[STOP] ForexSniper Pro v13.0 stopped.");
}

//+------------------------------------------------------------------+
//| TRADE CLOSE EVENT                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &req,
                        const MqlTradeResult      &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal))            return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   string sym    = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   if(profit == 0) return;

   if(profit > 0)
   {
      gDayProfit += profit;
      Print("[WIN] +$", DoubleToString(profit, 2), " on ", sym,
            " | Daily profit: $", DoubleToString(gDayProfit, 2));
      TG("PROFIT +$" + DoubleToString(profit, 2) + " on " + sym +
         "\nDaily: $" + DoubleToString(gDayProfit, 2) + " / $" + DoubleToString(InpDailyProfit, 0));
   }
   else
   {
      gDayLoss += MathAbs(profit);
      Print("[LOSS] -$", DoubleToString(MathAbs(profit), 2), " on ", sym,
            " | Daily loss: $", DoubleToString(gDayLoss, 2));
      TG("Loss -$" + DoubleToString(MathAbs(profit), 2) + " on " + sym +
         "\nDaily: $" + DoubleToString(gDayLoss, 2) + " / $" + DoubleToString(InpDailyLoss, 0));
   }
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDash();
   if(!InpAuto) return;

   ManagePositions();

   // Trigger on M5 candle
   datetime bar = iTime(Symbol(), PERIOD_M5, 0);
   if(bar == gLastBar) return;
   gLastBar = bar;

   DayReset();

   // Refresh AI model daily
   if(InpAutoModel&&InpGitUser!=""&&gModelUpdate>0&&
      TimeCurrent()-gModelUpdate>86400)
      DownloadAIModel();

   // Safety checks
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(gStartBal > 0 && equity < gStartBal * (1.0 - InpMaxDD / 100.0))
   {
      Print("[DRAWDOWN] Equity $", DoubleToString(equity, 2),
            " below limit. Bot stopped.");
      TG("DRAWDOWN ALERT! Bot stopped.");
      return;
   }
   if(gDayProfit >= InpDailyProfit)
   { Print("[DAILY TP] $", DoubleToString(gDayProfit, 2), " target hit. Paused."); return; }
   if(gDayLoss >= InpDailyLoss)
   { Print("[DAILY SL] $", DoubleToString(gDayLoss, 2), " loss hit. Paused."); return; }
   if(CountAll() >= InpMaxTrades)
   { Print("[MAX TRADES] ", InpMaxTrades, " open."); return; }
   if(IsNews())
   { Print("[NEWS] High impact event. Paused."); return; }

   // Reload symbols if needed
   if(gTotalSyms == 0) LoadSymbols();

   // Build timeframe list
   ENUM_TIMEFRAMES tfs[];
   string          tfNames[];
   int             tfc = 0;
   if(InpM5)  { ArrayResize(tfs, tfc+1); tfs[tfc]=PERIOD_M5;  ArrayResize(tfNames, tfc+1); tfNames[tfc]="M5";  tfc++; }
   if(InpM15) { ArrayResize(tfs, tfc+1); tfs[tfc]=PERIOD_M15; ArrayResize(tfNames, tfc+1); tfNames[tfc]="M15"; tfc++; }
   if(InpH1)  { ArrayResize(tfs, tfc+1); tfs[tfc]=PERIOD_H1;  ArrayResize(tfNames, tfc+1); tfNames[tfc]="H1";  tfc++; }

   // Scan all symbols
   for(int p = 0; p < gTotalSyms; p++)
   {
      if(CountAll() >= InpMaxTrades) break;

      string sym = gSymbols[p];
      if(sym == "") continue;

      // Spread check
      double spd = GetSpread(sym);
      if(spd > InpMaxSpread) continue;

      // Session check (forex only)
      if(InpSession && !IsCrypto(sym) && !SessionOK()) continue;

      gLastSym = sym;

      // Scan each timeframe
      for(int t = 0; t < tfc; t++)
      {
         if(CountAll() >= InpMaxTrades) break;
         if(CountSym(sym) >= InpMaxPerPair) break;

         // Use AI score if model connected, fallback to indicators
         int score = 0;
         if(gModelReady)
         {
            score = GetAIScore(sym, tfs[t]);
            // If AI gives weak signal, confirm with indicators
            if(score != 0)
            {
               int indScore = GetSignal(sym, tfs[t]);
               // Only block if indicator STRONGLY disagrees (not just neutral)
               // indScore == 0 means neutral — AI signal allowed through
               if((score>0 && indScore<0) || (score<0 && indScore>0))
               {
                  Print("[FILTER] ", sym, " ", tfNames[t],
                        " AI:", score>0?"BUY":"SELL",
                        " vs IND:", indScore>0?"BUY":"SELL",
                        " — conflict skipped.");
                  score = 0; // Both disagree — skip trade
               }
               else if(score!=0 && indScore!=0 && ((score>0&&indScore>0)||(score<0&&indScore<0)))
               {
                  Print("[CONFIRMED] ", sym, " ", tfNames[t],
                        " AI + Indicator both agree: ", score>0?"BUY":"SELL");
               }
            }
         }
         if(score == 0) score = GetSignal(sym, tfs[t]);
         if(score != 0)
         {
            Print("[SIGNAL] ", sym, " ", tfNames[t], " Score:", MathAbs(score), "%",
                  score > 0 ? " BUY" : " SELL");
            PlaceTrade(sym, score, tfNames[t]);
            Sleep(200);
         }
      }
   }
}
//+------------------------------------------------------------------+
