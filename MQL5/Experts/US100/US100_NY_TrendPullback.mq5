//+------------------------------------------------------------------+
//|                                   US100_NY_TrendPullback.mq5     |
//|                                                                  |
//|  Intraday trend pullback system for the NASDAQ 100 CFD (US100).  |
//|                                                                  |
//|  Idea in one line: trade only during the New York cash session,  |
//|  only in the direction of the hourly trend, and only on the      |
//|  first sign that a shallow pullback has been rejected.           |
//|                                                                  |
//|  See docs/STRATEGY.md for the full rule set and the reasoning.   |
//+------------------------------------------------------------------+
#property copyright "US100 project"
#property link      "https://github.com/oraclerevolution/us100"
#property version   "1.00"
#property description "US100 NY session trend pullback EA with ATR risk sizing and daily guardrails."

#include <Trade\Trade.mqh>

#include <US100/Defs.mqh>
#include <US100/TimeZones.mqh>
#include <US100/SymbolContext.mqh>
#include <US100/SessionFilter.mqh>
#include <US100/SignalEngine.mqh>
#include <US100/RiskManager.mqh>
#include <US100/PositionManager.mqh>
#include <US100/Guardrails.mqh>
#include <US100/Dashboard.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== Identity ==="
input long              InpMagic              = 100100;      // Magic number
input string           InpComment            = "US100-NYTP"; // Order comment
input int              InpSlippagePoints     = 20;           // Max deviation (points)

input group "=== Session ==="
input ENUM_SESSION_MODE InpSessionMode       = SESSION_MODE_NY; // How to read the hours below
input int              InpSessionStartHour   = 9;            // Session start hour
input int              InpSessionStartMin    = 30;           // Session start minute
input int              InpSessionEndHour     = 16;           // Session end hour
input int              InpSessionEndMin      = 0;            // Session end minute
input int              InpBrokerGmtWinter    = 2;            // Broker GMT offset, winter (NY mode)
input int              InpBrokerGmtSummer    = 3;            // Broker GMT offset, summer (NY mode)
input int              InpWarmupMinutes      = 15;           // Skip N min after the open
input int              InpEntryCutoffMin     = 30;           // No new entries N min before close
input bool             InpFlattenAtEnd       = true;         // Flatten everything at session end
input int              InpFlattenBeforeEnd   = 2;            // Flatten N min before close
input bool             InpTradeMonday        = true;         // Trade Monday
input bool             InpTradeTuesday       = true;         // Trade Tuesday
input bool             InpTradeWednesday     = true;         // Trade Wednesday
input bool             InpTradeThursday      = true;         // Trade Thursday
input bool             InpTradeFriday        = true;         // Trade Friday

input group "=== Signal ==="
input ENUM_TIMEFRAMES  InpBiasTF             = PERIOD_H1;    // Bias timeframe
input int              InpBiasEmaPeriod      = 50;           // Bias EMA period
input int              InpBiasSlopeBars      = 3;            // Bias EMA slope lookback
input ENUM_TIMEFRAMES  InpEntryTF            = PERIOD_M5;    // Entry timeframe
input int              InpFastEmaPeriod      = 20;           // Entry fast EMA (value zone)
input int              InpSlowEmaPeriod      = 50;           // Entry slow EMA (trend filter)
input int              InpPullbackLookback   = 6;            // Pullback lookback (bars)
input bool             InpRequireTrendAlign  = true;         // Require entry TF trend alignment

input group "=== Volatility and spread filters ==="
input int              InpAtrPeriod          = 14;           // ATR period (entry TF)
input double           InpMinAtrPoints       = 0;            // Min ATR in points (0 = off)
input double           InpMaxAtrPoints       = 0;            // Max ATR in points (0 = off)
input double           InpMaxSpreadPoints    = 0;            // Max spread in points (0 = off)
input double           InpMaxSpreadAtrRatio  = 0.20;         // Max spread / ATR (0 = off)

