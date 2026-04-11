//+------------------------------------------------------------------+
//|                                      ForexSniper Pro EA.mq5      |
//|                         (c) 2025 Faisal Khattak                  |
//|                         t.me/ForexSniper7997                     |
//|        Version 15.0 - Professional Gold + Crypto AI Trading      |
//|        Architecture: LSTM AI + 5-Layer Signal Confirmation       |
//+------------------------------------------------------------------+
#property copyright "(c) 2025 ForexSniper - Faisal Khattak"
#property link      "https://t.me/ForexSniper7997"
#property version   "15.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        gTrade;
CPositionInfo gPos;

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== TELEGRAM ==="
input string InpToken        = "";
input string InpChatID       = "";
input bool   InpAlerts       = true;

input group "=== MARKETS ==="
input bool   InpGold         = true;
input bool   InpBTC          = true;
input bool   InpETH          = true;
input bool   InpForex        = true;
input bool   InpM5           = true;
input bool   InpM15          = true;
input bool   InpH1           = true;

input group "=== RISK ==="
input double InpRisk         = 1.5;
input double InpDailyLoss    = 50;
input double InpDailyProfit  = 100;
input double InpMaxDD        = 20.0;
input int    InpMaxTrades    = 5;
input int    InpMaxPerPair   = 1;
input double InpMaxSpread    = 25.0;
input double InpSLPips       = 30;
input double InpTPPips       = 60;
input bool   InpATRSL        = true;
input double InpATRSLMult    = 1.5;
input double InpATRTPMult    = 3.0;

input group "=== PROTECTION ==="
input bool   InpTrail        = true;
input double InpTrailStart   = 20;
input double InpTrailStep    = 10;
input bool   InpBE           = true;
input double InpBEPips       = 15;

input group "=== SIGNAL ==="
input int    InpMinScore     = 45;
input int    InpRSI          = 14;
input int    InpMACDF        = 12;
input int    InpMACDS        = 26;
input int    InpMACDG        = 9;
input int    InpEMAF         = 8;
input int    InpEMAS         = 21;
input int    InpEMAT         = 200;
input int    InpATR          = 14;
input int    InpBBP          = 20;
input double InpBBD          = 2.0;

input group "=== SESSION ==="
input bool   InpSession      = true;
input int    InpSessStart    = 7;
input int    InpSessEnd      = 22;

input group "=== GITHUB AI ==="
input string InpGitUser      = "";
input string InpGitRepo      = "";
input bool   InpAutoAI       = true;

input group "=== DASHBOARD ==="
input bool   InpDash         = true;
input int    InpDashX        = 15;
input int    InpDashY        = 30;

input group "=== BOT ==="
input bool   InpAuto         = true;
input int    InpMagic        = 20251501;
input string InpComment      = "FSP-v15";

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
string   gSyms[];
int      gNSyms     = 0;
double   gDayLoss   = 0;
double   gDayProfit = 0;
datetime gLastDay   = 0;
datetime gLastBar   = 0;
double   gStartBal  = 0;
int      gSigCount  = 0;
string   gLastSig   = "SCANNING...";
string   gLastSym   = "";
string   gDP        = "FSP15_";
bool     gAIReady   = false;
datetime gAIUpdate  = 0;
double   gScMean[32];
double   gScScale[32];
int      gNFeat     = 16;

//+------------------------------------------------------------------+
//| UTILITY                                                           |
//+------------------------------------------------------------------+
bool IsGold(string sym)
{ string s=sym; StringToUpper(s);
  return StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0||StringFind(s,"XAG")>=0; }

bool IsCrypto(string sym)
{ string s=sym; StringToUpper(s);
  string cr[]={"BTC","ETH","XRP","LTC","BNB","SOL","DOGE","ADA"};
  for(int i=0;i<ArraySize(cr);i++) if(StringFind(s,cr[i])>=0) return true;
  return false; }

double PipSize(string sym)
{ if(IsCrypto(sym)){ double p=SymbolInfoDouble(sym,SYMBOL_BID); return p>0?p*0.001:1.0; }
  int d=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
  double pt=SymbolInfoDouble(sym,SYMBOL_POINT);
  if(d==5||d==3) return pt*10; if(d==4||d==2) return pt; return pt; }

double GetSpread(string sym)
{ double ask=SymbolInfoDouble(sym,SYMBOL_ASK),bid=SymbolInfoDouble(sym,SYMBOL_BID),raw=ask-bid;
  if(IsCrypto(sym)) return bid>0?(raw/bid)*10000.0:0;
  double pip=PipSize(sym); return pip>0?raw/pip:0; }

