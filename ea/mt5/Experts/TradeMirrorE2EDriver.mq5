//+------------------------------------------------------------------+
//| TradeMirrorE2EDriver.mq5                                         |
//| Test driver for the TradeMirror end-to-end suite (ea/mt5/e2e).   |
//|                                                                  |
//| Attach once to any chart of a DEMO terminal. The host runner     |
//| drops one JSON file per command into                              |
//|   MQL5\Files\TradeMirrorE2E\cmd\<id>.json                         |
//| The driver executes it, writes MQL5\Files\TradeMirrorE2E\ack\<id>.json
//| (atomic: temp file + FileMove) and deletes the command file. A   |
//| command whose ack already exists is never executed again.        |
//| Every second (and after each command) it writes status.json with |
//| account state, open positions and recent deals.                  |
//|                                                                  |
//| It refuses to trade unless ACCOUNT_TRADE_MODE is DEMO.           |
//+------------------------------------------------------------------+
#property copyright "mt5-web-replicator"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input int  PollMs        = 250;   // command poll interval (ms)
input int  StatusEveryMs = 1000;  // status.json refresh interval (ms)
input int  DealsHours    = 24;    // recent deals window reported in status.json
input int  MaxDeals      = 100;   // max recent deals reported
input int  SlippagePts   = 50;    // deviation for market orders (points)

#define E2E_DIR   "TradeMirrorE2E"
#define E2E_CMD   "TradeMirrorE2E\\cmd\\"
#define E2E_ACK   "TradeMirrorE2E\\ack\\"

CTrade   g_trade;
ulong    g_beat = 0;
ulong    g_last_status_ms = 0;
ulong    g_commands = 0;
string   g_last_cmd = "";

//--- JSON helpers -------------------------------------------------------------
string JsonEscape(const string s)
  {
   string r = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c == '"')       r += "\\\"";
      else if(c == '\\') r += "\\\\";
      else if(c == '\n') r += "\\n";
      else if(c == '\r') r += "\\r";
      else if(c == '\t') r += "\\t";
      else if(c < 32)    r += " ";
      else               r += ShortToString(c);
     }
   return r;
  }

string JStr(const string s) { return "\"" + JsonEscape(s) + "\""; }
string JNum(const double v, const int digits = 8) { return DoubleToString(v, digits); }
string JInt(const long v) { return IntegerToString(v); }
string JBool(const bool v) { return v ? "true" : "false"; }

// Value of a top-level key in a flat JSON object. Returns false when the key is absent or null.
bool JsonGet(const string json, const string key, string &out)
  {
   string pat = "\"" + key + "\"";
   int p = StringFind(json, pat);
   while(p >= 0)
     {
      int q = p + StringLen(pat);
      int n = StringLen(json);
      while(q < n && (StringGetCharacter(json, q) == ' ' || StringGetCharacter(json, q) == '\t'))
         q++;
      if(q < n && StringGetCharacter(json, q) == ':')
        {
         q++;
         while(q < n && (StringGetCharacter(json, q) == ' ' || StringGetCharacter(json, q) == '\t'))
            q++;
         if(q >= n)
            return false;
         if(StringGetCharacter(json, q) == '"')
           {
            string r = "";
            q++;
            while(q < n)
              {
               ushort c = StringGetCharacter(json, q);
               if(c == '\\' && q + 1 < n)
                 {
                  ushort d = StringGetCharacter(json, q + 1);
                  if(d == 'n') r += "\n";
                  else if(d == 't') r += "\t";
                  else r += ShortToString(d);
                  q += 2;
                  continue;
                 }
               if(c == '"')
                  break;
               r += ShortToString(c);
               q++;
              }
            out = r;
            return true;
           }
         int e = q;
         while(e < n)
           {
            ushort c = StringGetCharacter(json, e);
            if(c == ',' || c == '}' || c == ' ' || c == '\r' || c == '\n')
               break;
            e++;
           }
         out = StringSubstr(json, q, e - q);
         if(out == "null")
            return false;
         return true;
        }
      p = StringFind(json, pat, p + 1);
     }
   return false;
  }

string JsonStr(const string json, const string key, const string def = "")
  {
   string v;
   return JsonGet(json, key, v) ? v : def;
  }

double JsonDbl(const string json, const string key, const double def = 0.0)
  {
   string v;
   return JsonGet(json, key, v) ? StringToDouble(v) : def;
  }

long JsonLong(const string json, const string key, const long def = 0)
  {
   string v;
   return JsonGet(json, key, v) ? StringToInteger(v) : def;
  }