input group "=== Risk ==="
input double           InpRiskPercent        = 0.5;          // Risk per trade (% of equity)
input ENUM_SL_MODE     InpSlMode             = SL_MODE_SWING_ATR; // Stop placement mode
input double           InpSlAtrMult          = 1.5;          // ATR multiple for the stop
input int              InpSwingBars          = 5;            // Swing lookback for the stop
input double           InpSwingBufferAtr     = 0.25;         // Extra room beyond the swing (ATR)
input double           InpRewardRatio        = 2.0;          // Take profit as a multiple of risk
input double           InpMaxSlPoints        = 0;            // Reject setups wider than N points (0 = off)
input double           InpMarginBufferPct    = 20.0;         // Keep N% of free margin unused

input group "=== Trade management ==="
input bool             InpUseBreakeven       = true;         // Move to breakeven
input double           InpBeTriggerR         = 1.0;          // Breakeven trigger (R)
input double           InpBeOffsetAtr        = 0.05;         // Breakeven offset (ATR)
input bool             InpUseTrailing        = true;         // ATR trailing stop
input double           InpTrailStartR        = 1.5;          // Trailing start (R)
input double           InpTrailAtrMult       = 1.5;          // Trailing distance (ATR)

input group "=== Guardrails ==="
input int              InpMaxPositions       = 1;            // Max simultaneous positions
input int              InpMaxTradesPerDay    = 3;            // Max trades per day (0 = off)
input int              InpMaxConsecLosses    = 2;            // Stop after N losses in a row (0 = off)
input double           InpMaxDailyLossPct    = 2.0;          // Stop after N% day drawdown (0 = off)
input int              InpCooldownBars       = 3;            // Cooldown bars after a loss

input group "=== Diagnostics ==="
input bool             InpShowDashboard      = true;         // On-chart dashboard
input bool             InpVerboseLog          = true;        // Log why entries are skipped
input bool             InpWriteCsvLog        = false;        // Append closed trades to a CSV file

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade            g_trade;
CSymbolContext    g_ctx;
CSessionFilter    g_session;
CSignalEngine     g_signal;
CRiskManager      g_risk;
CPositionManager  g_posmgr;
CGuardrails       g_guard;
CDashboard        g_dash;

datetime          g_lastBarTime     = 0;
datetime          g_lastEntryBar    = 0;
datetime          g_lastFlattenTry  = 0;
int               g_sessionDay      = -1;  // server day the window was built for
int               g_sessionTotal    = 0;   // session length in minutes
ENUM_BLOCK_REASON g_block           = BLOCK_DATA;
ENUM_BLOCK_REASON g_lastLoggedBlock = BLOCK_NONE;
string            g_csvFile         = "";

