//+------------------------------------------------------------------+
//|                                          TradeMirrorSelfTest.mq5 |
//|  EA client tests for the Strategy Tester (design section 8).     |
//|  The Tester does not run WebRequest, so the real client engine   |
//|  runs against an injected in-memory fake server (ITransport).    |
//|  Covers S01-S06 (journal/outbox) and S24-S26 (transport, rotate, |
//|  enroll). Real trades are placed on the tester symbol.           |
//|                                                                  |
//|  Run: Strategy Tester, Expert = TradeMirrorSelfTest, a hedging   |
//|  account, any liquid symbol (EURUSD), "Every tick", 1 day.       |
//|  Result: PASS/FAIL lines in the tester Journal; OnTester() value |
//|  = number of failed checks (0 = all green).                      |
//+------------------------------------------------------------------+
#property copyright "TradeMirror"
#property version   "1.00"
#property description "TradeMirror client self-test (Strategy Tester only)."

#include <TradeMirror\Client.mqh>
#include <TradeMirror\TestTransport.mqh>

input double TestVolume = 0.01;   // lot used by the scenarios
input long   TestMagic  = 4242;   // copier magic used in the commands

CFakeServer g_fake;
int         g_failed = 0;
int         g_passed = 0;
bool        g_done = false;
string      g_runTag = "";

void Check(const string scenario, const bool cond, const string what)
  {
   if(cond) { g_passed++; PrintFormat("PASS %s: %s", scenario, what); }
   else     { g_failed++; PrintFormat("FAIL %s: %s", scenario, what); }
  }

CTradeMirror *NewEngine(const string tag, const bool enroll)
  {
   STmSettings s;
   s.server_url = "https://fake.test";
   s.role = TM_ROLE_SLAVE;
   s.enroll_code = enroll ? g_fake.code : "";
   s.force_enroll = enroll;
   s.rotate_days = 0;
   s.verbose = false;
   s.popups = false;
   s.file_tag = g_runTag + tag;
   CTradeMirror *tm = new CTradeMirror();
   tm.Init(s, GetPointer(g_fake));
   return tm;
  }

void Ticks(CTradeMirror *tm, const int n)
  {
   for(int i = 0; i < n; i++)
     {
      g_tm_fake_now_ms += 1000;
      tm.OnTimerTick();
      CExecutor *ex = tm.Exec();
      if(ex.m_crashed)
         return;
     }
  }

bool UntilSession(CTradeMirror *tm)
  {
   for(int i = 0; i < 30 && tm.SessionId() == ""; i++)
      Ticks(tm, 1);
   return tm.SessionId() != "";
  }

int PositionsWithComment(const string comment)
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_COMMENT) == comment)
         n++;
   return n;
  }

ulong PositionIdWithComment(const string comment)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_COMMENT) == comment)
         return (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   return 0;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r); ZeroMemory(res);
      MqlTick tick; SymbolInfoTick(PositionGetString(POSITION_SYMBOL), tick);
      bool sell = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      r.action = TRADE_ACTION_DEAL; r.position = t; r.symbol = PositionGetString(POSITION_SYMBOL);
      r.volume = PositionGetDouble(POSITION_VOLUME); r.type = sell ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      r.price = sell ? tick.bid : tick.ask; r.deviation = 50; r.type_filling = TmFilling(r.symbol);
      if(!OrderSend(r, res))
         PrintFormat("cleanup close of %I64u failed: %u", t, res.retcode);
     }
  }

string OpenCmd(const string id, const long copyId)
  {
   MqlTick t;
   SymbolInfoTick(_Symbol, t);
   CJsonWriter w;
   w.BeginObj();
   w.Str("command_id", id);
   w.Str("attempt_id", "a_" + id);
   w.Str("action", "open");
   w.Int("copy_id", copyId);
   w.Int("seq_in_copy", 1);
   w.Str("symbol", _Symbol);
   w.Str("side", "buy");
   w.Num("volume", TestVolume);
   w.Num("master_price", t.ask, _Digits);
   w.Null("sl");
   w.Null("tp");
   w.Int("max_slippage_points", 50);
   w.Null("max_entry_deviation_points");
   w.Null("position_id");
   w.Int("magic", TestMagic);
   w.Str("comment", "c" + IntegerToString(copyId));
   w.Int("issued_at", g_tm_fake_now_ms);
   w.Int("expires_at", g_tm_fake_now_ms + 600000);
   w.EndObj();
   return w.Text();
  }

