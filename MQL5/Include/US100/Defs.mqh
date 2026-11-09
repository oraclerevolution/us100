//+------------------------------------------------------------------+
//|                                                         Defs.mqh |
//|   US100 NY Trend Pullback - shared enums, structs and constants  |
//+------------------------------------------------------------------+
#ifndef US100_DEFS_MQH
#define US100_DEFS_MQH

#define US100_EA_NAME     "US100_NY_TrendPullback"
#define US100_EA_VERSION  "1.0.0"

//--- Directional bias derived from the higher timeframe
enum ENUM_BIAS
  {
   BIAS_NONE  =  0,
   BIAS_LONG  =  1,
   BIAS_SHORT = -1
  };

//--- Entry signal direction
enum ENUM_SIGNAL_DIR
  {
   SIG_NONE =  0,
   SIG_BUY  =  1,
   SIG_SELL = -1
  };

//--- How the session window inputs are interpreted
enum ENUM_SESSION_MODE
  {
   SESSION_MODE_NY     = 0, // New York time (DST handled automatically)
   SESSION_MODE_SERVER = 1  // Broker server time (raw, no conversion)
  };

//--- How the protective stop distance is derived
enum ENUM_SL_MODE
  {
   SL_MODE_ATR       = 0, // ATR only
   SL_MODE_SWING     = 1, // Swing structure only
   SL_MODE_SWING_ATR = 2  // Swing structure with ATR floor
  };

//--- Why the EA refused to open a trade on this bar
enum ENUM_BLOCK_REASON
  {
   BLOCK_NONE = 0,
   BLOCK_DATA,
   BLOCK_SESSION_CLOSED,
   BLOCK_SESSION_WARMUP,
   BLOCK_SESSION_CUTOFF,
   BLOCK_DAILY_LOSS,
   BLOCK_MAX_TRADES,
   BLOCK_CONSEC_LOSSES,
   BLOCK_COOLDOWN,
   BLOCK_POSITION_OPEN,
   BLOCK_SPREAD,
   BLOCK_ATR_TOO_LOW,
   BLOCK_ATR_TOO_HIGH,
   BLOCK_NO_BIAS,
   BLOCK_NO_SETUP,
   BLOCK_RISK_SIZING
  };

//+------------------------------------------------------------------+
//| Human readable label for a block reason                          |
//+------------------------------------------------------------------+
string BlockReasonToString(const ENUM_BLOCK_REASON r)
  {
   switch(r)
     {
      case BLOCK_NONE:            return("ready");
      case BLOCK_DATA:            return("waiting for data");
      case BLOCK_SESSION_CLOSED:  return("outside session");
      case BLOCK_SESSION_WARMUP:  return("open warmup");
      case BLOCK_SESSION_CUTOFF:  return("entry cutoff");
      case BLOCK_DAILY_LOSS:      return("daily loss limit");
      case BLOCK_MAX_TRADES:      return("max trades/day");
      case BLOCK_CONSEC_LOSSES:   return("consecutive losses");
      case BLOCK_COOLDOWN:        return("cooldown after loss");
      case BLOCK_POSITION_OPEN:   return("position already open");
      case BLOCK_SPREAD:          return("spread too wide");
      case BLOCK_ATR_TOO_LOW:     return("volatility too low");
      case BLOCK_ATR_TOO_HIGH:    return("volatility too high");
      case BLOCK_NO_BIAS:         return("no HTF bias");
      case BLOCK_NO_SETUP:        return("no setup");
      case BLOCK_RISK_SIZING:     return("risk sizing rejected");
     }
   return("unknown");
  }

//+------------------------------------------------------------------+
//| A fully qualified entry setup produced by the signal engine      |
//+------------------------------------------------------------------+
struct SSignal
  {
   ENUM_SIGNAL_DIR   dir;        // trade direction
   double            atr;        // ATR on the entry timeframe (price units)
   double            swingRef;   // swing low (buy) or swing high (sell)
   double            emaFast;    // fast EMA value on the trigger bar
   datetime          barTime;    // open time of the trigger bar

   void Reset()
     {
      dir=SIG_NONE;
      atr=0.0;
      swingRef=0.0;
      emaFast=0.0;
      barTime=0;
     }
  };

//+------------------------------------------------------------------+
//| A validated order request ready to be sent                       |
//+------------------------------------------------------------------+
struct SOrderPlan
  {
   bool     isBuy;
   double   price;
   double   sl;
   double   tp;
   double   lot;
   double   slDistance;  // price units
   double   riskMoney;   // account currency actually at risk

   void Reset()
     {
      isBuy=false;
      price=0.0;
      sl=0.0;
      tp=0.0;
      lot=0.0;
      slDistance=0.0;
      riskMoney=0.0;
     }
  };

#endif // US100_DEFS_MQH