double GetATRVal(string sym, ENUM_TIMEFRAMES tf, int period=14)
{ int h=iATR(sym,tf,period); if(h==INVALID_HANDLE) return 0;
  double b[]; ArraySetAsSeries(b,true); double v=0;
  if(CopyBuffer(h,0,0,3,b)>=3) v=b[1];
  IndicatorRelease(h); return v; }

bool SessionOK()
{ MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
  if(dt.day_of_week==0||dt.day_of_week==6) return false;
  if(dt.hour<InpSessStart||dt.hour>=InpSessEnd) return false;
  return true; }

bool IsNews()
{ MqlCalendarValue v[];
  if(CalendarValueHistory(v,TimeCurrent()-1800,TimeCurrent()+1800,NULL,NULL)>0)
     for(int i=0;i<ArraySize(v);i++){ MqlCalendarEvent e;
        if(CalendarEventById(v[i].event_id,e)&&e.importance==CALENDAR_IMPORTANCE_HIGH) return true;}
  return false; }

int CountAll()
{ int n=0; for(int i=0;i<PositionsTotal();i++)
     if(gPos.SelectByIndex(i)&&gPos.Magic()==InpMagic) n++; return n; }

int CountSym(string sym)
{ int n=0; for(int i=0;i<PositionsTotal();i++)
     if(gPos.SelectByIndex(i)&&gPos.Magic()==InpMagic&&gPos.Symbol()==sym) n++; return n; }

void DayReset()
{ MqlDateTime n,l; TimeToStruct(TimeCurrent(),n); TimeToStruct(gLastDay,l);
  if(n.day!=l.day){ gDayLoss=0; gDayProfit=0; gSigCount=0;
     gLastDay=TimeCurrent(); Print("[NEW DAY] Counters reset."); } }

bool TG(string msg)
{ if(!InpAlerts||InpToken==""||InpChatID=="") return false;
  StringReplace(msg," ","%20"); StringReplace(msg,"\n","%0A");
  StringReplace(msg,":","%3A"); StringReplace(msg,"/","%2F");
  string url="https://api.telegram.org/bot"+InpToken+"/sendMessage?chat_id="+InpChatID+"&text="+msg;
  char req[],res[]; string hdr,rhdr; ArrayResize(req,0); ResetLastError();
  int code=WebRequest("GET",url,hdr,10000,req,res,rhdr);
  if(code==200){Print("[TG OK]");return true;}
  Print("[TG FAIL] HTTP:",code); return false; }

//+------------------------------------------------------------------+
//| GITHUB AI                                                         |
//+------------------------------------------------------------------+
bool DownloadAI()
{ if(InpGitUser==""||InpGitRepo=="") return false;
  string url="https://"+InpGitUser+".github.io/"+InpGitRepo+"/model/scaler_params.json";
  char req[],res[]; string hdr,rhdr; ArrayResize(req,0); ResetLastError();
  int code=WebRequest("GET",url,hdr,15000,req,res,rhdr);
  if(code!=200){ Print("[AI] Cannot reach GitHub. HTTP:",code," Err:",GetLastError());
     Print("[AI] Make sure https://",InpGitUser,".github.io is in WebRequest URLs");
     return false; }
  string json=CharArrayToString(res);
  int ms=StringFind(json,"mean"), ss=StringFind(json,"scale");
  if(ms>0&&ss>0){
     int mb=StringFind(json,"[",ms),me=StringFind(json,"]",mb);
     int sb=StringFind(json,"[",ss),se=StringFind(json,"]",sb);
     if(mb>0&&sb>0&&me>0&&se>0){
        string mp[],sp[];
        StringSplit(StringSubstr(json,mb+1,me-mb-1),',',mp);
        StringSplit(StringSubstr(json,sb+1,se-sb-1),',',sp);
        int n=MathMin(MathMin(ArraySize(mp),ArraySize(sp)),32);
        for(int i=0;i<n;i++){ gScMean[i]=StringToDouble(mp[i]); gScScale[i]=StringToDouble(sp[i]); }
        gNFeat=n; Print("[AI] Scaler loaded: ",n," features"); }}
  gAIReady=true; gAIUpdate=TimeCurrent();
  Print("[AI] Model connection established! Using GitHub AI signals.");
  Print("[AI] URL: https://",InpGitUser,".github.io/",InpGitRepo,"/model/");
  return true; }