string CancelCmd(const string id, const long copyId, const string openId)
  {
   CJsonWriter w;
   w.BeginObj();
   w.Str("command_id", id);
   w.Str("attempt_id", "a_" + id);
   w.Str("action", "cancel");
   w.Int("copy_id", copyId);
   w.Int("seq_in_copy", 2);
   w.Str("symbol", _Symbol);
   w.Null("position_id");
   w.Str("open_command_id", openId);
   w.Int("magic", TestMagic);
   w.Str("comment", "c" + IntegerToString(copyId));
   w.Str("reason", "master_closed");
   w.Int("issued_at", g_tm_fake_now_ms);
   w.Null("expires_at");
   w.EndObj();
   return w.Text();
  }

//--- S01: lost result after OrderSend; open re-delivered -> result re-sent, one position
void S01()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s01", true);
   Check("S01", UntilSession(tm), "enrolled + session");
   g_fake.Queue("c_s01", OpenCmd("c_s01", 9101));
   g_fake.dropResults = 1;                      // the first results POST is processed, reply lost
   Ticks(tm, 12);
   Check("S01", PositionsWithComment("c9101") == 1, "one position after the lost reply");
   g_fake.Redeliver("c_s01");                   // lease expired: the server delivers the open again
   Ticks(tm, 12);
   Check("S01", PositionsWithComment("c9101") == 1, "still one position after re-delivery (never re-executed)");
   Check("S01", g_fake.CountResults("c_s01", "done") >= 2, "stored done result re-sent");
   Check("S01", StringFind(g_fake.LastResult("c_s01", "done"), "\"position_id\":") >= 0, "done carries position_id");
   Check("S01", tm.Outbox().Count() == 0, "outbox drained after 2xx");
   delete tm;
   CloseAll();
  }

//--- S02: crash before OrderSend (journal prepared) -> restart executes once
void S02()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s02", true);
   UntilSession(tm);
   g_fake.Queue("c_s02", OpenCmd("c_s02", 9102));
   CExecutor *ex = tm.Exec();
   ex.m_crash = TM_CRASH_AFTER_PREPARED;
   Ticks(tm, 6);
   Check("S02", ex.m_crashed, "crashed after prepared");
   Check("S02", PositionsWithComment("c9102") == 0, "nothing sent before the crash");
   delete tm;                                   // process dies; files stay
   tm = NewEngine("s02", false);
   g_fake.Redeliver("c_s02");
   UntilSession(tm);
   Ticks(tm, 12);
   Check("S02", PositionsWithComment("c9102") == 1, "executed exactly once after restart");
   Check("S02", g_fake.CountResults("c_s02", "done") >= 1, "done reported");
   delete tm;
   CloseAll();
  }

//--- S03: crash after OrderSend before confirmed -> uncertain -> scan finds c<id> -> done, no second order
void S03()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s03", true);
   UntilSession(tm);
   g_fake.Queue("c_s03", OpenCmd("c_s03", 9103));
   CExecutor *ex = tm.Exec();
   ex.m_crash = TM_CRASH_AFTER_ORDERSEND;
   Ticks(tm, 6);
   Check("S03", ex.m_crashed, "crashed after OrderSend");
   Check("S03", PositionsWithComment("c9103") == 1, "order reached the broker");
   delete tm;
   tm = NewEngine("s03", false);
   g_fake.Redeliver("c_s03");
   UntilSession(tm);
   Ticks(tm, 12);
   Check("S03", PositionsWithComment("c9103") == 1, "no second order");
   string done = g_fake.LastResult("c_s03", "done");
   Check("S03", done != "" && StringFind(done, "\"position_id\":" + IntegerToString((long)PositionIdWithComment("c9103"))) >= 0,
         "done with the real position_id");
   delete tm;
   CloseAll();
  }

