//+------------------------------------------------------------------+
//|                                                 SignalEngine.mqh |
//|   Higher timeframe bias + entry timeframe pullback trigger.      |
//|   Every decision is taken on CLOSED bars only (index >= 1).      |
//+------------------------------------------------------------------+
#ifndef US100_SIGNALENGINE_MQH
#define US100_SIGNALENGINE_MQH

#include "Defs.mqh"

//+------------------------------------------------------------------+
class CSignalEngine
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_biasTF;
   ENUM_TIMEFRAMES   m_entryTF;

   int               m_hBiasEma;
   int               m_hFastEma;
   int               m_hSlowEma;
   int               m_hAtr;

   int               m_biasSlopeBars;
   int               m_pullbackLookback;
   int               m_swingBars;
   bool              m_requireTrendAlign;

   int               m_entryBars;      // bars to copy on the entry TF
   int               m_biasBars;       // bars to copy on the bias TF

   double            m_biasEma[];
   double            m_fastEma[];
   double            m_slowEma[];
   double            m_atrBuf[];
   double            m_biasClose[];
   MqlRates          m_rates[];

   bool              m_dataOk;

public:
                     CSignalEngine();
   bool              Init(const string sym,
                          const ENUM_TIMEFRAMES biasTF,const int biasEmaPeriod,const int biasSlopeBars,
                          const ENUM_TIMEFRAMES entryTF,const int fastEmaPeriod,const int slowEmaPeriod,
                          const int atrPeriod,const int pullbackLookback,const int swingBars,
                          const bool requireTrendAlign);
   void              Deinit();
   bool              Update();
   bool              DataOk() const { return(m_dataOk); }

   ENUM_BIAS         Bias() const;
   double            Atr()  const { return(m_dataOk ? m_atrBuf[1] : 0.0); }
   double            FastEma() const { return(m_dataOk ? m_fastEma[1] : 0.0); }
   datetime          LastClosedBarTime() const { return(m_dataOk ? m_rates[1].time : 0); }

   bool              BuildSignal(SSignal &sig) const;

private:
   double            SwingLow(const int bars)  const;
   double            SwingHigh(const int bars) const;
  };

//+------------------------------------------------------------------+
CSignalEngine::CSignalEngine()
  {
   m_symbol="";
   m_biasTF=PERIOD_H1;
   m_entryTF=PERIOD_M5;
   m_hBiasEma=INVALID_HANDLE;
   m_hFastEma=INVALID_HANDLE;
   m_hSlowEma=INVALID_HANDLE;
   m_hAtr=INVALID_HANDLE;
   m_biasSlopeBars=3;
   m_pullbackLookback=6;
   m_swingBars=5;
   m_requireTrendAlign=true;
   m_entryBars=40;
   m_biasBars=20;
   m_dataOk=false;
  }

//+------------------------------------------------------------------+
bool CSignalEngine::Init(const string sym,
                         const ENUM_TIMEFRAMES biasTF,const int biasEmaPeriod,const int biasSlopeBars,
                         const ENUM_TIMEFRAMES entryTF,const int fastEmaPeriod,const int slowEmaPeriod,
                         const int atrPeriod,const int pullbackLookback,const int swingBars,
                         const bool requireTrendAlign)
  {
   m_symbol            = sym;
   m_biasTF            = biasTF;
   m_entryTF           = entryTF;
   m_biasSlopeBars     = (int)MathMax(1,biasSlopeBars);
   m_pullbackLookback  = (int)MathMax(1,pullbackLookback);
   m_swingBars         = (int)MathMax(2,swingBars);
   m_requireTrendAlign = requireTrendAlign;

   m_hBiasEma = iMA(sym,biasTF,(int)MathMax(2,biasEmaPeriod),0,MODE_EMA,PRICE_CLOSE);
   m_hFastEma = iMA(sym,entryTF,(int)MathMax(2,fastEmaPeriod),0,MODE_EMA,PRICE_CLOSE);
   m_hSlowEma = iMA(sym,entryTF,(int)MathMax(2,slowEmaPeriod),0,MODE_EMA,PRICE_CLOSE);
   m_hAtr     = iATR(sym,entryTF,(int)MathMax(2,atrPeriod));

   if(m_hBiasEma==INVALID_HANDLE || m_hFastEma==INVALID_HANDLE ||
      m_hSlowEma==INVALID_HANDLE || m_hAtr==INVALID_HANDLE)
     {
      PrintFormat("[signal] indicator creation failed, err=%d",GetLastError());
      return(false);
     }

   //--- how deep we need to look back, plus headroom
   m_entryBars = (int)MathMax(m_pullbackLookback,m_swingBars)+8;
   m_biasBars  = m_biasSlopeBars+8;

   ArraySetAsSeries(m_biasEma,true);
   ArraySetAsSeries(m_fastEma,true);
   ArraySetAsSeries(m_slowEma,true);
   ArraySetAsSeries(m_atrBuf,true);
   ArraySetAsSeries(m_biasClose,true);
   ArraySetAsSeries(m_rates,true);

   return(true);
  }

//+------------------------------------------------------------------+
void CSignalEngine::Deinit()
  {
   if(m_hBiasEma!=INVALID_HANDLE) IndicatorRelease(m_hBiasEma);
   if(m_hFastEma!=INVALID_HANDLE) IndicatorRelease(m_hFastEma);
   if(m_hSlowEma!=INVALID_HANDLE) IndicatorRelease(m_hSlowEma);
   if(m_hAtr    !=INVALID_HANDLE) IndicatorRelease(m_hAtr);
   m_hBiasEma=m_hFastEma=m_hSlowEma=m_hAtr=INVALID_HANDLE;
   m_dataOk=false;
  }