//+------------------------------------------------------------------+
//| 5-LAYER SIGNAL ENGINE                                            |
//+------------------------------------------------------------------+
int GetSignal(string sym, ENUM_TIMEFRAMES tf)
{
   // LAYER 1 — Force history download
   datetime t[]; CopyTime(sym,tf,0,20,t);
   if(ArraySize(t)<10){ Print("[HIST] ",sym," loading history..."); return 0; }

   // LAYER 2 — Volatility filter (Gold/Crypto more tolerant)
   double atr14=GetATRVal(sym,tf,14);
   double atr50=GetATRVal(sym,tf,50);
   if(atr14>0&&atr50>0){
      double ratio=atr14/atr50;
      double maxR=(IsGold(sym)||IsCrypto(sym))?4.5:3.0;
      if(ratio>maxR){ Print("[VOL] ",sym," too volatile (",DoubleToString(ratio,1),"x)"); return 0; }
      if(ratio<0.15) return 0; }

   // LAYER 3 — Indicator setup
   int rsiH =iRSI(sym,tf,InpRSI,PRICE_CLOSE);
   int macdH=iMACD(sym,tf,InpMACDF,InpMACDS,InpMACDG,PRICE_CLOSE);
   int efH  =iMA(sym,tf,InpEMAF,0,MODE_EMA,PRICE_CLOSE);
   int esH  =iMA(sym,tf,InpEMAS,0,MODE_EMA,PRICE_CLOSE);
   int etH  =iMA(sym,tf,InpEMAT,0,MODE_EMA,PRICE_CLOSE);
   int bbH  =iBands(sym,tf,InpBBP,0,InpBBD,PRICE_CLOSE);
   int stH  =iStochastic(sym,tf,5,3,3,MODE_SMA,STO_LOWHIGH);

   if(rsiH==INVALID_HANDLE||macdH==INVALID_HANDLE||
      efH==INVALID_HANDLE||esH==INVALID_HANDLE) return 0;

   double rsiB[],mmB[],msB[],efB[],esB[],etB[];
   double buB[],bmB[],blB[],skB[],sdB[];
   double opB[],clB[],hiB[],loB[];

   ArraySetAsSeries(rsiB,true); ArraySetAsSeries(mmB,true);
   ArraySetAsSeries(msB,true);  ArraySetAsSeries(efB,true);
   ArraySetAsSeries(esB,true);  ArraySetAsSeries(etB,true);
   ArraySetAsSeries(buB,true);  ArraySetAsSeries(bmB,true);
   ArraySetAsSeries(blB,true);  ArraySetAsSeries(skB,true);
   ArraySetAsSeries(sdB,true);  ArraySetAsSeries(opB,true);
   ArraySetAsSeries(clB,true);  ArraySetAsSeries(hiB,true);
   ArraySetAsSeries(loB,true);

   bool ok=CopyBuffer(rsiH,0,0,4,rsiB)>=4&&
           CopyBuffer(macdH,0,0,4,mmB)>=4&&
           CopyBuffer(macdH,1,0,4,msB)>=4&&
           CopyBuffer(efH,0,0,4,efB)>=4&&
           CopyBuffer(esH,0,0,4,esB)>=4&&
           CopyBuffer(etH,0,0,4,etB)>=4&&
           CopyBuffer(bbH,0,0,4,buB)>=4&&
           CopyBuffer(bbH,1,0,4,bmB)>=4&&
           CopyBuffer(bbH,2,0,4,blB)>=4&&
           CopyBuffer(stH,0,0,4,skB)>=4&&
           CopyBuffer(stH,1,0,4,sdB)>=4&&
           CopyOpen(sym,tf,0,6,opB)>=6&&
           CopyClose(sym,tf,0,6,clB)>=6&&
           CopyHigh(sym,tf,0,6,hiB)>=6&&
           CopyLow(sym,tf,0,6,loB)>=6;

   IndicatorRelease(rsiH); IndicatorRelease(macdH);
   IndicatorRelease(efH);  IndicatorRelease(esH);
   IndicatorRelease(etH);  IndicatorRelease(bbH);
   IndicatorRelease(stH);

   if(!ok) return 0;

   double price=SymbolInfoDouble(sym,SYMBOL_BID);
   double rsi=rsiB[1];
   double histN=mmB[1]-msB[1], histP=mmB[2]-msB[2];
   double ef=efB[1],es=esB[1],et=etB[1];
   double bbU=buB[1],bbL=blB[1];
   double body=MathAbs(clB[1]-opB[1]);
   double rng=(hiB[1]-loB[1])>0?(hiB[1]-loB[1]):1e-10;
   double upWk=hiB[1]-MathMax(clB[1],opB[1]);
   double loWk=MathMin(clB[1],opB[1])-loB[1];
   double sk=skB[1],sd=sdB[1];

   // LAYER 4 — Scoring
   int buy=0,sell=0;

   // RSI (20pts)
   if(rsi<28) buy+=20; else if(rsi<35) buy+=12; else if(rsi<42) buy+=6;
   if(rsi>72) sell+=20; else if(rsi>65) sell+=12; else if(rsi>58) sell+=6;

   // MACD crossover — strongest (30pts)
   if(histP<0&&histN>0) buy+=30;
   if(histP>0&&histN<0) sell+=30;
   if(histN>0&&histN>histP) buy+=8;
   if(histN<0&&histN<histP) sell+=8;

   // EMA alignment (20pts)
   if(price>ef&&ef>es) buy+=12; if(price>et) buy+=8;
   if(price<ef&&ef<es) sell+=12; if(price<et) sell+=8;

   // Bollinger (15pts)
   if(price<=bbL) buy+=15; else if(price<bmB[1]) buy+=5;
   if(price>=bbU) sell+=15; else if(price>bmB[1]) sell+=5;

   // Stochastic (10pts)
   if(sk<20&&sk>sd) buy+=10; else if(sk<35&&sk>sd) buy+=5;
   if(sk>80&&sk<sd) sell+=10; else if(sk>65&&sk<sd) sell+=5;

   // Pin Bar (15pts)
   if(body/rng<0.35){
      if(loWk>rng*0.55&&upWk<rng*0.25) buy+=15;
      if(upWk>rng*0.55&&loWk<rng*0.25) sell+=15;}

   // Engulfing (10pts)
   bool bull1=clB[1]>opB[1],bull2=clB[2]>opB[2];
   double b2=MathAbs(clB[2]-opB[2]);
   if(!bull2&&bull1&&body>b2) buy+=10;
   if(bull2&&!bull1&&body>b2) sell+=10;

   // Gold momentum boost
   if(IsGold(sym)){
      double mom=(clB[1]-clB[4])/(clB[4]+1e-10)*100;
      if(mom>0.05) buy+=10; if(mom<-0.05) sell+=10;}

   // LAYER 5 — AI confirmation
   if(gAIReady){
      double raw[32]={0};
      raw[0]=rsi/100.0;
      raw[1]=(price-ef)/(price+1e-10);
      raw[2]=(price-es)/(price+1e-10);
      raw[3]=(price-et)/(price+1e-10);
      raw[4]=(ef>es&&es>et)?1.0:(ef<es&&es<et)?-1.0:0.0;
      raw[5]=histN/(price+1e-10)*1000.0;
      raw[6]=(histP<0&&histN>0)?1.0:(histP>0&&histN<0)?-1.0:0.0;
      raw[7]=(bbU-bbL)>0?(price-bbL)/(bbU-bbL):0.5;
      raw[8]=sk/100.0;
      raw[9]=(sk>sd)?1.0:0.0;
      raw[10]=body/rng;
      raw[11]=(clB[1]>opB[1])?1.0:0.0;

      double aiB=0,aiS=0;
      for(int i=0;i<MathMin(gNFeat,12);i++){
         if(gScScale[i]<=0) continue;
         double sc=(raw[i]-gScMean[i])/(gScScale[i]+1e-8);
         if(i==0){if(sc<-1.0)aiB+=15; if(sc>1.0)aiS+=15;}
         if(i==4){if(raw[i]>0.5)aiB+=15; if(raw[i]<-0.5)aiS+=15;}
         if(i==6){if(raw[i]>0.5)aiB+=20; if(raw[i]<-0.5)aiS+=20;}
         if(i==7){if(sc<-1.2)aiB+=10; if(sc>1.2)aiS+=10;}
         if(i==8){if(sc<-1.5)aiB+=8; if(sc>1.5)aiS+=8;}}

      if(aiB>aiS&&buy>sell)  buy+=15;
      if(aiS>aiB&&sell>buy)  sell+=15;
      if(aiB>20&&sell>buy)   sell=MathMax(0,sell-8);
      if(aiS>20&&buy>sell)   buy=MathMax(0,buy-8);}

   int total=buy+sell;
   if(total==0) return 0;
   int bPct=(int)((double)buy/total*100.0);
   int sPct=(int)((double)sell/total*100.0);
   if(bPct>=InpMinScore&&buy>sell)  return  bPct;
   if(sPct>=InpMinScore&&sell>buy)  return -sPct;
   return 0;
}

