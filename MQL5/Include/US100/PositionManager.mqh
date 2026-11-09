//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|   Owns everything that happens AFTER an entry: break even,       |
//|   ATR trailing stop and the end of session flatten.              |
//|                                                                  |
//|   The initial risk R is rebuilt from the take profit distance    |
//|   (TP = rr * R by construction), so the module stays stateless   |
//|   and keeps working after a terminal restart.                    |
//+------------------------------------------------------------------+
#ifndef US100_POSITIONMANAGER_MQH
#define US100_POSITIONMANAGER_MQH

#include <Trade\Trade.mqh>
#include "Defs.mqh"
#include "SymbolContext.mqh"

//+------------------------------------------------------------------+
class CPositionManager
  {
private:
   CTrade           *m_trade;
   CSymbolContext   *m_ctx;
   long              m_magic;

   double            m_rewardRatio;
   bool              m_beEnabled;
   double            m_beTriggerR;
   double            m_beOffsetAtr;
   bool              m_trailEnabled;
   double            m_trailStartR;
   double            m_trailAtrMult;

public:
                     CPositionManager();
   void              Attach(CTrade *trade,CSymbolContext *ctx,const long magic);
   void              Configure(const double rewardRatio,
                               const bool beEnabled,const double beTriggerR,const double beOffsetAtr,
                               const bool trailEnabled,const double trailStartR,const double trailAtrMult);

   int               Count() const;
   bool              HasPosition() const { return(Count()>0); }
   void              Manage(const double atr);
   int               CloseAll(const string reason);

private:
   bool              IsOurs() const;
   double            InitialRisk(const double entry,const double tp,const double atr) const;
   bool              ApplyStop(const ulong ticket,const double newSL,const double tp,
                               const double refPrice,const string tag);
  };

//+------------------------------------------------------------------+
CPositionManager::CPositionManager()
  {
   m_trade=NULL;
   m_ctx=NULL;
   m_magic=0;
   m_rewardRatio=2.0;
   m_beEnabled=true;
   m_beTriggerR=1.0;
   m_beOffsetAtr=0.05;
   m_trailEnabled=true;
   m_trailStartR=1.5;
   m_trailAtrMult=1.5;
  }

//+------------------------------------------------------------------+
void CPositionManager::Attach(CTrade *trade,CSymbolContext *ctx,const long magic)
  {
   m_trade=trade;
   m_ctx=ctx;
   m_magic=magic;
  }

//+------------------------------------------------------------------+
void CPositionManager::Configure(const double rewardRatio,
                                 const bool beEnabled,const double beTriggerR,const double beOffsetAtr,
                                 const bool trailEnabled,const double trailStartR,const double trailAtrMult)
  {
   m_rewardRatio  = MathMax(0.1,rewardRatio);
   m_beEnabled    = beEnabled;
   m_beTriggerR   = MathMax(0.1,beTriggerR);
   m_beOffsetAtr  = MathMax(0.0,beOffsetAtr);
   m_trailEnabled = trailEnabled;
   m_trailStartR  = MathMax(0.1,trailStartR);
   m_trailAtrMult = MathMax(0.1,trailAtrMult);
  }