//--- forward declarations
void              Housekeeping();
void              RefreshSession();
bool              MustFlatten(const datetime now);
ENUM_BLOCK_REASON EvaluateEntry();
bool              SendOrder(const SOrderPlan &plan);
void              LogBlock(const ENUM_BLOCK_REASON r);

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_ctx.Refresh(_Symbol))
     {
      Print("[init] cannot read symbol specifications, aborting");
      return(INIT_FAILED);
     }
   Print("[init] ",g_ctx.Describe());

   if(InpRiskPercent<=0.0)
     {
      Print("[init] risk per trade must be greater than zero");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpFastEmaPeriod>=InpSlowEmaPeriod)
     {
      Print("[init] fast EMA must be shorter than the slow EMA");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(PeriodSeconds(InpBiasTF)<PeriodSeconds(InpEntryTF))
     {
      Print("[init] bias timeframe must be equal to or higher than the entry timeframe");
      return(INIT_PARAMETERS_INCORRECT);
     }

   //--- trading layer
   g_trade.SetExpertMagicNumber((ulong)InpMagic);
   g_trade.SetDeviationInPoints((ulong)MathMax(0,InpSlippagePoints));
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   //--- session: build the server time window, then pick the weekdays
   RefreshSession();
   g_session.SetDay(0,false);                 // Sunday
   g_session.SetDay(1,InpTradeMonday);
   g_session.SetDay(2,InpTradeTuesday);
   g_session.SetDay(3,InpTradeWednesday);
   g_session.SetDay(4,InpTradeThursday);
   g_session.SetDay(5,InpTradeFriday);
   g_session.SetDay(6,false);                 // Saturday

   //--- signal
   if(!g_signal.Init(_Symbol,
                     InpBiasTF,InpBiasEmaPeriod,InpBiasSlopeBars,
                     InpEntryTF,InpFastEmaPeriod,InpSlowEmaPeriod,
                     InpAtrPeriod,InpPullbackLookback,InpSwingBars,
                     InpRequireTrendAlign))
     {
      Print("[init] signal engine failed to initialise");
      return(INIT_FAILED);
     }

   //--- risk
   g_risk.Attach(GetPointer(g_ctx));
   g_risk.Configure(InpRiskPercent,InpSlMode,InpSlAtrMult,InpSwingBufferAtr,
                    InpRewardRatio,InpMaxSlPoints,InpMarginBufferPct);

   //--- management
   g_posmgr.Attach(GetPointer(g_trade),GetPointer(g_ctx),InpMagic);
   g_posmgr.Configure(InpRewardRatio,
                      InpUseBreakeven,InpBeTriggerR,InpBeOffsetAtr,
                      InpUseTrailing,InpTrailStartR,InpTrailAtrMult);

   //--- guardrails
   g_guard.Configure(_Symbol,InpMagic,InpEntryTF,
                     InpMaxTradesPerDay,InpMaxConsecLosses,
                     InpMaxDailyLossPct,InpCooldownBars);
   g_guard.Recompute();

   g_dash.SetEnabled(InpShowDashboard);

   g_csvFile="US100_trades_"+_Symbol+"_"+IntegerToString(InpMagic)+".csv";

   PrintFormat("[init] %s v%s ready. Session %s. Server time now %s.",
               US100_EA_NAME,US100_EA_VERSION,g_session.Describe(),
               TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   PrintFormat("[init] risk %.2f%%/trade, TP %.2fR, max %d trades/day, day stop %.2f%%",
               InpRiskPercent,InpRewardRatio,InpMaxTradesPerDay,InpMaxDailyLossPct);

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("[init] WARNING: algo trading is disabled in the terminal");
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      Print("[init] WARNING: the account does not allow expert advisors");

   EventSetTimer(5);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_signal.Deinit();
   g_dash.Clear();
   PrintFormat("[deinit] stopped, reason=%d",reason);
  }

//+------------------------------------------------------------------+
//| Rebuild the server time session window.                          |
//|                                                                  |
//| In SESSION_MODE_NY the hour inputs are New York times and are    |
//| converted using both DST calendars, so the window follows the    |
//| real cash session all year. Called at init and on every new      |
//| server day, which is when a DST switch can take effect.          |
//+------------------------------------------------------------------+
void RefreshSession()
  {
   datetime now=TimeCurrent();

   int startMin=InpSessionStartHour*60+InpSessionStartMin;
   int endMin  =InpSessionEndHour*60+InpSessionEndMin;

   if(InpSessionMode==SESSION_MODE_NY)
     {
      startMin=TZ_NyMinuteToServerMinute(startMin,now,InpBrokerGmtWinter,InpBrokerGmtSummer);
      endMin  =TZ_NyMinuteToServerMinute(endMin,  now,InpBrokerGmtWinter,InpBrokerGmtSummer);
     }

   g_session.Configure(startMin/60,startMin%60,endMin/60,endMin%60,
                       (int)MathMax(0,InpWarmupMinutes),
                       (int)MathMax(0,InpEntryCutoffMin));

   g_sessionTotal=endMin-startMin;
   if(g_sessionTotal<=0)
      g_sessionTotal+=24*60;

   MqlDateTime s;
   TimeToStruct(now,s);
   g_sessionDay=s.day_of_year;

   PrintFormat("[session] window %s (mode=%s)",
               g_session.Describe(),
               InpSessionMode==SESSION_MODE_NY ? "New York" : "server");
  }

//+------------------------------------------------------------------+
//| True when every open position must be closed right now           |
//+------------------------------------------------------------------+
bool MustFlatten(const datetime now)
  {
   if(!InpFlattenAtEnd)
      return(false);

   //--- nothing can be closed while the instrument is not tradable
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)==SYMBOL_TRADE_MODE_DISABLED)
      return(false);

   if(!g_session.InSession(now))
      return(true);

   int into=g_session.MinutesIntoSession(now);
   return(into>=(g_sessionTotal-(int)MathMax(0,InpFlattenBeforeEnd)));
  }