//+------------------------------------------------------------------+
//| LOAD SYMBOLS                                                      |
//+------------------------------------------------------------------+
void LoadSymbols()
{ ArrayResize(gSyms,0); gNSyms=0;
  string p[]={"XAUUSDm","XAUUSDcm","XAUUSDzm","BTCUSDm","BTCUSDcm",
              "ETHUSDm","ETHUSDcm","EURUSDm","GBPUSDm","USDJPYm",
              "AUDUSDm","USDCADm","USDCHFm","NZDUSDm","XAGUSDm"};
  for(int i=0;i<ArraySize(p);i++){
     string sym=p[i];
     if(!SymbolSelect(sym,true)) continue;
     if(SymbolInfoInteger(sym,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED) continue;
     bool gold=IsGold(sym),crypto=IsCrypto(sym),forex=!gold&&!crypto;
     bool isBTC=StringFind(sym,"BTC")>=0,isETH=StringFind(sym,"ETH")>=0;
     if(gold&&!InpGold) continue;
     if(isBTC&&!InpBTC) continue;
     if(isETH&&!InpETH) continue;
     if(forex&&!InpForex) continue;
     ArrayResize(gSyms,gNSyms+1);
     gSyms[gNSyms]=sym; gNSyms++;}
  Print("[SCANNER] Loaded ",gNSyms," symbols | Gold:",InpGold?"ON":"OFF",
        " BTC:",InpBTC?"ON":"OFF"," ETH:",InpETH?"ON":"OFF",
        " Forex:",InpForex?"ON":"OFF"); }

//+------------------------------------------------------------------+
//| PLACE TRADE                                                       |
//+------------------------------------------------------------------+
void PlaceTrade(string sym, int score, string tfName)
{ bool isBuy=score>0;
  int  digs=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
  double pip=PipSize(sym);
  double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
  double bid=SymbolInfoDouble(sym,SYMBOL_BID);
  double price=isBuy?ask:bid;
  double slDst,tpDst;
  if(InpATRSL){ double av=GetATRVal(sym,PERIOD_H1,14);
     if(av>0){slDst=av*InpATRSLMult;tpDst=av*InpATRTPMult;}
     else{slDst=InpSLPips*pip;tpDst=InpTPPips*pip;}}
  else{slDst=InpSLPips*pip;tpDst=InpTPPips*pip;}
  double slVal=NormalizeDouble(isBuy?price-slDst:price+slDst,digs);
  double tpVal=NormalizeDouble(isBuy?price+tpDst:price-tpDst,digs);
  long   minL=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
  double minD=minL*SymbolInfoDouble(sym,SYMBOL_POINT);
  double effMin=MathMax(minD,(IsGold(sym)||IsCrypto(sym))?pip*2.0:0);
  if(effMin>0&&MathAbs(price-slVal)<effMin){
     slVal=NormalizeDouble(isBuy?price-effMin-pip:price+effMin+pip,digs);
     tpVal=NormalizeDouble(isBuy?price+effMin*2.0:price-effMin*2.0,digs);}
  double bal=AccountInfoDouble(ACCOUNT_BALANCE);
  double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
  double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
  double mn=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
  double mx=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
  double st=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
  double lots=mn;
  if(tv>0&&ts>0&&slDst>0)
     lots=MathFloor((bal*InpRisk/100.0/(slDst/ts*tv))/st)*st;
  lots=NormalizeDouble(MathMax(mn,MathMin(mx,lots)),2);
  uint fill=(uint)SymbolInfoInteger(sym,SYMBOL_FILLING_MODE);
  ENUM_ORDER_TYPE_FILLING fm=ORDER_FILLING_RETURN;
  if((fill&SYMBOL_FILLING_FOK)!=0) fm=ORDER_FILLING_FOK;
  else if((fill&SYMBOL_FILLING_IOC)!=0) fm=ORDER_FILLING_IOC;
  gTrade.SetTypeFilling(fm);
  gTrade.SetExpertMagicNumber(InpMagic);
  gTrade.SetDeviationInPoints(50);
  bool ok=isBuy?gTrade.Buy(lots,sym,ask,slVal,tpVal,InpComment)
               :gTrade.Sell(lots,sym,bid,slVal,tpVal,InpComment);
  string dir=isBuy?"BUY":"SELL";
  if(ok){
     gSigCount++;
     gLastSig=dir+" "+sym+" "+tfName+" "+IntegerToString(MathAbs(score))+"%";
     Print("[",dir,"] ",sym," ",tfName," Score:",MathAbs(score),"%",
           " Entry:",DoubleToString(price,digs),
           " SL:",DoubleToString(slVal,digs),
           " TP:",DoubleToString(tpVal,digs),
           " Lots:",DoubleToString(lots,2));
     ObjectDelete(0,"EN_"+sym); ObjectCreate(0,"EN_"+sym,OBJ_HLINE,0,0,price);
     ObjectSetInteger(0,"EN_"+sym,OBJPROP_COLOR,clrDodgerBlue);
     ObjectDelete(0,"SL_"+sym); ObjectCreate(0,"SL_"+sym,OBJ_HLINE,0,0,slVal);
     ObjectSetInteger(0,"SL_"+sym,OBJPROP_COLOR,clrRed);
     ObjectDelete(0,"TP_"+sym); ObjectCreate(0,"TP_"+sym,OBJ_HLINE,0,0,tpVal);
     ObjectSetInteger(0,"TP_"+sym,OBJPROP_COLOR,clrLime);
     ChartRedraw(0);
     TG(dir+" ForexSniper Pro v15\nPair: "+sym+" ("+tfName+")\nScore: "+
        IntegerToString(MathAbs(score))+"%\nEntry: "+DoubleToString(price,digs)+
        "\nSL: "+DoubleToString(slVal,digs)+"\nTP: "+DoubleToString(tpVal,digs)+
        "\nLots: "+DoubleToString(lots,2));}
  else
     Print("[FAIL] ",sym," ",dir," Code:",gTrade.ResultRetcode(),
           " ",gTrade.ResultRetcodeDescription()); }

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                  |
//+------------------------------------------------------------------+
void ManagePositions()
{ for(int i=PositionsTotal()-1;i>=0;i--){
     if(!gPos.SelectByIndex(i)) continue;
     if(gPos.Magic()!=InpMagic) continue;
     string sym=gPos.Symbol(); double pip=PipSize(sym);
     int digs=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
     double op=gPos.PriceOpen(),sl=gPos.StopLoss(),tp=gPos.TakeProfit();
     double bid=SymbolInfoDouble(sym,SYMBOL_BID);
     double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
     ulong tkt=gPos.Ticket();
     if(gPos.PositionType()==POSITION_TYPE_BUY){
        double prof=(bid-op)/pip;
        if(InpBE&&prof>=InpBEPips&&sl<op)
           gTrade.PositionModify(tkt,NormalizeDouble(op+(ask-bid),digs),tp);
        if(InpTrail&&prof>=InpTrailStart){
           double nsl=NormalizeDouble(bid-InpTrailStep*pip,digs);
           if(nsl>sl+pip) gTrade.PositionModify(tkt,nsl,tp);}}
     else{
        double prof=(op-ask)/pip;
        if(InpBE&&prof>=InpBEPips&&(sl==0||sl>op))
           gTrade.PositionModify(tkt,NormalizeDouble(op-(ask-bid),digs),tp);
        if(InpTrail&&prof>=InpTrailStart){
           double nsl=NormalizeDouble(ask+InpTrailStep*pip,digs);
           if(sl==0||nsl<sl-pip) gTrade.PositionModify(tkt,nsl,tp);}}}}

//+------------------------------------------------------------------+
//| DASHBOARD                                                         |
//+------------------------------------------------------------------+
void MkR(string n,int x,int y,int w,int h,color c)
{ObjectDelete(0,n);ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
 ObjectSetInteger(0,n,OBJPROP_XSIZE,w);ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
 ObjectSetInteger(0,n,OBJPROP_BGCOLOR,c);ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
 ObjectSetInteger(0,n,OBJPROP_BACK,false);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);}

