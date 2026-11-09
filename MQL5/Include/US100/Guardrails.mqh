//+------------------------------------------------------------------+
//|                                                   Guardrails.mqh |
//|   Daily risk budget and trade throttling. Every figure is        |
//|   recomputed from the deal history so the state survives a       |
//|   terminal restart or a chart reload mid session.                |
//+------------------------------------------------------------------+
#ifndef US100_GUARDRAILS_MQH
#define US100_GUARDRAILS_MQH

#include "Defs.mqh"

//+------------------------------------------------------------------+
class CGuardrails
  {
private:
   string            m_symbol;
   long              m_magic;
   ENUM_TIMEFRAMES   m_tf;

   int               m_maxTradesPerDay;
   int               m_maxConsecLosses;
   double            m_maxDailyLossPct;
   int               m_cooldownBars;

   //--- cached day statistics
   datetime          m_cacheStamp;
   int               m_tradesToday;
   int               m_consecLosses;
   double            m_realizedToday;
   datetime          m_lastLossClose;

public:
                     CGuardrails();
   void              Configure(const string sym,const long magic,const ENUM_TIMEFRAMES tf,
                               const int maxTradesPerDay,const int maxConsecLosses,
                               const double maxDailyLossPct,const int cooldownBars);

   void              Recompute();
   ENUM_BLOCK_REASON Check() const;

   int               TradesToday()      const { return(m_tradesToday);   }
   int               ConsecLosses()     const { return(m_consecLosses);  }
   double            RealizedToday()    const { return(m_realizedToday); }
   double            FloatingPL()       const;
   double            DayDrawdownPct()   const;
   int               CooldownBarsLeft() const;

   static datetime   StartOfDay(const datetime t);

private:
   bool              IsOurDeal(const ulong ticket) const;
  };

//+------------------------------------------------------------------+
CGuardrails::CGuardrails()
  {
   m_symbol="";
   m_magic=0;
   m_tf=PERIOD_M5;
   m_maxTradesPerDay=3;
   m_maxConsecLosses=2;
   m_maxDailyLossPct=2.0;
   m_cooldownBars=3;
   m_cacheStamp=0;
   m_tradesToday=0;
   m_consecLosses=0;
   m_realizedToday=0.0;
   m_lastLossClose=0;
  }

//+------------------------------------------------------------------+
void CGuardrails::Configure(const string sym,const long magic,const ENUM_TIMEFRAMES tf,
                            const int maxTradesPerDay,const int maxConsecLosses,
                            const double maxDailyLossPct,const int cooldownBars)
  {
   m_symbol          = sym;
   m_magic           = magic;
   m_tf              = tf;
   m_maxTradesPerDay = maxTradesPerDay;      // <=0 disables
   m_maxConsecLosses = maxConsecLosses;      // <=0 disables
   m_maxDailyLossPct = maxDailyLossPct;      // <=0 disables
   m_cooldownBars    = (int)MathMax(0,cooldownBars);
  }

//+------------------------------------------------------------------+
datetime CGuardrails::StartOfDay(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   s.hour=0;
   s.min=0;
   s.sec=0;
   return(StructToTime(s));
  }

//+------------------------------------------------------------------+
bool CGuardrails::IsOurDeal(const ulong ticket) const
  {
   if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol)
      return(false);
   if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=m_magic)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| Walk today's deals once and refresh every counter                |