//+------------------------------------------------------------------+
//| Assumes a position is already selected                           |
//+------------------------------------------------------------------+
bool CPositionManager::IsOurs() const
  {
   if(PositionGetString(POSITION_SYMBOL)!=m_ctx.Symbol())
      return(false);
   if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
int CPositionManager::Count() const
  {
   int n=0;
   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      if(PositionGetTicket(i)==0)
         continue;
      if(IsOurs())
         n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
double CPositionManager::InitialRisk(const double entry,const double tp,const double atr) const
  {
   if(tp>0.0 && m_rewardRatio>0.0)
     {
      double r=MathAbs(tp-entry)/m_rewardRatio;
      if(r>0.0)
         return(r);
     }
   //--- no take profit set: fall back on current volatility
   return(atr>0.0 ? atr : 0.0);
  }

//+------------------------------------------------------------------+
//| Push a new stop, respecting the broker distance constraints      |
//+------------------------------------------------------------------+
bool CPositionManager::ApplyStop(const ulong ticket,const double newSL,const double tp,
                                 const double refPrice,const string tag)
  {
   double sl=m_ctx.NormalizePrice(newSL);

   //--- the broker refuses stops that sit too close to the market
   double minDist=m_ctx.MinStopPrice();
   if(minDist>0.0 && MathAbs(refPrice-sl)<minDist)
      return(false);

   //--- and refuses any modification inside the freeze zone
   double freeze=m_ctx.FreezePrice();
   if(freeze>0.0 && MathAbs(refPrice-sl)<freeze)
      return(false);

   if(!m_trade.PositionModify(ticket,sl,tp))
     {
      PrintFormat("[mgr] %s stop modify failed on #%s, ret=%d (%s)",
                  tag,IntegerToString(ticket),
                  m_trade.ResultRetcode(),m_trade.ResultRetcodeDescription());
      return(false);
     }

   PrintFormat("[mgr] %s stop moved to %.*f on #%s",
               tag,m_ctx.Digits(),sl,IntegerToString(ticket));
   return(true);
  }

//+------------------------------------------------------------------+
//| Called on every tick while a position is open                    |
//+------------------------------------------------------------------+
void CPositionManager::Manage(const double atr)
  {
   if(m_trade==NULL || m_ctx==NULL)
      return;
   if(!m_beEnabled && !m_trailEnabled)
      return;

   int total=PositionsTotal();
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(!IsOurs())
         continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      bool   isBuy = (type==POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      double R=InitialRisk(entry,tp,atr);
      if(R<=0.0)
         continue;

      double cur    = isBuy ? m_ctx.Bid() : m_ctx.Ask();
      double profit = isBuy ? (cur-entry) : (entry-cur);

      double target=sl;
      string tag="";

      //--- 1. break even
      if(m_beEnabled && profit>=m_beTriggerR*R)
        {
         double be = isBuy ? entry+m_beOffsetAtr*atr : entry-m_beOffsetAtr*atr;
         if(isBuy)
           {
            if(sl<=0.0 || be>target)
              {
               target=be;
               tag="breakeven";
              }
           }
         else
           {
            if(sl<=0.0 || be<target)
              {
               target=be;
               tag="breakeven";
              }
           }
        }

      //--- 2. ATR trailing, which can only improve on the above
      if(m_trailEnabled && profit>=m_trailStartR*R)
        {
         double trail = isBuy ? cur-m_trailAtrMult*atr : cur+m_trailAtrMult*atr;
         if(isBuy)
           {
            if(trail>target)
              {
               target=trail;
               tag="trail";
              }
           }
         else
           {
            if(target<=0.0 || trail<target)
              {
               target=trail;
               tag="trail";
              }
           }
        }

      if(tag=="")
         continue;

      //--- ignore micro adjustments, they only generate traffic
      double minMove=m_ctx.PointsToPrice(1.0);
      if(sl>0.0 && MathAbs(target-sl)<minMove)
         continue;

      ApplyStop(ticket,target,tp,cur,tag);
     }
  }

//+------------------------------------------------------------------+
//| Flatten every position owned by this EA                          |
//+------------------------------------------------------------------+
int CPositionManager::CloseAll(const string reason)
  {
   if(m_trade==NULL || m_ctx==NULL)
      return(0);

   int closed=0;
   int total=PositionsTotal();
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(!IsOurs())
         continue;

      if(m_trade.PositionClose(ticket))
        {
         closed++;
         PrintFormat("[mgr] closed #%s (%s)",IntegerToString(ticket),reason);
        }
      else
         PrintFormat("[mgr] close failed on #%s, ret=%d (%s)",
                     IntegerToString(ticket),
                     m_trade.ResultRetcode(),m_trade.ResultRetcodeDescription());
     }
   return(closed);
  }

#endif // US100_POSITIONMANAGER_MQH