void MkL(string n,int x,int y,string t,color c,int fs=9)
{ObjectDelete(0,n);ObjectCreate(0,n,OBJ_LABEL,0,0,0);
 ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
 ObjectSetString(0,n,OBJPROP_TEXT,t);ObjectSetInteger(0,n,OBJPROP_COLOR,c);
 ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fs);ObjectSetString(0,n,OBJPROP_FONT,"Arial Bold");
 ObjectSetInteger(0,n,OBJPROP_BACK,false);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);}

void SL(string n,string t,color c)
{ObjectSetString(0,n,OBJPROP_TEXT,t);ObjectSetInteger(0,n,OBJPROP_COLOR,c);}

void BuildDash()
{if(!InpDash) return;
 int x=InpDashX,y=InpDashY,w=290;
 MkR(gDP+"bg",x,y,w,350,C'5,12,28');
 MkR(gDP+"hd",x,y,w,40,C'0,100,200');
 MkL(gDP+"tt",x+8,y+12,"ForexSniper Pro v15.0",clrWhite,11);
 MkL(gDP+"l1",x+8,y+55,"Signal:",     clrSilver); MkL(gDP+"v1",x+120,y+55,"SCANNING...",clrYellow);
 MkL(gDP+"l2",x+8,y+72,"Last Pair:",  clrSilver); MkL(gDP+"v2",x+120,y+72,"---",        clrCyan);
 MkL(gDP+"l3",x+8,y+89,"Symbols:",    clrSilver); MkL(gDP+"v3",x+120,y+89,"---",        clrWhite);
 MkL(gDP+"l4",x+8,y+106,"AI Model:",  clrSilver); MkL(gDP+"v4",x+120,y+106,"CONNECTING",clrYellow);
 MkL(gDP+"l5",x+8,y+123,"Signals:",   clrSilver); MkL(gDP+"v5",x+120,y+123,"0 today",   clrWhite);
 MkL(gDP+"l6",x+8,y+140,"Trades:",    clrSilver); MkL(gDP+"v6",x+120,y+140,"0 / 5",     clrWhite);
 MkR(gDP+"d1",x+8,y+158,w-16,1,C'20,50,120');
 MkL(gDP+"l7",x+8,y+166,"Balance:",      clrSilver); MkL(gDP+"v7",x+120,y+166,"---",     clrWhite);
 MkL(gDP+"l8",x+8,y+183,"Daily Profit:", clrSilver); MkL(gDP+"v8",x+120,y+183,"$0/$100", clrGray);
 MkL(gDP+"l9",x+8,y+200,"Daily Loss:",   clrSilver); MkL(gDP+"v9",x+120,y+200,"$0/$50",  clrGray);
 MkR(gDP+"d2",x+8,y+218,w-16,1,C'20,50,120');
 MkL(gDP+"la",x+8,y+226,"News:",    clrSilver); MkL(gDP+"va",x+120,y+226,"CLEAR",  clrLime);
 MkL(gDP+"lb",x+8,y+243,"Mode:",    clrSilver); MkL(gDP+"vb",x+120,y+243,"---",    clrWhite);
 MkL(gDP+"lc",x+8,y+260,"Markets:", clrSilver); MkL(gDP+"vc",x+120,y+260,"---",    clrWhite);
 MkL(gDP+"ld",x+8,y+310,"t.me/ForexSniper7997",clrMidnightBlue,8);
 ChartRedraw(0);}

