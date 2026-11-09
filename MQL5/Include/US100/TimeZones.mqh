//+------------------------------------------------------------------+
//|                                                    TimeZones.mqh |
//|                                                                  |
//|  Converts a New York cash session into broker server minutes.    |
//|                                                                  |
//|  Why this file exists: the NYSE session is defined in New York   |
//|  time, the EA sees broker server time, and the two sides change  |
//|  their clocks on DIFFERENT dates (US: 2nd Sunday of March to     |
//|  1st Sunday of November, EU: last Sunday of March to last        |
//|  Sunday of October). Getting this wrong shifts every entry by    |
//|  an hour for a few weeks a year, and the error is invisible in   |
//|  a backtest that uses the same wrong offset.                     |
//|                                                                  |
//|  Everything here is computed from the calendar, never from       |
//|  TimeGMT() or TimeLocal(), because those are not reliable in     |
//|  the Strategy Tester. The result is therefore identical in       |
//|  backtest and in live trading.                                   |
//+------------------------------------------------------------------+
#ifndef US100_TIMEZONES_MQH
#define US100_TIMEZONES_MQH

//+------------------------------------------------------------------+
//| Date of the nth Sunday of a month at 00:00 UTC.                  |
//| nth = 1..4, or -1 for the last Sunday of the month.              |
//+------------------------------------------------------------------+
datetime TZ_SundayOfMonth(const int year,const int month,const int nth)
  {
   MqlDateTime s;
   s.year=year;
   s.mon=month;
   s.day=1;
   s.hour=0;
   s.min=0;
   s.sec=0;

   datetime first=StructToTime(s);
   TimeToStruct(first,s);

   if(nth>0)
     {
      int shift=(7-s.day_of_week)%7;                 // days until the 1st Sunday
      return(first+(datetime)(shift+7*(nth-1))*86400);
     }

   //--- last Sunday: start from the 1st of the next month and step back
   int ny=(month==12 ? year+1 : year);
   int nm=(month==12 ? 1     : month+1);
   MqlDateTime t;
   t.year=ny;
   t.mon=nm;
   t.day=1;
   t.hour=0;
   t.min=0;
   t.sec=0;
   datetime nextFirst=StructToTime(t);
   TimeToStruct(nextFirst,t);
   int back=(t.day_of_week==0 ? 7 : t.day_of_week);
   return(nextFirst-(datetime)back*86400);
  }

//+------------------------------------------------------------------+
//| European summer time: last Sunday of March 01:00 UTC             |
//|                   to  last Sunday of October 01:00 UTC           |
//+------------------------------------------------------------------+
bool TZ_IsEuDst(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(utc,s);

   datetime start=TZ_SundayOfMonth(s.year,3,-1)+3600;    // 01:00 UTC
   datetime end  =TZ_SundayOfMonth(s.year,10,-1)+3600;   // 01:00 UTC

   return(utc>=start && utc<end);
  }

//+------------------------------------------------------------------+
//| US daylight saving: 2nd Sunday of March 07:00 UTC                |
//|                 to  1st Sunday of November 06:00 UTC             |
//+------------------------------------------------------------------+
bool TZ_IsUsDst(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(utc,s);

   datetime start=TZ_SundayOfMonth(s.year,3,2)+7*3600;   // 02:00 EST = 07:00 UTC
   datetime end  =TZ_SundayOfMonth(s.year,11,1)+6*3600;  // 02:00 EDT = 06:00 UTC

   return(utc>=start && utc<end);
  }

//+------------------------------------------------------------------+
//| New York UTC offset in hours: -4 in summer, -5 in winter         |
//+------------------------------------------------------------------+
int TZ_NewYorkOffsetHours(const datetime utc)
  {
   return(TZ_IsUsDst(utc) ? -4 : -5);
  }

//+------------------------------------------------------------------+
//| Broker UTC offset in hours for a given server timestamp.         |
//| gmtWinter / gmtSummer describe the broker: most MT5 brokers run  |
//| GMT+2 in winter and GMT+3 in summer (they follow EU dates).      |
//| A broker that never shifts its clock just gets the same value    |
//| in both inputs.                                                  |
//+------------------------------------------------------------------+
int TZ_BrokerOffsetHours(const datetime serverTime,const int gmtWinter,const int gmtSummer)
  {
   if(gmtWinter==gmtSummer)
      return(gmtWinter);

   //--- the offset depends on UTC, which depends on the offset; one
   //--- approximation is enough, the two only disagree inside the
   //--- single hour of the switch itself
   datetime approxUtc=serverTime-(datetime)gmtWinter*3600;
   return(TZ_IsEuDst(approxUtc) ? gmtSummer : gmtWinter);
  }

//+------------------------------------------------------------------+
//| Convert a New York minute-of-day into a server minute-of-day     |
//+------------------------------------------------------------------+
int TZ_NyMinuteToServerMinute(const int nyMinuteOfDay,
                              const datetime serverTime,
                              const int gmtWinter,
                              const int gmtSummer)
  {
   int brokerOff=TZ_BrokerOffsetHours(serverTime,gmtWinter,gmtSummer);
   datetime utc=serverTime-(datetime)brokerOff*3600;
   int nyOff=TZ_NewYorkOffsetHours(utc);

   //--- NY local = UTC + nyOff  ->  UTC = NY local - nyOff
   //--- server   = UTC + brokerOff
   int m=nyMinuteOfDay-nyOff*60+brokerOff*60;
   m%=1440;
   if(m<0)
      m+=1440;
   return(m);
  }

#endif // US100_TIMEZONES_MQH
