//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|   Turns a signal into a concrete order plan: stop placement,     |
//|   take profit and a position size derived from a % of equity.    |
//+------------------------------------------------------------------+
#ifndef US100_RISKMANAGER_MQH
#define US100_RISKMANAGER_MQH

#include "Defs.mqh"
#include "SymbolContext.mqh"

//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   CSymbolContext   *m_ctx;
   double            m_riskPct;
   ENUM_SL_MODE      m_slMode;
   double            m_slAtrMult;      // used by SL_MODE_ATR and as the floor
   double            m_swingBufferAtr; // extra room beyond the swing, in ATR
   double            m_rewardRatio;    // TP = rr * SL distance
   double            m_maxSlPoints;    // 0 = no cap
   double            m_marginBufferPct;

public:
                     CRiskManager();
   void              Attach(CSymbolContext *ctx) { m_ctx=ctx; }
   void              Configure(const double riskPct,const ENUM_SL_MODE slMode,
                               const double slAtrMult,const double swingBufferAtr,
                               const double rewardRatio,const double maxSlPoints,
                               const double marginBufferPct);

   double            RewardRatio() const { return(m_rewardRatio); }

   bool              BuildPlan(const SSignal &sig,SOrderPlan &plan,string &err) const;

private:
   double            StopDistance(const SSignal &sig,const double price,const bool isBuy) const;
   double            LotForRisk(const double price,const double sl,const bool isBuy,
                                const double riskMoney,double &riskUsed,string &err) const;
  };

//+------------------------------------------------------------------+
CRiskManager::CRiskManager()
  {
   m_ctx=NULL;
   m_riskPct=0.5;
   m_slMode=SL_MODE_SWING_ATR;
   m_slAtrMult=1.5;
   m_swingBufferAtr=0.25;
   m_rewardRatio=2.0;
   m_maxSlPoints=0.0;
   m_marginBufferPct=20.0;
  }

//+------------------------------------------------------------------+
void CRiskManager::Configure(const double riskPct,const ENUM_SL_MODE slMode,
                             const double slAtrMult,const double swingBufferAtr,
                             const double rewardRatio,const double maxSlPoints,
                             const double marginBufferPct)
  {
   m_riskPct         = MathMax(0.01,riskPct);
   m_slMode          = slMode;
   m_slAtrMult       = MathMax(0.1,slAtrMult);
   m_swingBufferAtr  = MathMax(0.0,swingBufferAtr);
   m_rewardRatio     = MathMax(0.1,rewardRatio);
   m_maxSlPoints     = MathMax(0.0,maxSlPoints);
   m_marginBufferPct = MathMax(0.0,marginBufferPct);
  }

//+------------------------------------------------------------------+
//| Raw stop distance before broker constraints are applied          |
//+------------------------------------------------------------------+
double CRiskManager::StopDistance(const SSignal &sig,const double price,const bool isBuy) const
  {
   double atrDist=m_slAtrMult*sig.atr;

   double swingDist;
   if(isBuy)
      swingDist=price-(sig.swingRef-m_swingBufferAtr*sig.atr);
   else
      swingDist=(sig.swingRef+m_swingBufferAtr*sig.atr)-price;

   switch(m_slMode)
     {
      case SL_MODE_ATR:
         return(atrDist);
      case SL_MODE_SWING:
         return(swingDist);
      default: // SL_MODE_SWING_ATR
         return(MathMax(swingDist,atrDist));
     }
  }