//+------------------------------------------------------------------+
//| Runs on every tick and on the timer: management plus display     |
//+------------------------------------------------------------------+
void Housekeeping()
  {
   datetime now=TimeCurrent();

   //--- a DST switch can only land on a day boundary
   MqlDateTime st;
   TimeToStruct(now,st);
   if(st.day_of_year!=g_sessionDay)
      RefreshSession();

   //--- right after a restart the series are not loaded yet; refresh here
   //--- so trade management and the dashboard do not wait for a new bar
   if(!g_signal.DataOk())
      g_signal.Update();

   if(g_posmgr.HasPosition())
     {
      if(MustFlatten(now))
        {
         //--- the market can be closed or frozen: do not hammer the server
         if(now-g_lastFlattenTry>=30)
           {
            g_lastFlattenTry=now;
            g_posmgr.CloseAll("session end");
           }
        }
      else
         g_posmgr.Manage(g_signal.Atr());
     }

   if(InpShowDashboard)
     {
      double atrPts=g_ctx.PriceToPoints(g_signal.Atr());
      g_dash.Render(_Symbol,
                    g_session.Describe(),
                    g_session.InSession(now),
                    g_signal.Bias(),
                    atrPts,
                    g_ctx.SpreadPoints(),
                    g_guard.TradesToday(),
                    InpMaxTradesPerDay,
                    g_guard.ConsecLosses(),
                    g_guard.RealizedToday(),
                    g_guard.DayDrawdownPct(),
                    InpMaxDailyLossPct,
                    g_posmgr.Count(),
                    g_block);
     }
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   Housekeeping();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   Housekeeping();

   //--- entries are decided once per closed bar, never intrabar
   datetime barTime=iTime(_Symbol,InpEntryTF,0);
   if(barTime==0)
      return;
   if(barTime==g_lastBarTime)
      return;
   g_lastBarTime=barTime;

   g_guard.Recompute();
   g_block=EvaluateEntry();
   LogBlock(g_block);
  }

//+------------------------------------------------------------------+
//| One pass of the decision tree. Returns the first blocking reason |
//| or BLOCK_NONE when a trade was actually sent.                    |
//+------------------------------------------------------------------+
ENUM_BLOCK_REASON EvaluateEntry()
  {
   if(!g_signal.Update())
      return(BLOCK_DATA);

   datetime now=TimeCurrent();

   if(g_posmgr.Count()>=(int)MathMax(1,InpMaxPositions))
      return(BLOCK_POSITION_OPEN);

   if(!g_session.InSession(now))
      return(BLOCK_SESSION_CLOSED);

   if(!g_session.CanOpenNew(now))
     {
      if(g_session.MinutesIntoSession(now)<InpWarmupMinutes)
         return(BLOCK_SESSION_WARMUP);
      return(BLOCK_SESSION_CUTOFF);
     }

   ENUM_BLOCK_REASON guard=g_guard.Check();
   if(guard!=BLOCK_NONE)
      return(guard);

   //--- volatility window
   double atr=g_signal.Atr();
   double atrPts=g_ctx.PriceToPoints(atr);
   if(InpMinAtrPoints>0.0 && atrPts<InpMinAtrPoints)
      return(BLOCK_ATR_TOO_LOW);
   if(InpMaxAtrPoints>0.0 && atrPts>InpMaxAtrPoints)
      return(BLOCK_ATR_TOO_HIGH);

   //--- cost of entry
   double spreadPts=g_ctx.SpreadPoints();
   if(InpMaxSpreadPoints>0.0 && spreadPts>InpMaxSpreadPoints)
      return(BLOCK_SPREAD);
   if(InpMaxSpreadAtrRatio>0.0 && atrPts>0.0 && spreadPts>InpMaxSpreadAtrRatio*atrPts)
      return(BLOCK_SPREAD);

   if(g_signal.Bias()==BIAS_NONE)
      return(BLOCK_NO_BIAS);

   SSignal sig;
   if(!g_signal.BuildSignal(sig))
      return(BLOCK_NO_SETUP);

   //--- never act twice on the same trigger bar
   if(sig.barTime==g_lastEntryBar)
      return(BLOCK_NO_SETUP);

   SOrderPlan plan;
   string err="";
   if(!g_risk.BuildPlan(sig,plan,err))
     {
      PrintFormat("[entry] setup rejected by risk: %s",err);
      return(BLOCK_RISK_SIZING);
     }

   if(SendOrder(plan))
     {
      g_lastEntryBar=sig.barTime;
      g_guard.Recompute();
      return(BLOCK_NONE);
     }

   return(BLOCK_RISK_SIZING);
  }

