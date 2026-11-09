//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|   Minimal on-chart panel so the state of the EA is readable at   |
//|   a glance without digging through the journal.                  |
//+------------------------------------------------------------------+
#ifndef US100_DASHBOARD_MQH
#define US100_DASHBOARD_MQH

#include "Defs.mqh"

//+------------------------------------------------------------------+
class CDashboard
  {
private:
   bool              m_enabled;

public:
                     CDashboard(): m_enabled(true) {}
   void              SetEnabled(const bool on) { m_enabled=on; }

   void              Render(const string symbol,
                            const string sessionText,
                            const bool inSession,
                            const ENUM_BIAS bias,
                            const double atrPoints,
                            const double spreadPoints,
                            const int tradesToday,
                            const int maxTrades,
                            const int consecLosses,
                            const double realizedToday,
                            const double ddPct,
                            const double maxDdPct,
                            const int openPositions,
                            const ENUM_BLOCK_REASON block);

   void              Clear() { Comment(""); }
  };

//+------------------------------------------------------------------+
void CDashboard::Render(const string symbol,
                        const string sessionText,
                        const bool inSession,
                        const ENUM_BIAS bias,
                        const double atrPoints,
                        const double spreadPoints,
                        const int tradesToday,
                        const int maxTrades,
                        const int consecLosses,
                        const double realizedToday,
                        const double ddPct,
                        const double maxDdPct,
                        const int openPositions,
                        const ENUM_BLOCK_REASON block)
  {
   if(!m_enabled)
      return;

   string biasText="flat";
   if(bias==BIAS_LONG)  biasText="LONG";
   if(bias==BIAS_SHORT) biasText="SHORT";

   string txt="";
   txt+=StringFormat("%s  v%s\n",US100_EA_NAME,US100_EA_VERSION);
   txt+="--------------------------------------\n";
   txt+=StringFormat("Symbol      : %s\n",symbol);
   txt+=StringFormat("Session     : %s  [%s]\n",sessionText,inSession?"OPEN":"closed");
   txt+=StringFormat("HTF bias    : %s\n",biasText);
   txt+=StringFormat("ATR / spread: %.0f pts / %.0f pts\n",atrPoints,spreadPoints);
   txt+="--------------------------------------\n";
   txt+=StringFormat("Open pos.   : %d\n",openPositions);
   txt+=StringFormat("Trades today: %d%s\n",tradesToday,
                     maxTrades>0?StringFormat(" / %d",maxTrades):"");
   txt+=StringFormat("Loss streak : %d\n",consecLosses);
   txt+=StringFormat("Realized P/L: %.2f %s\n",realizedToday,
                     AccountInfoString(ACCOUNT_CURRENCY));
   txt+=StringFormat("Day drawdown: %.2f%%%s\n",ddPct,
                     maxDdPct>0?StringFormat(" / %.2f%%",maxDdPct):"");
   txt+="--------------------------------------\n";
   txt+=StringFormat("State       : %s\n",BlockReasonToString(block));

   Comment(txt);
  }

#endif // US100_DASHBOARD_MQH