//+------------------------------------------------------------------+
void CGuardrails::Recompute()
  {
   m_tradesToday=0;
   m_consecLosses=0;
   m_realizedToday=0.0;
   m_lastLossClose=0;
   m_cacheStamp=TimeCurrent();

   datetime from=StartOfDay(TimeCurrent());
   if(!HistorySelect(from,TimeCurrent()+1))
      return;

   int total=HistoryDealsTotal();

   //--- Aggregate every deal of the day per position id, so a trade is
   //--- judged on its full net result, commission and swap included.
   //--- A broker that charges commission on the opening deal would
   //--- otherwise make a small loss look like a win.
   long     posId[];
   double   posNet[];
   datetime posClose[];
   bool     posOpened[];
   bool     posClosed[];
   int      n=0;

   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0)
         continue;
      if(!IsOurDeal(ticket))
         continue;

      long   entry      = HistoryDealGetInteger(ticket,DEAL_ENTRY);
      long   positionId = HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      double net        = HistoryDealGetDouble(ticket,DEAL_PROFIT)
                          +HistoryDealGetDouble(ticket,DEAL_SWAP)
                          +HistoryDealGetDouble(ticket,DEAL_COMMISSION);

      m_realizedToday+=net;

      int idx=-1;
      for(int k=0;k<n;k++)
         if(posId[k]==positionId)
           {
            idx=k;
            break;
           }

      if(idx<0)
        {
         idx=n;
         n++;
         ArrayResize(posId,n);
         ArrayResize(posNet,n);
         ArrayResize(posClose,n);
         ArrayResize(posOpened,n);
         ArrayResize(posClosed,n);
         posId[idx]=positionId;
         posNet[idx]=0.0;
         posClose[idx]=0;
         posOpened[idx]=false;
         posClosed[idx]=false;
        }

      posNet[idx]+=net;

      if(entry==DEAL_ENTRY_IN)
         posOpened[idx]=true;

      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
        {
         posClosed[idx]=true;
         datetime dt=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
         if(dt>posClose[idx])
            posClose[idx]=dt;
        }
     }

   //--- a trade counts against the daily quota as soon as it was opened
   for(int k=0;k<n;k++)
      if(posOpened[k])
         m_tradesToday++;

   //--- collect the closed trades and order them by close time
   datetime ct[];
   double   cn[];
   int      m=0;
   for(int k=0;k<n;k++)
     {
      if(!posClosed[k])
         continue;
      m++;
      ArrayResize(ct,m);
      ArrayResize(cn,m);
      ct[m-1]=posClose[k];
      cn[m-1]=posNet[k];
     }

   for(int a=1;a<m;a++)                       // insertion sort, a few items
     {
      datetime kt=ct[a];
      double   kv=cn[a];
      int      b=a-1;
      while(b>=0 && ct[b]>kt)
        {
         ct[b+1]=ct[b];
         cn[b+1]=cn[b];
         b--;
        }
      ct[b+1]=kt;
      cn[b+1]=kv;
     }

   //--- losing streak at the tail of the sequence
   for(int a=m-1;a>=0;a--)
     {
      if(cn[a]<0.0)
         m_consecLosses++;
      else
         break;
     }

   //--- most recent loss, which is what the cooldown counts from
   for(int a=m-1;a>=0;a--)
      if(cn[a]<0.0)
        {
         m_lastLossClose=ct[a];
         break;
        }
  }

//+------------------------------------------------------------------+
double CGuardrails::FloatingPL() const
  {
   double pl=0.0;
   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
         continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic)
         continue;
      pl+=PositionGetDouble(POSITION_PROFIT)
          +PositionGetDouble(POSITION_SWAP);
     }
   return(pl);
  }

//+------------------------------------------------------------------+
//| Drawdown since the start of the day, as a positive percentage.   |
//| Derived from the balance at day start, so a restart does not     |
//| reset the budget.                                                |
//+------------------------------------------------------------------+
double CGuardrails::DayDrawdownPct() const
  {
   double startBalance=AccountInfoDouble(ACCOUNT_BALANCE)-m_realizedToday;
   if(startBalance<=0.0)
      return(0.0);

   double pl=m_realizedToday+FloatingPL();
   if(pl>=0.0)
      return(0.0);

   return(-pl/startBalance*100.0);
  }

//+------------------------------------------------------------------+
int CGuardrails::CooldownBarsLeft() const
  {
   if(m_cooldownBars<=0 || m_lastLossClose==0)
      return(0);

   int secs=PeriodSeconds(m_tf);
   if(secs<=0)
      return(0);

   int elapsed=(int)((TimeCurrent()-m_lastLossClose)/secs);
   int left=m_cooldownBars-elapsed;
   return(left>0 ? left : 0);
  }

//+------------------------------------------------------------------+
//| The single question the EA asks before every entry               |
//+------------------------------------------------------------------+
ENUM_BLOCK_REASON CGuardrails::Check() const
  {
   if(m_maxDailyLossPct>0.0 && DayDrawdownPct()>=m_maxDailyLossPct)
      return(BLOCK_DAILY_LOSS);

   if(m_maxTradesPerDay>0 && m_tradesToday>=m_maxTradesPerDay)
      return(BLOCK_MAX_TRADES);

   if(m_maxConsecLosses>0 && m_consecLosses>=m_maxConsecLosses)
      return(BLOCK_CONSEC_LOSSES);

   if(CooldownBarsLeft()>0)
      return(BLOCK_COOLDOWN);

   return(BLOCK_NONE);
  }

#endif // US100_GUARDRAILS_MQH