//+------------------------------------------------------------------+
//| Pull every series we need. Index 0 is the forming bar, index 1   |
//| the last closed bar.                                             |
//+------------------------------------------------------------------+
bool CSignalEngine::Update()
  {
   m_dataOk=false;

   if(CopyRates(m_symbol,m_entryTF,0,m_entryBars,m_rates)<m_entryBars)
      return(false);
   if(CopyBuffer(m_hFastEma,0,0,m_entryBars,m_fastEma)<m_entryBars)
      return(false);
   if(CopyBuffer(m_hSlowEma,0,0,m_entryBars,m_slowEma)<m_entryBars)
      return(false);
   if(CopyBuffer(m_hAtr,0,0,m_entryBars,m_atrBuf)<m_entryBars)
      return(false);
   if(CopyBuffer(m_hBiasEma,0,0,m_biasBars,m_biasEma)<m_biasBars)
      return(false);
   if(CopyClose(m_symbol,m_biasTF,0,m_biasBars,m_biasClose)<m_biasBars)
      return(false);

   //--- copy calls may reset the indexing direction on dynamic arrays
   ArraySetAsSeries(m_rates,true);
   ArraySetAsSeries(m_fastEma,true);
   ArraySetAsSeries(m_slowEma,true);
   ArraySetAsSeries(m_atrBuf,true);
   ArraySetAsSeries(m_biasEma,true);
   ArraySetAsSeries(m_biasClose,true);

   if(m_atrBuf[1]<=0.0)
      return(false);

   m_dataOk=true;
   return(true);
  }

//+------------------------------------------------------------------+
//| Bias: price on the right side of the HTF EMA, and that EMA must  |
//| actually be sloping in the same direction.                        |
//+------------------------------------------------------------------+
ENUM_BIAS CSignalEngine::Bias() const
  {
   if(!m_dataOk)
      return(BIAS_NONE);

   double emaNow  = m_biasEma[1];
   double emaPast = m_biasEma[1+m_biasSlopeBars];
   double close   = m_biasClose[1];

   if(close>emaNow && emaNow>emaPast)
      return(BIAS_LONG);
   if(close<emaNow && emaNow<emaPast)
      return(BIAS_SHORT);

   return(BIAS_NONE);
  }

//+------------------------------------------------------------------+
double CSignalEngine::SwingLow(const int bars) const
  {
   double lo=m_rates[1].low;
   for(int i=2;i<=bars;i++)
      if(m_rates[i].low<lo)
         lo=m_rates[i].low;
   return(lo);
  }

//+------------------------------------------------------------------+
double CSignalEngine::SwingHigh(const int bars) const
  {
   double hi=m_rates[1].high;
   for(int i=2;i<=bars;i++)
      if(m_rates[i].high>hi)
         hi=m_rates[i].high;
   return(hi);
  }

//+------------------------------------------------------------------+
//| Entry rules, long side (short side mirrored):                    |
//|  1. HTF bias is long                                             |
//|  2. optional: last closed bar is above the slow EMA (M5 trend)   |
//|  3. price dipped into the value zone (low <= fast EMA) within    |
//|     the lookback window -> that is the pullback                  |
//|  4. the trigger bar closes bullish, back above the fast EMA, and |
//|     above the previous bar high -> momentum is resuming          |
//+------------------------------------------------------------------+
bool CSignalEngine::BuildSignal(SSignal &sig) const
  {
   sig.Reset();

   if(!m_dataOk)
      return(false);

   ENUM_BIAS bias=Bias();
   if(bias==BIAS_NONE)
      return(false);

   bool isLong=(bias==BIAS_LONG);

   //--- 2. entry timeframe trend alignment
   if(m_requireTrendAlign)
     {
      if(isLong  && m_rates[1].close<=m_slowEma[1])
         return(false);
      if(!isLong && m_rates[1].close>=m_slowEma[1])
         return(false);
     }

   //--- 3. pullback into the value zone
   bool touched=false;
   for(int i=1;i<=m_pullbackLookback;i++)
     {
      if(isLong && m_rates[i].low<=m_fastEma[i])
        {
         touched=true;
         break;
        }
      if(!isLong && m_rates[i].high>=m_fastEma[i])
        {
         touched=true;
         break;
        }
     }
   if(!touched)
      return(false);

   //--- 4. momentum trigger on the last closed bar
   if(isLong)
     {
      if(m_rates[1].close<=m_rates[1].open)      return(false);
      if(m_rates[1].close<=m_fastEma[1])         return(false);
      if(m_rates[1].close<=m_rates[2].high)      return(false);
      sig.dir      = SIG_BUY;
      sig.swingRef = SwingLow(m_swingBars);
     }
   else
     {
      if(m_rates[1].close>=m_rates[1].open)      return(false);
      if(m_rates[1].close>=m_fastEma[1])         return(false);
      if(m_rates[1].close>=m_rates[2].low)       return(false);
      sig.dir      = SIG_SELL;
      sig.swingRef = SwingHigh(m_swingBars);
     }

   sig.atr     = m_atrBuf[1];
   sig.emaFast = m_fastEma[1];
   sig.barTime = m_rates[1].time;
   return(true);
  }

#endif // US100_SIGNALENGINE_MQH
