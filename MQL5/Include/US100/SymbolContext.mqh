//+------------------------------------------------------------------+
//|                                                SymbolContext.mqh |
//|   Caches broker symbol specs and centralises every conversion    |
//|   between points, price distances and lots.                      |
//+------------------------------------------------------------------+
#ifndef US100_SYMBOLCONTEXT_MQH
#define US100_SYMBOLCONTEXT_MQH

//+------------------------------------------------------------------+
class CSymbolContext
  {
private:
   string            m_symbol;
   int               m_digits;
   double            m_point;
   double            m_tickSize;
   double            m_tickValue;
   double            m_minLot;
   double            m_maxLot;
   double            m_lotStep;
   long              m_stopsLevel;
   long              m_freezeLevel;
   bool              m_ready;

public:
                     CSymbolContext();
   bool              Refresh(const string sym);
   bool              IsReady()            const { return(m_ready);       }
   string            Symbol()             const { return(m_symbol);      }
   int               Digits()             const { return(m_digits);      }
   double            Point()              const { return(m_point);       }
   double            MinLot()             const { return(m_minLot);      }
   double            MaxLot()             const { return(m_maxLot);      }
   double            LotStep()            const { return(m_lotStep);     }

   //--- live prices
   double            Ask()                const { return(SymbolInfoDouble(m_symbol,SYMBOL_ASK)); }
   double            Bid()                const { return(SymbolInfoDouble(m_symbol,SYMBOL_BID)); }
   double            SpreadPrice()        const { return(Ask()-Bid());   }
   double            SpreadPoints()       const { return(m_point>0.0 ? (Ask()-Bid())/m_point : 0.0); }

   //--- conversions
   double            PointsToPrice(const double pts)  const { return(pts*m_point); }
   double            PriceToPoints(const double dist) const { return(m_point>0.0 ? dist/m_point : 0.0); }
   double            NormalizePrice(const double p)   const { return(NormalizeDouble(p,m_digits)); }

   //--- money value of one point for one lot, in account currency
   double            ValuePerPointPerLot() const
     {
      if(m_tickSize<=0.0)
         return(0.0);
      return(m_tickValue*(m_point/m_tickSize));
     }

   //--- minimum distance the broker accepts between price and SL/TP
   double            MinStopPrice() const { return((double)m_stopsLevel*m_point); }
   double            FreezePrice()  const { return((double)m_freezeLevel*m_point); }

   //--- round a volume down onto the broker lot grid (never over-risk)
   double            NormalizeLotDown(const double lot) const
     {
      if(m_lotStep<=0.0)
         return(0.0);
      double steps=MathFloor(lot/m_lotStep+1e-8);
      double v=steps*m_lotStep;
      //--- lot step can be 0.01 -> keep 2 decimals clean
      v=NormalizeDouble(v,LotDigits());
      if(v>m_maxLot)
         v=m_maxLot;
      return(v);
     }

   int               LotDigits() const
     {
      if(m_lotStep<=0.0)
         return(2);
      int d=0;
      double s=m_lotStep;
      while(s<1.0 && d<8)
        {
         s*=10.0;
         d++;
        }
      return(d);
     }

   string            Describe() const;
  };

//+------------------------------------------------------------------+
CSymbolContext::CSymbolContext()
  {
   m_symbol="";
   m_digits=0;
   m_point=0.0;
   m_tickSize=0.0;
   m_tickValue=0.0;
   m_minLot=0.0;
   m_maxLot=0.0;
   m_lotStep=0.0;
   m_stopsLevel=0;
   m_freezeLevel=0;
   m_ready=false;
  }

//+------------------------------------------------------------------+
//| Reload every spec from the terminal. Call in OnInit and whenever |
//| the broker may have changed the contract (session rollover).     |
//+------------------------------------------------------------------+
bool CSymbolContext::Refresh(const string sym)
  {
   m_ready=false;
   m_symbol=sym;

   if(!SymbolSelect(sym,true))
     {
      PrintFormat("[ctx] SymbolSelect(%s) failed, err=%d",sym,GetLastError());
      return(false);
     }

   m_digits      = (int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   m_point       = SymbolInfoDouble(sym,SYMBOL_POINT);
   m_tickSize    = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   m_tickValue   = SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   m_minLot      = SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   m_maxLot      = SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   m_lotStep     = SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   m_stopsLevel  = SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
   m_freezeLevel = SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL);

   if(m_tickSize<=0.0)
      m_tickSize=m_point;

   if(m_point<=0.0 || m_lotStep<=0.0 || m_minLot<=0.0)
     {
      PrintFormat("[ctx] %s has invalid specs (point=%.10f lotStep=%.4f minLot=%.4f)",
                  sym,m_point,m_lotStep,m_minLot);
      return(false);
     }

   if(ValuePerPointPerLot()<=0.0)
     {
      //--- tick value is sometimes unavailable until the first tick arrives
      PrintFormat("[ctx] %s tick value not available yet (tickValue=%.5f)",sym,m_tickValue);
     }

   m_ready=true;
   return(true);
  }

//+------------------------------------------------------------------+
string CSymbolContext::Describe() const
  {
   return(StringFormat("%s digits=%d point=%.5f tickVal=%.5f ptVal/lot=%.5f "
                       "lots[%.2f..%.2f step %.2f] stopsLvl=%d freezeLvl=%d",
                       m_symbol,m_digits,m_point,m_tickValue,ValuePerPointPerLot(),
                       m_minLot,m_maxLot,m_lotStep,(int)m_stopsLevel,(int)m_freezeLevel));
  }

#endif // US100_SYMBOLCONTEXT_MQH