//+------------------------------------------------------------------+
//| Volume such that hitting the stop costs riskMoney                |
//+------------------------------------------------------------------+
double CRiskManager::LotForRisk(const double price,const double sl,const bool isBuy,
                                const double riskMoney,double &riskUsed,string &err) const
  {
   riskUsed=0.0;

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   //--- loss of exactly one lot if the stop is hit, in account currency
   double lossPerLot=0.0;
   if(!OrderCalcProfit(type,m_ctx.Symbol(),1.0,price,sl,lossPerLot))
     {
      //--- fallback on tick value arithmetic
      double vpp=m_ctx.ValuePerPointPerLot();
      if(vpp<=0.0)
        {
         err="cannot value a point on this symbol";
         return(0.0);
        }
      lossPerLot=-m_ctx.PriceToPoints(MathAbs(price-sl))*vpp;
     }

   lossPerLot=MathAbs(lossPerLot);
   if(lossPerLot<=0.0)
     {
      err="computed loss per lot is zero";
      return(0.0);
     }

   double lot=m_ctx.NormalizeLotDown(riskMoney/lossPerLot);

   if(lot<m_ctx.MinLot())
     {
      err=StringFormat("risk %.2f too small: min lot %.2f would risk %.2f",
                       riskMoney,m_ctx.MinLot(),m_ctx.MinLot()*lossPerLot);
      return(0.0);
     }

   //--- never take a position we cannot margin comfortably
   double margin=0.0;
   if(OrderCalcMargin(type,m_ctx.Symbol(),lot,price,margin))
     {
      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double allowed=freeMargin*(1.0-m_marginBufferPct/100.0);
      if(margin>allowed && margin>0.0)
        {
         double scaled=m_ctx.NormalizeLotDown(lot*allowed/margin);
         if(scaled<m_ctx.MinLot())
           {
            err=StringFormat("not enough free margin (needs %.2f, allowed %.2f)",margin,allowed);
            return(0.0);
           }
         PrintFormat("[risk] lot reduced %.2f -> %.2f by margin buffer",lot,scaled);
         lot=scaled;
        }
     }

   riskUsed=lot*lossPerLot;
   return(lot);
  }

//+------------------------------------------------------------------+
bool CRiskManager::BuildPlan(const SSignal &sig,SOrderPlan &plan,string &err) const
  {
   plan.Reset();
   err="";

   if(m_ctx==NULL || !m_ctx.IsReady())
     {
      err="symbol context not ready";
      return(false);
     }
   if(sig.dir==SIG_NONE || sig.atr<=0.0)
     {
      err="empty signal";
      return(false);
     }

   bool isBuy=(sig.dir==SIG_BUY);
   plan.isBuy=isBuy;
   plan.price=isBuy ? m_ctx.Ask() : m_ctx.Bid();

   if(plan.price<=0.0)
     {
      err="no price available";
      return(false);
     }

   double slDist=StopDistance(sig,plan.price,isBuy);

   //--- broker floor: the stop is checked against the opposite side of
   //--- the spread, so reserve the spread on top of the stops level
   double minDist=m_ctx.MinStopPrice()+m_ctx.SpreadPrice();
   double absoluteFloor=m_ctx.PointsToPrice(1.0);
   minDist=MathMax(minDist,absoluteFloor);
   if(slDist<minDist)
     {
      PrintFormat("[risk] stop widened %.*f -> %.*f (broker minimum)",
                  m_ctx.Digits(),slDist,m_ctx.Digits(),minDist);
      slDist=minDist;
     }

   if(m_maxSlPoints>0.0 && m_ctx.PriceToPoints(slDist)>m_maxSlPoints)
     {
      err=StringFormat("stop %.0f pts exceeds cap %.0f pts",
                       m_ctx.PriceToPoints(slDist),m_maxSlPoints);
      return(false);
     }

   plan.slDistance=slDist;
   plan.sl=m_ctx.NormalizePrice(isBuy ? plan.price-slDist : plan.price+slDist);
   plan.tp=m_ctx.NormalizePrice(isBuy ? plan.price+m_rewardRatio*slDist
                                      : plan.price-m_rewardRatio*slDist);

   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*m_riskPct/100.0;
   if(riskMoney<=0.0)
     {
      err="equity is zero";
      return(false);
     }

   plan.lot=LotForRisk(plan.price,plan.sl,isBuy,riskMoney,plan.riskMoney,err);
   if(plan.lot<=0.0)
      return(false);

   return(true);
  }

#endif // US100_RISKMANAGER_MQH