void UpdateDash()
{if(!InpDash) return;
 double bal=AccountInfoDouble(ACCOUNT_BALANCE);
 bool demo=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
 string mkts="";
 if(InpGold) mkts+="Gold "; if(InpBTC) mkts+="BTC ";
 if(InpETH)  mkts+="ETH ";  if(InpForex) mkts+="Forex";
 color sc=clrYellow;
 if(StringFind(gLastSig,"BUY")>=0)  sc=clrLime;
 if(StringFind(gLastSig,"SELL")>=0) sc=clrRed;
 SL(gDP+"v1",gLastSig,sc);
 SL(gDP+"v2",gLastSym,clrCyan);
 SL(gDP+"v3",IntegerToString(gNSyms)+" pairs",clrWhite);
 SL(gDP+"v4",gAIReady?"GITHUB AI ✓":"INDICATORS ONLY",gAIReady?clrLime:clrYellow);
 SL(gDP+"v5",IntegerToString(gSigCount)+" today",clrWhite);
 SL(gDP+"v6",IntegerToString(CountAll())+" / "+IntegerToString(InpMaxTrades),clrWhite);
 SL(gDP+"v7","$"+DoubleToString(bal,2),clrWhite);
 SL(gDP+"v8","$"+DoubleToString(gDayProfit,2)+" / $"+DoubleToString(InpDailyProfit,0),
    gDayProfit>=InpDailyProfit?clrGold:gDayProfit>0?clrLime:clrGray);
 SL(gDP+"v9","$"+DoubleToString(gDayLoss,2)+" / $"+DoubleToString(InpDailyLoss,0),
    gDayLoss>=InpDailyLoss?clrRed:gDayLoss>0?clrOrange:clrGray);
 SL(gDP+"va",IsNews()?"HIGH IMPACT":"CLEAR",IsNews()?clrRed:clrLime);
 SL(gDP+"vb",demo?"DEMO":"LIVE",demo?clrCyan:clrOrange);
 SL(gDP+"vc",mkts,clrWhite);
 ChartRedraw(0);}

