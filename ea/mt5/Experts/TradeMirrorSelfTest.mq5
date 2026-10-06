//+------------------------------------------------------------------+
//|                                          TradeMirrorSelfTest.mq5 |
//|  EA client tests for the Strategy Tester (design section 8).     |
//|  The Tester does not run WebRequest, so the real client engine   |
//|  runs against an injected in-memory fake server (ITransport).    |
//|  Covers S01-S06 (journal/outbox) and S24-S26 (transport, rotate, |
//|  enroll), S27-S28 (comment correlation), S29 (latency schedule), |
//|  S30 (per-server state files + migration), S31 (WebRequest errors). Real trades are placed on the tester symbol.           |
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
   s.min_gap_ms = 300;
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

// Server comment shape: c<copy_id>-<master position_id> (design 5.8a).
string TestComment(const long copyId) { return "c" + IntegerToString(copyId) + "-" + IntegerToString(700000 + copyId); }

// A position placed directly (as the broker would hold it), with an arbitrary comment.
ulong PlaceRaw(const string comment)
  {
   MqlTradeRequest r; MqlTradeResult res; ZeroMemory(r); ZeroMemory(res);
   MqlTick tick; SymbolInfoTick(_Symbol, tick);
   r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol; r.volume = TestVolume; r.type = ORDER_TYPE_BUY;
   r.price = tick.ask; r.deviation = 50; r.type_filling = TmFilling(_Symbol); r.magic = TestMagic;
   r.comment = comment;
   if(!OrderSend(r, res) || res.deal == 0)
      return 0;
   return PositionIdWithComment(comment);
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
   w.Str("comment", TestComment(copyId));
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
   w.Str("comment", TestComment(copyId));
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
   Check("S01", PositionsWithComment(TestComment(9101)) == 1, "one position after the lost reply");
   g_fake.Redeliver("c_s01");                   // lease expired: the server delivers the open again
   Ticks(tm, 12);
   Check("S01", PositionsWithComment(TestComment(9101)) == 1, "still one position after re-delivery (never re-executed)");
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
   Check("S02", PositionsWithComment(TestComment(9102)) == 0, "nothing sent before the crash");
   delete tm;                                   // process dies; files stay
   tm = NewEngine("s02", false);
   g_fake.Redeliver("c_s02");
   UntilSession(tm);
   Ticks(tm, 12);
   Check("S02", PositionsWithComment(TestComment(9102)) == 1, "executed exactly once after restart");
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
   Check("S03", PositionsWithComment(TestComment(9103)) == 1, "order reached the broker");
   delete tm;
   tm = NewEngine("s03", false);
   g_fake.Redeliver("c_s03");
   UntilSession(tm);
   Ticks(tm, 12);
   Check("S03", PositionsWithComment(TestComment(9103)) == 1, "no second order");
   string done = g_fake.LastResult("c_s03", "done");
   Check("S03", done != "" && StringFind(done, "\"position_id\":" + IntegerToString((long)PositionIdWithComment(TestComment(9103)))) >= 0,
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
   Check("S04", PositionsWithComment(TestComment(9104)) == 1, "no second order while suspended");
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
   Check("S05", PositionsWithComment(TestComment(9105)) == 1, "open executed");
   g_fake.Queue("x_s05", CancelCmd("x_s05", 9105, "c_s05"));
   Ticks(tm, 12);
   Check("S05", PositionsWithComment(TestComment(9105)) == 0, "position closed by the cancel");
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
   Check("S24", PositionsWithComment(TestComment(9124)) == 1, "execution not blocked by HTTP");
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

//--- S27: comment correlation rule (pure): only the c<copy_id> part counts
void S27()
  {
   Check("S27", TmCommentMatches("c13-9001", "c13-9001"), "full comment");
   Check("S27", TmCommentMatches("c13-9001", "c13-90"), "suffix truncated");
   Check("S27", TmCommentMatches("c13-9001", "c13-"), "truncated right after '-'");
   Check("S27", TmCommentMatches("c13-9001", "c13-9001[sl 1.1]"), "suffix rewritten");
   Check("S27", !TmCommentMatches("c13-9001", "c13"), "bare id for a long-form command is ambiguous");
   Check("S27", !TmCommentMatches("c13-9001", "c1"), "cut inside the digits never matches");
   Check("S27", !TmCommentMatches("c13-9001", "c14-9001"), "wrong copy id");
   Check("S27", !TmCommentMatches("c13-9001", "c130-9001"), "longer id with the same prefix");
   Check("S27", !TmCommentMatches("c13-9001", "manual"), "not a copier comment");
   Check("S27", TmCommentMatches("c13", "c13"), "legacy c<id>");
   Check("S27", TmCommentMatches("c13", "c13-5"), "legacy command, broker appended a suffix");
   Check("S27", !TmCommentMatches("c13", "c13x"), "legacy command, garbage after the digits");
  }

//--- S28: broker truncated/rewrote the comment suffix -> the open is found by c<copy_id> + magic,
//    never re-sent; a bare c<copy_id> for a long-form command is not taken as evidence.
void S28Case(const string tag, const long copyId, const string brokerComment, const bool expectAdopt)
  {
   string scen = "S28" + tag;
   ulong pid = PlaceRaw(brokerComment);
   Check(scen, pid != 0, "broker-side position placed with comment " + brokerComment);
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s28" + tag, true);
   UntilSession(tm);
   string id = "c_s28" + tag;
   g_fake.Queue(id, OpenCmd(id, copyId));
   Ticks(tm, 12);
   string done = g_fake.LastResult(id, "done");
   if(expectAdopt)
     {
      Check(scen, PositionsWithComment(TestComment(copyId)) == 0, "no second order");
      Check(scen, done != "" && StringFind(done, "\"position_id\":" + IntegerToString((long)pid)) >= 0,
            "done with the existing position_id");
     }
   else
     {
      Check(scen, PositionsWithComment(TestComment(copyId)) == 1, "ambiguous evidence ignored: order sent");
      Check(scen, done != "" && StringFind(done, "\"position_id\":" + IntegerToString((long)pid)) < 0,
            "not correlated with the ambiguous position");
     }
   delete tm;
   CloseAll();
  }

void S28()
  {
   S28Case("a", 9128, "c9128-7", true);               // suffix truncated
   S28Case("b", 9129, "c9129-x[sl]", true);           // suffix rewritten
   S28Case("c", 9130, "c9130", false);                // bare id: ambiguous for a long-form command
  }

//--- S29: latency scheduling with a short tick: the commands poll keeps its interval (not one call per tick),
//    a received command executes and its result goes out on the next ticks, followed by one immediate re-poll.
void TicksMs(CTradeMirror *tm, const int n, const int stepMs)
  {
   for(int i = 0; i < n; i++)
     {
      g_tm_fake_now_ms += stepMs;
      tm.OnTimerTick();
     }
  }

void S29()
  {
   g_fake.Reset();
   CTradeMirror *tm = NewEngine("s29", true);
   UntilSession(tm);
   TicksMs(tm, 100, 200);                       // settle (config, symbols, first snapshot)
   int polls = g_fake.commandPolls;
   long calls = tm.HttpCalls();
   TicksMs(tm, 100, 200);                       // 20 s idle at 200 ms ticks, poll_ms = 2000
   int idlePolls = g_fake.commandPolls - polls;
   Check("S29", idlePolls >= 9 && idlePolls <= 11, StringFormat("idle polls follow poll_ms, not the tick (%d in 20 s)", idlePolls));
   Check("S29", tm.HttpCalls() - calls <= 14, StringFormat("idle HTTP rate bounded (%I64d calls in 20 s)", tm.HttpCalls() - calls));
   g_fake.Queue("c_s29", OpenCmd("c_s29", 9131));
   polls = g_fake.commandPolls;
   int t = 0;
   while(g_fake.commandPolls == polls && t < 15) { TicksMs(tm, 1, 200); t++; }
   Check("S29", g_fake.commandPolls > polls && t <= 11, StringFormat("command picked up within one interval (%d ticks)", t));
   int results = g_fake.resultPosts;
   polls = g_fake.commandPolls;
   TicksMs(tm, 1, 200);
   Check("S29", PositionsWithComment(TestComment(9131)) == 1, "executed on the next tick");
   TicksMs(tm, 1, 200);
   Check("S29", g_fake.resultPosts > results, "result posted on the first tick the min gap allows");
   TicksMs(tm, 2, 200);
   Check("S29", g_fake.commandPolls == polls + 1, "one immediate re-poll after a non-empty batch (after the gap)");
   polls = g_fake.commandPolls;
   TicksMs(tm, 5, 200);
   Check("S29", g_fake.commandPolls == polls, "back to the interval after the burst");
   Check("S29", g_fake.minGapMs >= 300, StringFormat("no two calls closer than the 300 ms gap (min %I64d ms)", g_fake.minGapMs));
   Check("S29", tm.MinGapMs() == 300, "gap input honored");
   delete tm;
   CloseAll();
  }

//--- S30: state file names carry the Copy Server identity; legacy (pre-identity) files are adopted only
//    when their token file records the same server, and are never deleted.
void S30Id(const string url, const string want)
  {
   Check("S30", TmServerId(url) == want, StringFormat("server id of '%s' = '%s' (got '%s')", url, want, TmServerId(url)));
  }

string S30Legacy(const string tag, const string kind, const string ext)
  {
   return "TradeMirror\\" + g_runTag + tag + "_" + kind + TmSafeName(AccountInfoString(ACCOUNT_SERVER)) + "_" +
          IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_slave" + ext;
  }

void S30WriteLegacyToken(const string tag, const string tokenValue, const string serverUrl)
  {
   CTokenStore t;
   t.SetPath(S30Legacy(tag, "copy_token_", ".dat"));
   t.token = tokenValue; t.account_id = 7; t.login = AccountInfoInteger(ACCOUNT_LOGIN); t.issued_ms = 1;
   t.server_url = serverUrl;
   t.Save();
  }

CTradeMirror *S30Engine(const string tag, const string url)
  {
   STmSettings s;
   s.server_url = url; s.role = TM_ROLE_SLAVE; s.enroll_code = ""; s.force_enroll = false; s.rotate_days = 0;
   s.verbose = false; s.popups = false; s.file_tag = g_runTag + tag; s.min_gap_ms = 300;
   CTradeMirror *tm = new CTradeMirror();
   tm.Init(s, GetPointer(g_fake));
   return tm;
  }

void S30()
  {
   S30Id("https://trademirror.imentore.com", "trademirror.imentore.com");
   S30Id("https://TradeMirror.Imentore.com:443/", "trademirror.imentore.com");
   S30Id("https://user:pw@host.example.com/api/v4?x=1#f", "host.example.com");
   S30Id("http://localhost:8099", "localhost_8099");
   S30Id("http://127.0.0.1:80/", "127.0.0.1");
   S30Id("https://host.example.com:8443", "host.example.com_8443");
   S30Id("", "noserver");

   g_fake.Reset();
   // a) legacy token of the same server (URL spelled differently) + journal/outbox -> adopted, old files kept
   S30WriteLegacyToken("s30a", "tok-legacy-a", "https://Fake.test/");
   TmAppendLine(S30Legacy("s30a", "outbox_", ".jsonl"), "{\"id\":1,\"result\":{\"command_id\":\"c_s30\",\"status\":\"done\"}}");
   CTradeMirror *tm = S30Engine("s30a", "https://fake.test");
   Check("S30", tm.MigratedFrom() != "", "legacy state of the same server migrated");
   Check("S30", tm.Token().token == "tok-legacy-a", "legacy token reused (no re-enroll)");
   Check("S30", StringFind(tm.Token().Path(), "_fake.test.dat") > 0, "token file name carries the server id: " + tm.Token().Path());
   Check("S30", tm.Outbox().Count() == 1, "legacy outbox adopted");
   Check("S30", FileIsExist(S30Legacy("s30a", "copy_token_", ".dat")) && FileIsExist(S30Legacy("s30a", "outbox_", ".jsonl")),
         "legacy files not deleted");
   CTokenStore disk;
   disk.SetPath(tm.Token().Path());
   disk.Load();
   Check("S30", disk.token == "tok-legacy-a" && disk.server_url == "https://fake.test", "new token file records the server URL");
   delete tm;
   // a2) restart: the new file wins, no second migration
   tm = S30Engine("s30a", "https://fake.test");
   Check("S30", tm.MigratedFrom() == "" && tm.Token().token == "tok-legacy-a", "restart loads the new file directly");
   delete tm;
   // b) same legacy files, another server -> ignored, separate (empty) state
   tm = S30Engine("s30a", "https://other.example.com:8443");
   Check("S30", tm.MigratedFrom() == "" && !tm.Token().HasToken(), "legacy token of another server ignored");
   Check("S30", tm.Outbox().Count() == 0, "another server starts with an empty outbox");
   Check("S30", StringFind(tm.Token().Path(), "_other.example.com_8443.dat") > 0, "separate token file per server");
   delete tm;
   // c) legacy token without a stored server URL -> ignored (cannot prove it belongs to this server)
   S30WriteLegacyToken("s30c", "tok-legacy-c", "");
   tm = S30Engine("s30c", "https://fake.test");
   Check("S30", tm.MigratedFrom() == "" && !tm.Token().HasToken(), "legacy token without server URL ignored");
   Check("S30", FileIsExist(S30Legacy("s30c", "copy_token_", ".dat")), "ignored legacy token kept on disk");
   delete tm;
   // d) a fresh enroll writes the server URL into the token file
   tm = NewEngine("s30d", true);
   UntilSession(tm);
   disk.SetPath(tm.Token().Path());
   disk.Load();
   Check("S30", disk.HasToken() && disk.server_url == "https://fake.test", "enrolled token file records the server URL");
   delete tm;
  }

//--- S31: WebRequest failure classification and operator hints
void S31Case(const int code, const int lastError, const int wantStatus, const int wantError)
  {
   int st = 0, er = 0;
   TmClassifyWebRequest(code, lastError, st, er);
   Check("S31", st == wantStatus && er == wantError,
         StringFormat("WebRequest(%d, err %d) -> status %d error %d (got %d/%d)", code, lastError, wantStatus, wantError, st, er));
  }

void S31()
  {
   S31Case(-1, 4006, TM_HTTP_NOT_ALLOWED, 4006);
   S31Case(-1, 4014, TM_HTTP_NOT_ALLOWED, 4014);
   S31Case(-1, 4060, TM_HTTP_NOT_ALLOWED, 4060);
   S31Case(-1, 5203, TM_HTTP_NETWORK_ERROR, 5203);
   S31Case(1009, 0, TM_HTTP_NETWORK_ERROR, 1009);
   S31Case(1001, 0, TM_HTTP_NETWORK_ERROR, 1001);
   S31Case(200, 0, 200, 0);
   S31Case(503, 0, 503, 0);
   string url = "https://fake.test";
   Check("S31", TmTransportHint(TM_HTTP_NOT_ALLOWED, 4006, url) ==
         "URL not allowed in Tools > Options > Expert Advisors > WebRequest: " + url, "allow-list hint names the URL");
   Check("S31", StringFind(TmTransportHint(TM_HTTP_NETWORK_ERROR, 1009, url), "TLS failed") == 0 &&
         StringFind(TmTransportHint(TM_HTTP_NETWORK_ERROR, 1009, url), "check ServerUrl scheme") > 0, "1009 -> TLS hint");
   Check("S31", TmTransportHint(TM_HTTP_NETWORK_ERROR, 5203, url) == "", "plain network error: no hint");
   Check("S31", TmTransportHint(503, 0, url) == "", "HTTP 503: no hint");
   // engine level: the hint reaches the alarm
   g_fake.Reset();
   g_fake.forceStatus = TM_HTTP_NOT_ALLOWED; g_fake.forceError = 4006;
   CTradeMirror *tm = NewEngine("s31a", true);
   Ticks(tm, 3);
   Check("S31", StringFind(TmLog.LastAlert(), "URL not allowed in Tools > Options > Expert Advisors > WebRequest: https://fake.test") >= 0,
         "engine alarms the allow-list hint: " + TmLog.LastAlert());
   delete tm;
   g_fake.Reset();
   g_fake.forceStatus = TM_HTTP_NETWORK_ERROR; g_fake.forceError = 1009;
   tm = NewEngine("s31b", true);
   Ticks(tm, 3);
   Check("S31", StringFind(TmLog.LastAlert(), "TLS failed") >= 0, "engine alarms the TLS hint: " + TmLog.LastAlert());
   delete tm;
   g_fake.Reset();
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
   S01(); S02(); S03(); S04(); S05(); S06(); S24(); S25(); S26(); S27(); S28(); S29(); S30(); S31();
   g_tm_fake_now_ms = 0;
   PrintFormat("TradeMirror self-test: %d passed, %d failed", g_passed, g_failed);
  }

double OnTester()
  {
   return (double)g_failed;
  }