//--- files --------------------------------------------------------------------
string ReadText(const string path)
  {
   int h = FileOpen(path, FILE_READ | FILE_BIN | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return "";
   uchar buf[];
   int sz = (int)FileSize(h);
   string s = "";
   if(sz > 0 && FileReadArray(h, buf, 0, sz) > 0)
      s = CharArrayToString(buf, 0, WHOLE_ARRAY, CP_UTF8);
   FileClose(h);
   return s;
  }

// Write through a temp file and FileMove so a reader never sees a half-written file.
bool WriteAtomic(const string path, const string text)
  {
   string tmp = path + ".tmp";
   int h = FileOpen(tmp, FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("E2E driver: cannot open %s (%d)", tmp, GetLastError());
      return false;
     }
   uchar buf[];
   int n = StringToCharArray(text, buf, 0, WHOLE_ARRAY, CP_UTF8);
   if(n > 0)
      FileWriteArray(h, buf, 0, n - 1);   // drop the terminating zero
   FileFlush(h);
   FileClose(h);
   if(!FileMove(tmp, 0, path, FILE_REWRITE))
     {
      PrintFormat("E2E driver: FileMove %s failed (%d)", path, GetLastError());
      return false;
     }
   return true;
  }

bool IsDemo() { return AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO; }

//--- status -------------------------------------------------------------------
string PositionsJson()
  {
   string s = "[";
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t))
         continue;
      if(StringLen(s) > 1)
         s += ",";
      string sym = PositionGetString(POSITION_SYMBOL);
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      s += "{\"ticket\":" + JInt((long)t)
           + ",\"identifier\":" + JInt(PositionGetInteger(POSITION_IDENTIFIER))
           + ",\"symbol\":" + JStr(sym)
           + ",\"side\":" + JStr(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "buy" : "sell")
           + ",\"volume\":" + JNum(PositionGetDouble(POSITION_VOLUME), 2)
           + ",\"price_open\":" + JNum(PositionGetDouble(POSITION_PRICE_OPEN), dg)
           + ",\"sl\":" + JNum(PositionGetDouble(POSITION_SL), dg)
           + ",\"tp\":" + JNum(PositionGetDouble(POSITION_TP), dg)
           + ",\"magic\":" + JInt(PositionGetInteger(POSITION_MAGIC))
           + ",\"comment\":" + JStr(PositionGetString(POSITION_COMMENT))
           + ",\"time_msc\":" + JInt(PositionGetInteger(POSITION_TIME_MSC))
           + "}";
     }
   return s + "]";
  }