//+------------------------------------------------------------------+
//| Market order with a couple of retries on transient price errors  |
//+------------------------------------------------------------------+
bool SendOrder(const SOrderPlan &plan)
  {
   string comment=StringSubstr(InpComment,0,27);

   for(int attempt=1;attempt<=3;attempt++)
     {
      bool ok;
      if(plan.isBuy)
         ok=g_trade.Buy(plan.lot,_Symbol,0.0,plan.sl,plan.tp,comment);
      else
         ok=g_trade.Sell(plan.lot,_Symbol,0.0,plan.sl,plan.tp,comment);

      uint code=g_trade.ResultRetcode();

      if(ok && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED ||
                code==TRADE_RETCODE_DONE_PARTIAL))
        {
         PrintFormat("[entry] %s %.2f lots @ %.*f  SL %.*f  TP %.*f  "
                     "stop %.0f pts  risk %.2f %s",
                     plan.isBuy?"BUY":"SELL",plan.lot,
                     g_ctx.Digits(),g_trade.ResultPrice(),
                     g_ctx.Digits(),plan.sl,
                     g_ctx.Digits(),plan.tp,
                     g_ctx.PriceToPoints(plan.slDistance),
                     plan.riskMoney,AccountInfoString(ACCOUNT_CURRENCY));
         return(true);
        }

      bool transient=(code==TRADE_RETCODE_REQUOTE ||
                      code==TRADE_RETCODE_PRICE_CHANGED ||
                      code==TRADE_RETCODE_PRICE_OFF ||
                      code==TRADE_RETCODE_TIMEOUT ||
                      code==TRADE_RETCODE_CONNECTION);

      PrintFormat("[entry] order attempt %d failed, ret=%d (%s)%s",
                  attempt,code,g_trade.ResultRetcodeDescription(),
                  transient?" - retrying":"");

      if(!transient)
         break;
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Only log a reason when it changes, to keep the journal readable  |
//+------------------------------------------------------------------+
void LogBlock(const ENUM_BLOCK_REASON r)
  {
   if(!InpVerboseLog)
      return;
   if(r==g_lastLoggedBlock)
      return;
   g_lastLoggedBlock=r;

   if(r==BLOCK_NONE)
      return;

   PrintFormat("[state] %s  (bias=%d atr=%.0f pts spread=%.0f pts trades=%d dd=%.2f%%)",
               BlockReasonToString(r),(int)g_signal.Bias(),
               g_ctx.PriceToPoints(g_signal.Atr()),g_ctx.SpreadPoints(),
               g_guard.TradesToday(),g_guard.DayDrawdownPct());
  }

//+------------------------------------------------------------------+
//| Optional CSV trade journal, one row per closing deal             |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpWriteCsvLog)
      return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.symbol!=_Symbol)
      return;
   if(trans.deal==0)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic)
      return;

   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT)
      return;

   int h=FileOpen(g_csvFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(h==INVALID_HANDLE)
     {
      PrintFormat("[csv] cannot open %s, err=%d",g_csvFile,GetLastError());
      return;
     }

   bool fresh=(FileSize(h)==0);
   FileSeek(h,0,SEEK_END);

   if(fresh)
      FileWrite(h,"close_time","symbol","type","volume","price","profit",
                "swap","commission","net","balance","comment");

   double profit    = HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   double swap      = HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   double commission= HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);

   FileWrite(h,
             TimeToString((datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME),TIME_DATE|TIME_SECONDS),
             HistoryDealGetString(trans.deal,DEAL_SYMBOL),
             (HistoryDealGetInteger(trans.deal,DEAL_TYPE)==DEAL_TYPE_BUY ? "buy" : "sell"),
             DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_VOLUME),2),
             DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_PRICE),g_ctx.Digits()),
             DoubleToString(profit,2),
             DoubleToString(swap,2),
             DoubleToString(commission,2),
             DoubleToString(profit+swap+commission,2),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
             HistoryDealGetString(trans.deal,DEAL_COMMENT));

   FileClose(h);
  }
//+------------------------------------------------------------------+