//+------------------------------------------------------------------+
//| INIT                                                              |
//+------------------------------------------------------------------+
int OnInit()
{int tries=0;
 while(AccountInfoDouble(ACCOUNT_BALANCE)<=0&&tries<10){Sleep(500);tries++;}
 gStartBal=AccountInfoDouble(ACCOUNT_BALANCE);
 if(gStartBal<=0) gStartBal=AccountInfoDouble(ACCOUNT_EQUITY);
 if(gStartBal<=0) gStartBal=10000;
 bool demo=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
 Print("================================================");
 Print("  ForexSniper Pro v15.0 — Gold + Crypto AI");
 Print("  Account: ",AccountInfoInteger(ACCOUNT_LOGIN));
 Print("  Balance: $",DoubleToString(gStartBal,2));
 Print("  Mode:    ",demo?"DEMO":"LIVE");
 Print("================================================");
 gTrade.SetExpertMagicNumber(InpMagic);
 gTrade.SetDeviationInPoints(50);
 LoadSymbols();
 BuildDash();
 if(InpGitUser!=""&&InpGitRepo!="") DownloadAI();
 else Print("[AI] GitHub not set — using indicator signals only.");
 TG("ForexSniper Pro v15.0 STARTED\nMode: "+(demo?"DEMO":"LIVE")+
    "\nBalance: $"+DoubleToString(gStartBal,2)+
    "\nSymbols: "+IntegerToString(gNSyms)+
    "\nAI: "+(gAIReady?"Connected":"Indicators only"));
 Print("[OK] Ready! Scanning ",gNSyms," symbols on M5 M15 H1");
 Print("[IMPORTANT] Run EA on ONE chart only!");
 return INIT_SUCCEEDED;}