string DealsJson()
  {
   string s = "[";
   datetime to = TimeCurrent() + 3600;
   datetime from = to - (datetime)(DealsHours * 3600 + 3600);
   if(!HistorySelect(from, to))
      return "[]";
   int total = HistoryDealsTotal();
   int first = MathMax(0, total - MaxDeals);
   for(int i = first; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      long type = HistoryDealGetInteger(d, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;
      if(StringLen(s) > 1)
         s += ",";
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      string e = entry == DEAL_ENTRY_IN ? "in" : entry == DEAL_ENTRY_OUT ? "out" : entry == DEAL_ENTRY_INOUT ? "inout" : "out_by";
      s += "{\"ticket\":" + JInt((long)d)
           + ",\"order\":" + JInt(HistoryDealGetInteger(d, DEAL_ORDER))
           + ",\"position_id\":" + JInt(HistoryDealGetInteger(d, DEAL_POSITION_ID))
           + ",\"symbol\":" + JStr(HistoryDealGetString(d, DEAL_SYMBOL))
           + ",\"side\":" + JStr(type == DEAL_TYPE_BUY ? "buy" : "sell")
           + ",\"entry\":" + JStr(e)
           + ",\"volume\":" + JNum(HistoryDealGetDouble(d, DEAL_VOLUME), 2)
           + ",\"price\":" + JNum(HistoryDealGetDouble(d, DEAL_PRICE), 6)
           + ",\"magic\":" + JInt(HistoryDealGetInteger(d, DEAL_MAGIC))
           + ",\"comment\":" + JStr(HistoryDealGetString(d, DEAL_COMMENT))
           + ",\"reason\":" + JInt(HistoryDealGetInteger(d, DEAL_REASON))
           + ",\"time_msc\":" + JInt(HistoryDealGetInteger(d, DEAL_TIME_MSC))
           + "}";
     }
   return s + "]";
  }

void WriteStatus()
  {
   g_beat++;
   string s = "{\"driver\":\"TradeMirrorE2EDriver\",\"version\":\"1.00\""
              + ",\"beat\":" + JInt((long)g_beat)
              + ",\"commands\":" + JInt((long)g_commands)
              + ",\"last_command\":" + JStr(g_last_cmd)
              + ",\"login\":" + JInt(AccountInfoInteger(ACCOUNT_LOGIN))
              + ",\"server\":" + JStr(AccountInfoString(ACCOUNT_SERVER))
              + ",\"demo\":" + JBool(IsDemo())
              + ",\"margin_mode\":" + JStr(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "hedging" : "netting")
              + ",\"connected\":" + JBool(TerminalInfoInteger(TERMINAL_CONNECTED) != 0)
              + ",\"terminal_trade_allowed\":" + JBool(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0)
              + ",\"ea_trade_allowed\":" + JBool(MQLInfoInteger(MQL_TRADE_ALLOWED) != 0)
              + ",\"balance\":" + JNum(AccountInfoDouble(ACCOUNT_BALANCE), 2)
              + ",\"equity\":" + JNum(AccountInfoDouble(ACCOUNT_EQUITY), 2)
              + ",\"time_current\":" + JInt((long)TimeCurrent())
              + ",\"time_local\":" + JInt((long)TimeLocal())
              + ",\"positions\":" + PositionsJson()
              + ",\"orders_total\":" + JInt(OrdersTotal())
              + ",\"deals\":" + DealsJson()
              + "}";
   WriteAtomic(E2E_DIR + "\\status.json", s);
   g_last_status_ms = GetTickCount64();
  }

//--- trade operations ------------------------------------------------------------
string ResultJson()
  {
   return ",\"retcode\":" + JInt((long)g_trade.ResultRetcode())
          + ",\"retcode_text\":" + JStr(g_trade.ResultRetcodeDescription())
          + ",\"order\":" + JInt((long)g_trade.ResultOrder())
          + ",\"deal\":" + JInt((long)g_trade.ResultDeal())
          + ",\"price\":" + JNum(g_trade.ResultPrice(), 6);
  }

bool TradeOk()
  {
   uint rc = g_trade.ResultRetcode();
   return rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED;
  }

long PositionIdOfDeal(const ulong deal)
  {
   for(int i = 0; i < 20 && deal > 0; i++)
     {
      if(HistoryDealSelect(deal))
         return HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      HistorySelect(TimeCurrent() - 3600, TimeCurrent() + 3600);
      Sleep(50);
     }
   return 0;
  }

ulong FindPosition(const string cmd)
  {
   long ticket = JsonLong(cmd, "ticket", 0);
   if(ticket > 0)
      return PositionSelectByTicket((ulong)ticket) ? (ulong)ticket : 0;
   string comment = JsonStr(cmd, "comment", "");
   string symbol = JsonStr(cmd, "symbol", "");
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(comment != "" && PositionGetString(POSITION_COMMENT) != comment)
         continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if(comment == "" && symbol == "")
         continue;
      return t;
     }
   return 0;
  }

