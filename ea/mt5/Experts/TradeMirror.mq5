//+------------------------------------------------------------------+
//|                                                  TradeMirror.mq5 |
//|  Copy-trading client for the TradeMirror Copy Server (protocol v4)|
//|  One EA, two roles: Master (publishes positions) or Slave        |
//|  (executes copy commands with a durable journal + outbox).       |
//+------------------------------------------------------------------+
#property copyright "TradeMirror"
#property version   "1.00"
#property description "TradeMirror copy client (v4). Role Master publishes positions; role Slave executes copies."
#property description "Add the server URL to Tools > Options > Expert Advisors > Allow WebRequest."

#include <TradeMirror\Client.mqh>

input string        ServerUrl     = "https://copy.example.com"; // Copy Server URL (https; http only for localhost)
input ENUM_TM_ROLE  Role          = TM_ROLE_SLAVE;              // Role of this terminal
input string        EnrollCode    = "";                         // One-time enrollment code from the admin
input bool          ForceReEnroll = false;                      // Enroll again even if a token file exists
input int           TokenRotateDays = 30;                       // Rotate the token every N days (0 = never)
input bool          VerboseLog    = false;                      // Debug lines in the Experts log
input bool          AlertPopups   = true;                       // Show alerts as terminal pop-ups

CWebRequestTransport g_transport;
CTradeMirror         g_tm;

int OnInit()
  {
   if(MQLInfoInteger(MQL_TESTER))
     {
      Print("TradeMirror: WebRequest does not run in the Strategy Tester. Use TradeMirrorSelfTest for tester runs.");
      return INIT_FAILED;
     }
   STmSettings s;
   s.server_url = ServerUrl;
   while(StringLen(s.server_url) > 0 && StringGetCharacter(s.server_url, StringLen(s.server_url) - 1) == '/')
      s.server_url = StringSubstr(s.server_url, 0, StringLen(s.server_url) - 1);
   s.role = Role;
   s.enroll_code = EnrollCode;
   StringTrimLeft(s.enroll_code);
   StringTrimRight(s.enroll_code);
   s.force_enroll = ForceReEnroll;
   s.rotate_days = TokenRotateDays;
   s.verbose = VerboseLog;
   s.popups = AlertPopups;
   s.file_tag = "";
   if(!g_tm.Init(s, GetPointer(g_transport)))
      return INIT_PARAMETERS_INCORRECT;
   EventSetTimer(1);   // 4.2: one tick per second, at most one HTTP call per tick
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

void OnTimer()
  {
   g_tm.OnTimerTick();
   Comment(g_tm.Status());
  }

void OnTrade()
  {
   g_tm.OnTradeEvent();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   g_tm.OnTransaction(trans, request, result);
  }