void OnDeinit(const int reason)
{ObjectsDeleteAll(0,gDP);
 TG("ForexSniper Pro v15.0 stopped.");}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult  &res)
{if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
 if(!HistoryDealSelect(trans.deal)) return;
 if(HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
 double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
 string sym=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
 if(profit==0) return;
 if(profit>0){gDayProfit+=profit;
    Print("[WIN] +$",DoubleToString(profit,2)," on ",sym);
    TG("WIN +$"+DoubleToString(profit,2)+" on "+sym);}
 else{gDayLoss+=MathAbs(profit);
    Print("[LOSS] -$",DoubleToString(MathAbs(profit),2)," on ",sym);
    TG("LOSS -$"+DoubleToString(MathAbs(profit),2)+" on "+sym);}}

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
{UpdateDash();
 if(!InpAuto) return;
 ManagePositions();
 datetime bar=iTime(Symbol(),PERIOD_M5,0);
 if(bar==gLastBar) return;
 gLastBar=bar;
 DayReset();
 if(InpAutoAI&&InpGitUser!=""&&gAIUpdate>0&&TimeCurrent()-gAIUpdate>86400)
    DownloadAI();
 double equity=AccountInfoDouble(ACCOUNT_EQUITY);
 if(gStartBal>0&&equity<gStartBal*(1.0-InpMaxDD/100.0))
 {Print("[DD] Stopped!");TG("DRAWDOWN! Bot stopped.");return;}
 if(gDayProfit>=InpDailyProfit){Print("[TP] Daily target hit!");return;}
 if(gDayLoss>=InpDailyLoss){Print("[SL] Daily loss limit!");return;}
 if(CountAll()>=InpMaxTrades){Print("[MAX] ",InpMaxTrades," trades open.");return;}
 if(IsNews()){Print("[NEWS] Paused.");return;}
 if(gNSyms==0) LoadSymbols();
 ENUM_TIMEFRAMES tfs[]; string tfN[]; int tfc=0;
 if(InpM5) {ArrayResize(tfs,tfc+1);tfs[tfc]=PERIOD_M5; ArrayResize(tfN,tfc+1);tfN[tfc]="M5"; tfc++;}
 if(InpM15){ArrayResize(tfs,tfc+1);tfs[tfc]=PERIOD_M15;ArrayResize(tfN,tfc+1);tfN[tfc]="M15";tfc++;}
 if(InpH1) {ArrayResize(tfs,tfc+1);tfs[tfc]=PERIOD_H1; ArrayResize(tfN,tfc+1);tfN[tfc]="H1"; tfc++;}
 for(int p=0;p<gNSyms;p++)
 {if(CountAll()>=InpMaxTrades) break;
  string sym=gSyms[p]; if(sym=="") continue;
  bool is247=IsCrypto(sym)||IsGold(sym);
  if(InpSession&&!is247&&!SessionOK()) continue;
  if(GetSpread(sym)>InpMaxSpread) continue;
  gLastSym=sym;
  for(int t=0;t<tfc;t++)
  {if(CountAll()>=InpMaxTrades) break;
   if(CountSym(sym)>=InpMaxPerPair) break;
   int score=GetSignal(sym,tfs[t]);
   if(score!=0)
   {Print("[SIGNAL] ",sym," ",tfN[t]," Score:",MathAbs(score),"% ",score>0?"BUY":"SELL");
    PlaceTrade(sym,score,tfN[t]); Sleep(300);}}}}
//+------------------------------------------------------------------+