//--- S04: ambiguous execution (no evidence visible) -> suspended + uncertain; later evidence -> done
void S04()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s04", true);
   UntilSession(tm);
   g_fake.Queue("c_s04", OpenCmd("c_s04", 9104));
   CExecutor *ex = tm.Exec();
   ex.m_crash = TM_CRASH_AFTER_ORDERSEND;
   Ticks(tm, 6);
   delete tm;
   g_tm_hide_evidence = true;                   // broker rewrote the comment, ids lost
   tm = NewEngine("s04", false);
   g_fake.Redeliver("c_s04");
   UntilSession(tm);
   Ticks(tm, 40);
   Check("S04", tm.Exec().CountState(JS_SUSPENDED) == 1, "journal entry suspended");
   Check("S04", g_fake.CountResults("c_s04", "uncertain") >= 1, "result uncertain reported");
   Check("S04", g_fake.CountResults("c_s04", "failed") == 0, "never reported not executed");
   Check("S04", PositionsWithComment("c9104") == 1, "no second order while suspended");
   g_tm_hide_evidence = false;                  // evidence becomes visible (late fill / adoption)
   Ticks(tm, 25);
   Check("S04", g_fake.CountResults("c_s04", "done") >= 1, "late evidence -> done");
   Check("S04", tm.Exec().CountState(JS_SUSPENDED) == 0, "suspension cleared");
   delete tm;
   CloseAll();
  }

//--- S05: cancel after execution -> EA closes the position and reports closed
void S05()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s05", true);
   UntilSession(tm);
   g_fake.Queue("c_s05", OpenCmd("c_s05", 9105));
   Ticks(tm, 10);
   Check("S05", PositionsWithComment("c9105") == 1, "open executed");
   g_fake.Queue("x_s05", CancelCmd("x_s05", 9105, "c_s05"));
   Ticks(tm, 12);
   Check("S05", PositionsWithComment("c9105") == 0, "position closed by the cancel");
   string closed = g_fake.LastResult("x_s05", "closed");
   Check("S05", closed != "" && StringFind(closed, "\"deal\":") >= 0, "cancel reported closed with the close deal");
   // cancel of an open that never reached the terminal -> not_executed
   g_fake.Queue("x_s05b", CancelCmd("x_s05b", 9115, "c_never"));
   Ticks(tm, 10);
   Check("S05", g_fake.CountResults("x_s05b", "not_executed") == 1, "cancel of a never-sent open -> not_executed");
   delete tm;
   CloseAll();
  }

//--- S06: journal entry round-trips through Save + reload (Open), including a NULL result
void S06()
  {
   string path = "TradeMirror\\" + g_runTag + "s06_journal_roundtrip.jsonl";
   FileDelete(path);
   CJournal *j = new CJournal();
   Check("S06", j.Open(path), "open empty journal");
   CJournalEntry *e = j.Create("c_s06", "a_c_s06", 9106, "open", 1, OpenCmd("c_s06", 9106));
   e.state = JS_UNCERTAIN;                      // result left unassigned (NULL string)
   e.order = 9000000000123;
   e.request_id = 77;
   e.position_id = 9000000000456;
   e.executed_volume = 0.01;
   e.sent_ms = 1234;
   e.checks = 2;
   Check("S06", j.Save(e), "entry saved");
   delete j;
   j = new CJournal();
   Check("S06", j.Open(path), "journal reopened");
   Check("S06", j.Total() == 1, "one entry reloaded");
   CJournalEntry *r = j.Find("c_s06", "a_c_s06");
   Check("S06", r != NULL && r.state == JS_UNCERTAIN && r.copy_id == 9106 && r.action == "open" && r.seq_in_copy == 1,
         "identity and state preserved");
   Check("S06", r != NULL && r.order == 9000000000123 && r.request_id == 77 && r.position_id == 9000000000456 &&
         r.executed_volume == 0.01 && r.sent_ms == 1234 && r.checks == 2, "execution fields preserved (64-bit ids)");
   Check("S06", r != NULL && StringFind(r.command, "\"command_id\":\"c_s06\"") >= 0 && StringLen(r.result) == 0,
         "command kept, empty result stays empty");
   if(r != NULL)
     {
      r.result = "{\"status\":\"done\"}";
      r.state = JS_CONFIRMED;
      j.Save(r);
     }
   delete j;
   j = new CJournal();
   j.Open(path);
   r = j.Find("c_s06", "a_c_s06");
   Check("S06", j.Total() == 1 && r != NULL && r.state == JS_CONFIRMED && r.result == "{\"status\":\"done\"}",
         "last line wins, result JSON preserved");
   delete j;
   FileDelete(path);
  }

