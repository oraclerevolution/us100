//+------------------------------------------------------------------+
//|                                                SessionFilter.mqh |
//|   Restricts activity to one intraday window, expressed in        |
//|   BROKER SERVER TIME. Supports windows that cross midnight.      |
//+------------------------------------------------------------------+
#ifndef US100_SESSIONFILTER_MQH
#define US100_SESSIONFILTER_MQH

//+------------------------------------------------------------------+
class CSessionFilter
  {
private:
   int               m_startMin;        // minutes from midnight
   int               m_endMin;
   int               m_warmupMin;       // skip N minutes after the open
   int               m_cutoffMin;       // no new entries N minutes before close
   bool              m_days[7];         // index 0 = Sunday .. 6 = Saturday

   static int        MinuteOfDay(const datetime t)
     {
      MqlDateTime s;
      TimeToStruct(t,s);
      return(s.hour*60+s.min);
     }

   static int        DayOfWeekOf(const datetime t)
     {
      MqlDateTime s;
      TimeToStruct(t,s);
      return(s.day_of_week);
     }

   //--- half open interval [a,b) with wrap-around support
   static bool       InWindow(const int cur,const int a,const int b)
     {
      if(a==b)
         return(true);               // 24h window
      if(a<b)
         return(cur>=a && cur<b);
      return(cur>=a || cur<b);       // crosses midnight
     }

public:
                     CSessionFilter();
   void              Configure(const int startHour,const int startMin,
                               const int endHour,const int endMin,
                               const int warmupMin,const int cutoffMin);
   void              SetDay(const int dayOfWeek,const bool enabled);

   bool              IsTradingDay(const datetime t) const;
   bool              InSession(const datetime t)    const;
   bool              CanOpenNew(const datetime t)   const;
   int               MinutesIntoSession(const datetime t) const;
   string            Describe() const;
  };

//+------------------------------------------------------------------+
CSessionFilter::CSessionFilter()
  {
   m_startMin  = 15*60+30;
   m_endMin    = 22*60;
   m_warmupMin = 15;
   m_cutoffMin = 30;
   for(int i=0;i<7;i++)
      m_days[i]=(i>=1 && i<=5);      // Monday..Friday
  }

//+------------------------------------------------------------------+
void CSessionFilter::Configure(const int startHour,const int startMin,
                               const int endHour,const int endMin,
                               const int warmupMin,const int cutoffMin)
  {
   m_startMin  = ((startHour%24)+24)%24*60 + (int)MathMax(0,MathMin(59,startMin));
   m_endMin    = ((endHour%24)+24)%24*60   + (int)MathMax(0,MathMin(59,endMin));
   m_warmupMin = (int)MathMax(0,warmupMin);
   m_cutoffMin = (int)MathMax(0,cutoffMin);
  }

//+------------------------------------------------------------------+
void CSessionFilter::SetDay(const int dayOfWeek,const bool enabled)
  {
   if(dayOfWeek<0 || dayOfWeek>6)
      return;
   m_days[dayOfWeek]=enabled;
  }

//+------------------------------------------------------------------+
bool CSessionFilter::IsTradingDay(const datetime t) const
  {
   int d=DayOfWeekOf(t);
   if(d<0 || d>6)
      return(false);
   return(m_days[d]);
  }

//+------------------------------------------------------------------+
//| Inside the raw session window (used for management and flattening)|
//+------------------------------------------------------------------+
bool CSessionFilter::InSession(const datetime t) const
  {
   if(!IsTradingDay(t))
      return(false);
   return(InWindow(MinuteOfDay(t),m_startMin,m_endMin));
  }

//+------------------------------------------------------------------+
//| Inside the narrower window where NEW entries are allowed          |
//+------------------------------------------------------------------+
bool CSessionFilter::CanOpenNew(const datetime t) const
  {
   if(!InSession(t))
      return(false);

   int into=MinutesIntoSession(t);
   if(into<m_warmupMin)
      return(false);

   int total=m_endMin-m_startMin;
   if(total<=0)
      total+=24*60;

   return(into<=(total-m_cutoffMin));
  }

//+------------------------------------------------------------------+
int CSessionFilter::MinutesIntoSession(const datetime t) const
  {
   int cur=MinuteOfDay(t);
   int into=cur-m_startMin;
   if(into<0)
      into+=24*60;
   return(into);
  }

//+------------------------------------------------------------------+
string CSessionFilter::Describe() const
  {
   return(StringFormat("%02d:%02d-%02d:%02d server (warmup %dm, cutoff %dm)",
                       m_startMin/60,m_startMin%60,m_endMin/60,m_endMin%60,
                       m_warmupMin,m_cutoffMin));
  }

#endif // US100_SESSIONFILTER_MQH