string Execute(const string cmd)
  {
   string op = JsonStr(cmd, "op", "");
   if(op == "ping")
      return "\"ok\":true";
   if(!IsDemo())
      return "\"ok\":false,\"error\":\"refused: account is not DEMO\"";

   g_trade.SetDeviationInPoints(SlippagePts);
   g_trade.SetAsyncMode(false);
   long magic = JsonLong(cmd, "magic", 0);
   g_trade.SetExpertMagicNumber((ulong)magic);

   if(op == "open")
     {
      string symbol = JsonStr(cmd, "symbol", _Symbol);
      string side = JsonStr(cmd, "side", "buy");
      double vol = JsonDbl(cmd, "volume", 0.01);
      double sl = JsonDbl(cmd, "sl", 0.0);
      double tp = JsonDbl(cmd, "tp", 0.0);
      string comment = JsonStr(cmd, "comment", "");
      if(!SymbolSelect(symbol, true))
         return "\"ok\":false,\"error\":\"symbol not found\"";
      g_trade.SetTypeFillingBySymbol(symbol);
      bool sent = side == "sell" ? g_trade.Sell(vol, symbol, 0.0, sl, tp, comment)
                  : g_trade.Buy(vol, symbol, 0.0, sl, tp, comment);
      bool ok = sent && TradeOk();
      long pos = ok ? PositionIdOfDeal(g_trade.ResultDeal()) : 0;
      return "\"ok\":" + JBool(ok) + ",\"position\":" + JInt(pos) + ResultJson();
     }
   if(op == "modify")
     {
      ulong t = FindPosition(cmd);
      if(t == 0)
         return "\"ok\":false,\"error\":\"position not found\"";
      double sl = JsonDbl(cmd, "sl", 0.0);
      double tp = JsonDbl(cmd, "tp", 0.0);
      bool ok = g_trade.PositionModify(t, sl, tp) && TradeOk();
      return "\"ok\":" + JBool(ok) + ",\"position\":" + JInt((long)t) + ResultJson();
     }
   if(op == "close" || op == "close_partial")
     {
      ulong t = FindPosition(cmd);
      if(t == 0)
         return "\"ok\":false,\"error\":\"position not found\"";
      g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL));
      bool ok;
      if(op == "close")
         ok = g_trade.PositionClose(t, (ulong)SlippagePts);
      else
         ok = g_trade.PositionClosePartial(t, JsonDbl(cmd, "volume", 0.0), (ulong)SlippagePts);
      ok = ok && TradeOk();
      return "\"ok\":" + JBool(ok) + ",\"position\":" + JInt((long)t) + ResultJson();
     }
   if(op == "close_all")
     {
      // Optional filters: symbol, magic (only when "magic" is present), comment_prefix.
      string symbol = JsonStr(cmd, "symbol", "");
      string prefix = JsonStr(cmd, "comment_prefix", "");
      string mv;
      bool by_magic = JsonGet(cmd, "magic", mv);
      int closed = 0, failed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol)
            continue;
         if(by_magic && PositionGetInteger(POSITION_MAGIC) != magic)
            continue;
         if(prefix != "" && StringFind(PositionGetString(POSITION_COMMENT), prefix) != 0)
            continue;
         g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL));
         if(g_trade.PositionClose(t, (ulong)SlippagePts) && TradeOk())
            closed++;
         else
            failed++;
        }
      return "\"ok\":" + JBool(failed == 0) + ",\"closed\":" + JInt(closed) + ",\"failed\":" + JInt(failed);
     }
   return "\"ok\":false,\"error\":\"unknown op\"";
  }

void ProcessCommands()
  {
   string name;
   long h = FileFindFirst(E2E_CMD + "*.json", name);
   if(h == INVALID_HANDLE)
      return;
   string names[];
   do
     {
      int n = ArraySize(names);
      ArrayResize(names, n + 1);
      names[n] = name;
     }
   while(FileFindNext(h, name));
   FileFindClose(h);
   ArraySort(names);   // ids are time-ordered, so files run in submission order

   for(int i = 0; i < ArraySize(names); i++)
     {
      string id = StringSubstr(names[i], 0, StringLen(names[i]) - 5);
      string cmd_path = E2E_CMD + names[i];
      string ack_path = E2E_ACK + names[i];
      if(FileIsExist(ack_path))
        {
         FileDelete(cmd_path);   // already executed: never trade twice
         continue;
        }
      string cmd = ReadText(cmd_path);
      if(StringLen(cmd) == 0 || StringFind(cmd, "}") < 0)
         continue;   // not fully written yet; retry next tick
      ulong t0 = GetTickCount64();
      string body = Execute(cmd);
      g_commands++;
      g_last_cmd = id;
      string ack = "{\"id\":" + JStr(id) + ",\"op\":" + JStr(JsonStr(cmd, "op", "")) + "," + body
                   + ",\"elapsed_ms\":" + JInt((long)(GetTickCount64() - t0))
                   + ",\"time_current\":" + JInt((long)TimeCurrent()) + "}";
      if(WriteAtomic(ack_path, ack))
         FileDelete(cmd_path);
      PrintFormat("E2E driver: %s -> %s", id, body);
      WriteStatus();
     }
  }

//--- events ---------------------------------------------------------------------
int OnInit()
  {
   FolderCreate(E2E_DIR);
   FolderCreate(E2E_DIR + "\\cmd");
   FolderCreate(E2E_DIR + "\\ack");
   if(!IsDemo())
      Print("E2E driver: account is not DEMO; all trade commands will be refused");
   EventSetMillisecondTimer(MathMax(50, PollMs));
   WriteStatus();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTimer()
  {
   ProcessCommands();
   if(GetTickCount64() - g_last_status_ms >= (ulong)StatusEveryMs)
      WriteStatus();
  }

void OnTick() {}
//+------------------------------------------------------------------+