//--- S24: 429 forever with a huge Retry-After on results -> EA keeps ticking, other routes continue, outbox retained
void S24()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s24", true);
   UntilSession(tm);
   g_fake.fail429Path = "/v4/slave/results";
   g_fake.retryAfterSec = 3600;
   g_fake.Queue("c_s24", OpenCmd("c_s24", 9124));
   Ticks(tm, 10);
   int polls = g_fake.commandPolls;
   int resultPosts = g_fake.resultPosts;
   Ticks(tm, 60);
   Check("S24", g_fake.commandPolls > polls, "commands poll continues while results are rate limited");
   Check("S24", g_fake.resultPosts == resultPosts, "results route respects Retry-After (no calls)");
   Check("S24", tm.Outbox().Count() > 0, "results retained in the outbox");
   Check("S24", PositionsWithComment("c9124") == 1, "execution not blocked by HTTP");
   Check("S24", tm.HttpCalls() <= 10 + 60 + 30, "at most one HTTP call per tick");
   g_fake.fail429Path = "";
   delete tm;
   tm = NewEngine("s24", false);                // restart: the outbox survives on disk
   Check("S24", tm.Outbox().Count() > 0, "outbox persisted across restart");
   UntilSession(tm);
   Ticks(tm, 10);
   Check("S24", tm.Outbox().Count() == 0 && g_fake.CountResults("c_s24", "done") >= 1, "results delivered after recovery");
   delete tm;
   CloseAll();
  }

//--- S25: rotate response lost -> old token still works; replay -> 409 rotation_pending -> restart -> confirm
void S25()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s25", true);
   UntilSession(tm);
   string oldToken = tm.Token().token;
   g_fake.dropNextRotate = true;
   tm.ForceRotate();
   Ticks(tm, 2);
   Check("S25", g_fake.pendingToken != "" && tm.Token().pending_token == "", "rotation pending on the server, nothing on disk");
   Check("S25", g_fake.token == oldToken, "old token still valid");
   Ticks(tm, 25);
   Check("S25", tm.Token().token == g_fake.token && tm.Token().token != oldToken, "new token confirmed and in use");
   Check("S25", g_fake.TokenRetired(oldToken), "old token revoked by confirm");
   Check("S25", g_fake.pendingToken == "", "no rotation left pending");
   CTokenStore disk;
   disk.SetPath(tm.Token().Path());
   disk.Load();
   Check("S25", disk.token == g_fake.token, "token file holds the new token");
   delete tm;
  }

//--- S26: enroll response lost -> same code re-enrolls; code consumed on first authenticated call
void S26()
  {
   g_fake.Reset();
   g_fake.dropNextEnroll = true;
   CTradeMirror *tm = NewEngine("s26", true);
   Ticks(tm, 4);
   Check("S26", g_fake.enrollCalls >= 2, "enroll retried after the lost response");
   Check("S26", tm.Token().token == g_fake.token, "token from the second enroll stored");
   Check("S26", g_fake.TokenRetired(tm.Token().token) == false, "stored token is live");
   UntilSession(tm);
   Check("S26", g_fake.codeConsumed, "code consumed on the first authenticated call");
   delete tm;
  }

int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER))
     {
      Print("TradeMirrorSelfTest runs only in the Strategy Tester");
      return INIT_FAILED;
     }
   if(!TmIsHedging())
      Print("WARNING: run the self-test on a hedging account");
   g_runTag = "st" + IntegerToString((long)TimeLocal());
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   if(g_done)
      return;
   g_done = true;
   g_tm_fake_now_ms = (long)TimeCurrent() * 1000;
   S01(); S02(); S03(); S04(); S05(); S06(); S24(); S25(); S26();
   g_tm_fake_now_ms = 0;
   PrintFormat("TradeMirror self-test: %d passed, %d failed", g_passed, g_failed);
  }

double OnTester()
  {
   return (double)g_failed;
  }
