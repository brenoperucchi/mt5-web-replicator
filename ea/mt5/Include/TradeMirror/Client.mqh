//+------------------------------------------------------------------+
//| TradeMirror - v4 protocol client (design 4.1 - 4.3, D8, 6.2)     |
//|                                                                  |
//| One OnTimer tick:                                                |
//|   1. local: journal recovery, close/close_partial/cancel/resolve |
//|   2. local: open/modify                                          |
//|   3. at most ONE HTTP call: prerequisites, then a dirty master   |
//|      snapshot, then results (at most every other slot), then a   |
//|      due commands poll, then a fair rotation of the other routes |
//| The tick is short (TM_TICK_MS) for responsiveness; the HTTP rate |
//| is still set by the per-route intervals, not by the tick.        |
//| WebRequest is synchronous, so nothing ever retries inside a call |
//| and nothing sleeps.                                              |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_CLIENT_MQH
#define TRADEMIRROR_CLIENT_MQH

#include "Json.mqh"
#include "Util.mqh"
#include "Transport.mqh"
#include "TokenStore.mqh"
#include "Journal.mqh"
#include "Outbox.mqh"
#include "Broker.mqh"
#include "Executor.mqh"

enum ENUM_TM_ROLE
  {
   TM_ROLE_MASTER = 0,  // Master (sends snapshots)
   TM_ROLE_SLAVE  = 1   // Slave (executes commands)
  };

enum ENUM_TM_ROUTE
  {
   R_ENROLL = 0,
   R_SESSION,
   R_CONFIRM,
   R_ROTATE,
   R_RESULTS,
   R_COMMANDS,
   R_SNAPSHOT,
   R_CONFIG,
   R_SYMBOLS,
   R_LOGS,
   R_COUNT
  };

#define TM_TICK_MS               200
#define TM_MIN_POLL_MS           500
#define TM_MIN_CALL_GAP_MS       200     // floor of the configurable gap between any two HTTP calls
#define TM_DEFAULT_CALL_GAP_MS   300
#define TM_TIMEOUT_MS            5000
#define TM_BUDGET_ATTEMPTS       6
#define TM_BUDGET_MS             60000
#define TM_MAX_BACKOFF_MS        16000
#define TM_CONFIG_EVERY_MS       60000
#define TM_BLOCKED_CONFIG_MS     300000
#define TM_SLAVE_SNAPSHOT_MS     10000
#define TM_SYMBOLS_EVERY_MS      86400000
#define TM_BAD_RESULTS_RETRY_MS  300000
#define TM_LOG_MAX_BYTES         262144

struct STmSettings
  {
   string            server_url;       // https://copy.example.com (no trailing slash)
   ENUM_TM_ROLE      role;
   string            enroll_code;
   int               rotate_days;      // 0 = never rotate automatically
   bool              verbose;
   bool              popups;
   string            file_tag;         // "" in production; isolates files in the self-test EA
   bool              force_enroll;     // ignore an existing token file and enroll with enroll_code
   int               min_gap_ms;       // minimum gap between ANY two HTTP calls (clamped to >= 200)
  };

struct STmRoute
  {
   long              due_ms;           // next_attempt_at (monotonic ms)
   int               attempts;         // transient attempts of the current request
   long              first_fail_ms;
   string            key;              // Idempotency-Key reused on retry of the same logical request
   string            body;             // frozen body for that key (event-like requests)
   bool              alerted;
   long              sent;             // counters (diagnostics / tests)
   long              ok;
  };

string TmRouteName(const int r)
  {
   switch(r)
     {
      case R_ENROLL:   return "enroll";
      case R_SESSION:  return "session";
      case R_CONFIRM:  return "token/confirm";
      case R_ROTATE:   return "token/rotate";
      case R_RESULTS:  return "slave/results";
      case R_COMMANDS: return "slave/commands";
      case R_SNAPSHOT: return "snapshot";
      case R_CONFIG:   return "config";
      case R_SYMBOLS:  return "symbols";
      case R_LOGS:     return "logs";
     }
   return "?";
  }

bool TmUrlAllowed(const string url)
  {
   if(StringFind(url, "https://") == 0)
      return true;
   return StringFind(url, "http://localhost") == 0 || StringFind(url, "http://127.0.0.1") == 0;
  }

bool TmVersionLess(const string a, const string b)
  {
   string pa[], pb[];
   int na = StringSplit(a, '.', pa);
   int nb = StringSplit(b, '.', pb);
   for(int i = 0; i < MathMax(na, nb); i++)
     {
      long x = i < na ? StringToInteger(pa[i]) : 0;
      long y = i < nb ? StringToInteger(pb[i]) : 0;
      if(x != y)
         return x < y;
     }
   return false;
  }

class CTradeMirror
  {
private:
   STmSettings       m_s;
   ITransport       *m_transport;
   CTokenStore       m_token;
   CJournal          m_journal;
   COutbox           m_outbox;
   CExecutor         m_exec;
   STmRoute          m_routes[R_COUNT];
   int               m_lastRoute;

   // session (C4)
   string            m_sessionId;
   long              m_epoch;
   long              m_seq;
   long              m_clockOffsetMs;
   int               m_notAccepted;
   long              m_lastAcceptedMs;
   bool              m_staleSession;
   bool              m_snapshotDirty;
   bool              m_commandsBurst;  // the next commands poll is the one immediate re-poll after a non-empty batch

   // server config
   string            m_mode;
   long              m_pollMs;
   bool              m_sendHistory;
   bool              m_debug;
   string            m_wanted[];
   string            m_cursor;
   bool              m_logsDisabled;

   // stop conditions (4.2 table)
   bool              m_unauthorized;
   bool              m_blocked;
   bool              m_accountMismatch;
   bool              m_enrollRefused;
   bool              m_restartRotation;
   string            m_status;
   long              m_httpCalls;
   long              m_minGapMs;       // no call starts sooner than this after the previous one (urgent ones included)
   long              m_lastCallMs;
   bool              m_inStep;         // re-entrancy guard for the scheduler step
   long              m_rateWindowMs;   // calls/min: start of the current minute window
   long              m_rateWindowCalls;
   long              m_callsPerMin;    // calls in the last complete minute (status line)
   int               m_rateWindows;

   string            Role(void) const { return m_s.role == TM_ROLE_MASTER ? "master" : "slave"; }
   bool              IsSlave(void) const { return m_s.role == TM_ROLE_SLAVE; }

   string            FileBase(void)
     {
      string tag = m_s.file_tag == "" ? "" : m_s.file_tag + "_";
      return "TradeMirror\\" + tag;
     }
   string            Suffix(void)
     {
      return TmSafeName(AccountInfoString(ACCOUNT_SERVER)) + "_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + Role();
     }

   long              Jitter(const long ms) { return ms + (long)(MathRand() % 250); }

   void              Schedule(const int r, const long inMs) { m_routes[r].due_ms = TmMonoMs() + inMs; }
   bool              Due(const int r) { return TmMonoMs() >= m_routes[r].due_ms; }

   void              ResetRequest(const int r)
     {
      m_routes[r].attempts = 0;
      m_routes[r].first_fail_ms = 0;
      m_routes[r].key = "";
      m_routes[r].body = "";
      m_routes[r].alerted = false;
     }

   //--- which routes want a call now -------------------------------------------------------
   bool              Wants(const int r)
     {
      bool hasToken = m_token.HasToken();
      if(m_unauthorized)
         return r == R_ENROLL && m_s.enroll_code != "" && !m_enrollRefused && Due(r);
      switch(r)
        {
         case R_ENROLL:
            return !hasToken && m_s.enroll_code != "" && !m_enrollRefused && Due(r);
         case R_SESSION:
            return hasToken && !m_blocked && m_sessionId == "" && !m_staleSession && Due(r);
         case R_CONFIRM:
            return hasToken && m_token.pending_token != "" && Due(r);
         case R_ROTATE:
            return hasToken && m_token.pending_token == "" && !m_blocked && m_s.rotate_days > 0 &&
                   TmNowMs() - m_token.issued_ms > (long)m_s.rotate_days * 86400000 && Due(r);
         case R_CONFIG:
            return hasToken && Due(r);
         case R_SYMBOLS:
            return hasToken && !m_blocked && Due(r);
         case R_RESULTS:
            return hasToken && IsSlave() && m_outbox.Count() > 0 && Due(r);
         case R_COMMANDS:
            return hasToken && IsSlave() && !m_blocked && m_sessionId != "" && Due(r);
         case R_SNAPSHOT:
            return hasToken && !m_blocked && m_sessionId != "" && !m_accountMismatch && SnapshotAllowed() &&
                   (Due(r) || (m_snapshotDirty && m_routes[r].attempts == 0));
         case R_LOGS:
            return hasToken && m_debug && !m_logsDisabled && Due(r);
        }
      return false;
     }

   // 4.3: no snapshot until connected, logged into the token's account and history synced
   bool              SnapshotAllowed(void)
     {
      if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
         return false;
      if(m_token.login != 0 && m_token.login != AccountInfoInteger(ACCOUNT_LOGIN))
        {
         if(!m_accountMismatch)
            TmLog.Alarm("terminal is logged into a different account than the token: snapshots stopped");
         m_accountMismatch = true;
         return false;
        }
      return true;
     }

   //--- fair rotation: prerequisites first, then results at most every other slot ---------------
   int               PickRoute(void)
     {
      int pre[4] = {R_ENROLL, R_SESSION, R_CONFIRM, R_ROTATE};
      for(int i = 0; i < 4; i++)
         if(Wants(pre[i]))
            return pre[i];
      // latency: a trade on the master goes out on the very next tick, ahead of config/symbols
      if(!IsSlave() && m_snapshotDirty && m_routes[R_SNAPSHOT].attempts == 0 && Wants(R_SNAPSHOT))
         return R_SNAPSHOT;
      int ring[5] = {R_COMMANDS, R_SNAPSHOT, R_CONFIG, R_SYMBOLS, R_LOGS};
      bool resultsDue = Wants(R_RESULTS);
      if(resultsDue && m_lastRoute != R_RESULTS)
         return R_RESULTS;
      // a due commands poll is not delayed by the rotation (its interval still bounds the rate)
      if(Wants(R_COMMANDS))
         return R_COMMANDS;
      int start = 0;
      for(int i = 0; i < 5; i++)
         if(ring[i] == m_lastRoute)
            start = i + 1;
      for(int k = 0; k < 5; k++)
        {
         int r = ring[(start + k) % 5];
         if(Wants(r))
            return r;
        }
      return resultsDue ? R_RESULTS : -1;
     }

   //--- HTTP --------------------------------------------------------------------------------
   string            Headers(const string token, const string key, const string contentType = "application/json")
     {
      string h = "Content-Type: " + contentType + "\r\nAccept: application/json\r\n";
      if(token != "")
         h += "Authorization: Bearer " + token + "\r\n";
      if(key != "")
         h += "Idempotency-Key: " + key + "\r\n";
      h += "User-Agent: " + TM_PRODUCT + "/" + TM_EA_VERSION + "\r\n";
      return h;
     }

   void              Call(const int r, const string method, const string path, const string token, const string body,
                          STmHttpResponse &resp, const string contentType = "application/json")
     {
      m_routes[r].sent++;
      m_httpCalls++;
      m_lastCallMs = TmMonoMs();
      CountRate(m_lastCallMs);
      string key = (method == "GET") ? "" : m_routes[r].key;
      m_transport.Send(method, m_s.server_url + path, Headers(token, key, contentType), body, TM_TIMEOUT_MS, resp);
      TmLog.Debug(StringFormat("%s %s -> %d", method, path, resp.status));
     }

   void              CountRate(const long now)
     {
      if(m_rateWindowMs == 0)
         m_rateWindowMs = now;
      if(now - m_rateWindowMs >= 60000)
        {
         m_callsPerMin = m_rateWindowCalls;
         m_rateWindowCalls = 0;
         m_rateWindowMs = now;
         string line = StringFormat("http: %I64d calls in the last minute (poll %I64d ms, min gap %I64d ms)", m_callsPerMin, m_pollMs, m_minGapMs);
         if(++m_rateWindows % 10 == 1)
            TmLog.Info(line);    // every 10 min in the Experts log; every minute with VerboseLog
         else
            TmLog.Debug(line);
        }
      m_rateWindowCalls++;
     }

   CJson            *ParseBody(const STmHttpResponse &resp)
     {
      if(resp.body == "")
         return NULL;
      CJson *j = JsonParse(resp.body);
      if(j != NULL && j.type == JSON_OBJECT && j.Has("server_time"))
        {
         m_clockOffsetMs = j.Long("server_time") - TmNowMs();
         m_exec.SetClockOffset(m_clockOffsetMs);
        }
      return j;
     }

   string            ErrorOf(CJson *j) { return j != NULL ? j.Str("error") : ""; }

   bool              IsTransient(const int status)
     {
      return status == TM_HTTP_NETWORK_ERROR || status == 429 || status >= 500;
     }

   // transient budget (4.2): max 6 attempts and 60 s per request; Retry-After for this route only
   void              Transient(const int r, const STmHttpResponse &resp, const bool eventRequest)
     {
      long now = TmMonoMs();
      if(m_routes[r].attempts == 0)
         m_routes[r].first_fail_ms = now;
      m_routes[r].attempts++;
      long backoff = MathMin((long)1000 << MathMin(m_routes[r].attempts - 1, 4), (long)TM_MAX_BACKOFF_MS);
      string ra = TmHeaderValue(resp.headers, "Retry-After");
      long retryAfterMs = ra != "" ? StringToInteger(ra) * 1000 : 0;
      bool exhausted = m_routes[r].attempts >= TM_BUDGET_ATTEMPTS || now - m_routes[r].first_fail_ms >= TM_BUDGET_MS;
      if(exhausted && !eventRequest)
        {
         // state request: dropped, fresh state on a later tick
         TmLog.Warn(StringFormat("%s: retry budget exhausted (last %d); dropped", TmRouteName(r), resp.status));
         ResetRequest(r);
         Schedule(r, MathMax(retryAfterMs, (long)TM_MAX_BACKOFF_MS));
         return;
        }
      if(exhausted && eventRequest && !m_routes[r].alerted)
        {
         m_routes[r].alerted = true;
         TmLog.Alarm(StringFormat("%s: server unreachable (last %d); results kept in the outbox and retried",
                                  TmRouteName(r), resp.status));
        }
      long wait = exhausted ? TM_MAX_BACKOFF_MS : Jitter(backoff);
      if(retryAfterMs > 0)
         wait = retryAfterMs;
      Schedule(r, wait);
     }

   // common non-2xx handling; returns true when handled
   bool              CommonError(const int r, const STmHttpResponse &resp, CJson *j, const bool eventRequest)
     {
      int st = resp.status;
      if(st == TM_HTTP_NOT_ALLOWED)
        {
         TmLog.Alarm("WebRequest is not allowed for " + m_s.server_url +
                     ": Tools > Options > Expert Advisors > Allow WebRequest for listed URL");
         Schedule(r, 60000);
         return true;
        }
      if(IsTransient(st))
        {
         Transient(r, resp, eventRequest);
         return true;
        }
      if(st == 401)
        {
         if(!m_unauthorized)
            TmLog.Alarm("token rejected (" + ErrorOf(j) + "): trading and calls stopped. Re-enroll with a new code.");
         m_unauthorized = true;
         m_exec.SetDrain(true);
         ResetRequest(r);
         return true;
        }
      if(st == 403)
        {
         if(!m_blocked)
            TmLog.Alarm("account blocked by the server: " + (j != NULL ? j.Str("message") : ""));
         m_blocked = true;
         m_exec.SetDrain(true);
         ResetRequest(r);
         Schedule(R_CONFIG, TM_BLOCKED_CONFIG_MS);
         return true;
        }
      if(st == 404)
        {
         TmLog.Alarm(TmRouteName(r) + ": 404 from the server (server version mismatch?)");
         ResetRequest(r);
         Schedule(r, TM_BAD_RESULTS_RETRY_MS);
         return true;
        }
      if(st == 409)
        {
         string err = ErrorOf(j);
         if(err == "stale_session")
           {
            // fenced: never loop on automatic re-registration (C4)
            TmLog.Alarm("session fenced by the server (another terminal with this token?). "
                        "Reload the EA, or wait for a config mode change, to start a new session.");
            m_sessionId = "";
            m_staleSession = true;
           }
         else if(err == "account_mismatch")
           {
            TmLog.Alarm("terminal logged into a different account than the token: snapshots stopped");
            m_accountMismatch = true;
           }
         else
            TmLog.Warn(TmRouteName(r) + ": 409 " + err);
         ResetRequest(r);
         Schedule(r, eventRequest ? TM_BAD_RESULTS_RETRY_MS : TM_MAX_BACKOFF_MS);
         return true;
        }
      // 400 / 413 / 422 and anything else
      TmLog.Alarm(StringFormat("%s: HTTP %d %s (EA/server bug?)", TmRouteName(r), st, ErrorOf(j)));
      if(eventRequest)
        {
         m_routes[r].key = "";   // a fresh batch next time
         Schedule(r, TM_BAD_RESULTS_RETRY_MS);
        }
      else
        {
         ResetRequest(r);
         Schedule(r, r == R_SNAPSHOT ? NormalInterval(r) : TM_BAD_RESULTS_RETRY_MS);
        }
      return true;
     }

   long              NormalInterval(const int r)
     {
      switch(r)
        {
         case R_COMMANDS: return m_pollMs;
         case R_SNAPSHOT: return IsSlave() ? TM_SLAVE_SNAPSHOT_MS : m_pollMs;
         case R_CONFIG:   return m_blocked ? TM_BLOCKED_CONFIG_MS : TM_CONFIG_EVERY_MS;
         case R_SYMBOLS:  return TM_SYMBOLS_EVERY_MS;
         case R_LOGS:     return 60000;
        }
      return 1000;
     }

   void              Success(const int r)
     {
      m_routes[r].ok++;
      ResetRequest(r);
      Schedule(r, NormalInterval(r));
     }

   //--- routes ------------------------------------------------------------------------------
   void              DoEnroll(void)
     {
      if(m_routes[R_ENROLL].key == "")
        {
         CJsonWriter w;
         w.BeginObj();
         w.Str("code", m_s.enroll_code);
         w.Str("broker_server", AccountInfoString(ACCOUNT_SERVER));
         w.Int("login", AccountInfoInteger(ACCOUNT_LOGIN));
         w.Str("role", Role());
         w.Str("margin_mode", TmIsHedging() ? "hedging" : "netting");
         w.Str("ea_version", TM_EA_VERSION);
         w.EndObj();
         m_routes[R_ENROLL].key = TmUuid();
         m_routes[R_ENROLL].body = w.Text();
        }
      STmHttpResponse resp;
      Call(R_ENROLL, "POST", "/v4/enroll", "", m_routes[R_ENROLL].body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 201 && j != NULL && j.Str("token") != "")
        {
         // never logged; written atomically before anything uses it (D8)
         m_token.token = j.Str("token");
         m_token.account_id = j.Long("account_id");
         m_token.login = AccountInfoInteger(ACCOUNT_LOGIN);
         m_token.issued_ms = TmNowMs();
         m_token.pending_token = "";
         m_token.pending_id = "";
         if(!m_token.Save())
            TmLog.Alarm("could not write the token file " + m_token.Path());
         m_unauthorized = false;
         m_blocked = false;
         m_exec.SetDrain(false);
         m_sessionId = "";
         m_staleSession = false;
         Success(R_ENROLL);
         Schedule(R_SESSION, 0);
         Schedule(R_CONFIG, 0);
         Schedule(R_SYMBOLS, 0);
         TmLog.Info(StringFormat("enrolled as %s, account id %I64d", Role(), m_token.account_id));
        }
      else if(resp.status == 401 || resp.status == 422 || resp.status == 400)
        {
         TmLog.Alarm("enrollment refused (" + ErrorOf(j) + "): ask for a new code and set it in the inputs");
         m_enrollRefused = true;
         ResetRequest(R_ENROLL);
        }
      else
         CommonError(R_ENROLL, resp, j, true);
      if(j != NULL)
         delete j;
     }

   void              DoSession(void)
     {
      if(m_routes[R_SESSION].key == "")
        {
         CJsonWriter w;
         w.BeginObj();
         w.Str("boot_nonce", StringSubstr(TmUuid(), 0, 32));
         w.Int("taken_at", TmNowMs());
         w.Int("ea_clock_offset_ms", m_clockOffsetMs);
         w.EndObj();
         m_routes[R_SESSION].key = TmUuid();
         m_routes[R_SESSION].body = w.Text();
        }
      STmHttpResponse resp;
      Call(R_SESSION, "POST", "/v4/session", m_token.token, m_routes[R_SESSION].body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 201 && j != NULL)
        {
         m_sessionId = j.Str("session_id");
         m_epoch = j.Long("epoch");
         m_seq = 0;
         m_notAccepted = 0;
         m_snapshotDirty = true;
         Success(R_SESSION);
         Schedule(R_COMMANDS, 0);
         TmLog.Info(StringFormat("session %s epoch %I64d", m_sessionId, m_epoch));
        }
      else
         CommonError(R_SESSION, resp, j, true);
      if(j != NULL)
         delete j;
     }

   void              DoRotate(void)
     {
      string path = m_restartRotation ? "/v4/token/rotate?restart=true" : "/v4/token/rotate";
      if(m_routes[R_ROTATE].key == "")
        {
         m_routes[R_ROTATE].key = TmUuid();
         m_routes[R_ROTATE].body = "";
        }
      STmHttpResponse resp;
      Call(R_ROTATE, "POST", path, m_token.token, "", resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 200 && j != NULL && j.Str("new_token") != "")
        {
         // step 1: the new token is on disk before confirm (D8.5)
         if(m_token.StorePending(j.Str("new_token"), j.Str("pending_id")))
           {
            m_restartRotation = false;
            Success(R_ROTATE);
            Schedule(R_CONFIRM, 0);
           }
         else
           {
            TmLog.Alarm("could not write the rotated token; rotation will restart");
            m_restartRotation = true;
            ResetRequest(R_ROTATE);
           }
        }
      else if(resp.status == 409 && ErrorOf(j) == "rotation_pending")
        {
         // response of an earlier rotate was lost (S25): confirm what is on disk, else restart
         ResetRequest(R_ROTATE);
         if(m_token.pending_token != "")
            Schedule(R_CONFIRM, 0);
         else
           {
            m_restartRotation = true;
            Schedule(R_ROTATE, 0);
           }
        }
      else
         CommonError(R_ROTATE, resp, j, true);
      if(j != NULL)
         delete j;
     }

   void              DoConfirm(void)
     {
      if(m_routes[R_CONFIRM].key == "")
        {
         CJsonWriter w;
         w.BeginObj();
         w.Str("pending_id", m_token.pending_id);
         w.EndObj();
         m_routes[R_CONFIRM].key = TmUuid();
         m_routes[R_CONFIRM].body = w.Text();
        }
      STmHttpResponse resp;
      Call(R_CONFIRM, "POST", "/v4/token/confirm", m_token.pending_token, m_routes[R_CONFIRM].body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 204)
        {
         m_token.PromotePending();
         Success(R_CONFIRM);
         TmLog.Info("token rotated");
        }
      else if(resp.status == 401 || (resp.status == 409 && ErrorOf(j) == "pending_mismatch"))
        {
         // the pending token expired or was replaced: forget it, rotate again later
         TmLog.Warn("pending token rejected (" + ErrorOf(j) + "); rotation restarts");
         m_token.DropPending();
         m_restartRotation = true;
         ResetRequest(R_CONFIRM);
        }
      else
         CommonError(R_CONFIRM, resp, j, true);
      if(j != NULL)
         delete j;
     }

   void              DoConfig(void)
     {
      STmHttpResponse resp;
      Call(R_CONFIG, "GET", "/v4/config", m_token.token, "", resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 200 && j != NULL)
        {
         string mode = j.Str("mode", "normal");
         if(mode != m_mode && m_staleSession)
           {
            // a config mode change is one of the two allowed triggers for a new session (C4)
            m_staleSession = false;
            Schedule(R_SESSION, 0);
           }
         if(mode != m_mode)
            TmLog.Info("server mode: " + mode + (j.Str("message") != "" ? " (" + j.Str("message") + ")" : ""));
         m_mode = mode;
         m_blocked = false;
         m_exec.SetDrain(mode == "drain");
         long poll = j.Long("poll_ms", 2000);
         m_pollMs = MathMax(poll, (long)TM_MIN_POLL_MS);
         m_sendHistory = j.Bool("send_history", false);
         bool debug = j.Bool("debug", false);
         if(debug && !m_debug)
            m_logsDisabled = false;
         m_debug = debug;
         TmLog.Verbose(m_s.verbose || m_debug);
         string minVer = j.Str("min_ea_version");
         if(minVer != "" && TmVersionLess(TM_EA_VERSION, minVer))
            TmLog.Alarm("this EA (" + TM_EA_VERSION + ") is older than the server minimum " + minVer + ": update it");
         CJson *wanted = j.Get("symbols_wanted");
         if(wanted != NULL && wanted.type == JSON_ARRAY && wanted.Size() > 0)
           {
            bool changed = wanted.Size() != ArraySize(m_wanted);
            ArrayResize(m_wanted, wanted.Size());
            for(int i = 0; i < wanted.Size(); i++)
              {
               if(m_wanted[i] != wanted.At(i).text)
                  changed = true;
               m_wanted[i] = wanted.At(i).text;
              }
            if(changed)
               Schedule(R_SYMBOLS, 0);
           }
         Success(R_CONFIG);
        }
      else
         CommonError(R_CONFIG, resp, j, false);
      if(j != NULL)
         delete j;
     }

   void              DoSymbols(void)
     {
      // body is rebuilt on each attempt; a new key goes with a new body
      m_routes[R_SYMBOLS].key = TmUuid();
      string body = TmBuildSymbols(m_wanted);
      STmHttpResponse resp;
      Call(R_SYMBOLS, "PUT", "/v4/symbols", m_token.token, body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 204 || resp.status == 200)
         Success(R_SYMBOLS);
      else
         CommonError(R_SYMBOLS, resp, j, false);
      if(j != NULL)
         delete j;
     }

   void              DoSnapshot(void)
     {
      // state request: fresh state and a new seq on every attempt (never a stale body)
      bool synced = false;
      m_seq++;
      m_routes[R_SNAPSHOT].key = TmUuid();
      long since = m_lastAcceptedMs > 0 ? m_lastAcceptedMs - 60000 : 0;
      string body = TmBuildSnapshot(m_sessionId, m_epoch, m_seq, m_clockOffsetMs, since, m_sendHistory, synced);
      if(!synced)
        {
         m_seq--;
         Schedule(R_SNAPSHOT, 1000);   // HistorySelect has not returned yet
         return;
        }
      m_snapshotDirty = false;
      string path = IsSlave() ? "/v4/slave/snapshot" : "/v4/master/snapshot";
      STmHttpResponse resp;
      long taken = TmNowMs();
      Call(R_SNAPSHOT, "POST", path, m_token.token, body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 200 && j != NULL)
        {
         if(j.Bool("accepted", false))
           {
            m_notAccepted = 0;
            m_lastAcceptedMs = taken;
           }
         else if(++m_notAccepted >= 3)
           {
            TmLog.Alarm("3 snapshots in a row not accepted by the server (seq ordering); check for a second terminal");
            m_notAccepted = 0;
           }
         Success(R_SNAPSHOT);
        }
      else
         CommonError(R_SNAPSHOT, resp, j, false);
      if(j != NULL)
         delete j;
     }

   void              DoCommands(void)
     {
      string path = "/v4/slave/commands" + (m_cursor != "" ? "?after=" + m_cursor : "");
      STmHttpResponse resp;
      Call(R_COMMANDS, "GET", path, m_token.token, "", resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 200 && j != NULL)
        {
         CJson *cmds = j.Get("commands");
         bool got = cmds != NULL && cmds.type == JSON_ARRAY && cmds.Size() > 0;
         m_exec.Receive(cmds);
         m_cursor = j.Str("cursor", m_cursor);
         Success(R_COMMANDS);
         // after a non-empty batch, poll once more right away (a close often follows an open), then back to the interval
         if(got && !m_commandsBurst)
           {
            m_commandsBurst = true;
            Schedule(R_COMMANDS, 0);
           }
         else
            m_commandsBurst = false;
        }
      else
         CommonError(R_COMMANDS, resp, j, false);
      if(j != NULL)
         delete j;
     }

   long              m_batchIds[];

   void              DoResults(void)
     {
      // event request: one frozen batch per Idempotency-Key until 2xx
      if(m_routes[R_RESULTS].key == "")
        {
         string body;
         if(m_outbox.PeekBatch(m_batchIds, body) == 0)
            return;
         m_routes[R_RESULTS].key = TmUuid();
         m_routes[R_RESULTS].body = body;
        }
      STmHttpResponse resp;
      Call(R_RESULTS, "POST", "/v4/slave/results", m_token.token, m_routes[R_RESULTS].body, resp);
      CJson *j = ParseBody(resp);
      if(resp.status == 200 || resp.status == 204)
        {
         if(j != NULL)
           {
            CJson *unknown = j.Get("unknown");
            if(unknown != NULL)
               for(int i = 0; i < unknown.Size(); i++)
                  TmLog.Warn("server does not know command " + unknown.At(i).text + "; result dropped");
           }
         m_outbox.Ack(m_batchIds);
         ArrayResize(m_batchIds, 0);
         Success(R_RESULTS);
         if(m_outbox.Count() > 0)
            Schedule(R_RESULTS, 0);
        }
      else
         CommonError(R_RESULTS, resp, j, true);
      if(j != NULL)
         delete j;
     }

   void              DoLogs(void)
     {
      string text = TmLog.TakeBuffer(TM_LOG_MAX_BYTES);
      if(text == "")
        {
         Schedule(R_LOGS, 60000);
         return;
        }
      m_routes[R_LOGS].key = TmUuid();
      STmHttpResponse resp;
      Call(R_LOGS, "POST", "/v4/logs", m_token.token, text, resp, "text/plain; charset=utf-8");
      if(resp.status == 204 || resp.status == 200)
         Success(R_LOGS);
      else if(resp.status == 404 || resp.status == 413)
        {
         // not available on this server, or over the cap/quota: stop until the next debug switch (4.3)
         m_logsDisabled = true;
         ResetRequest(R_LOGS);
        }
      else
        {
         ResetRequest(R_LOGS);
         Schedule(R_LOGS, 60000);
        }
     }

public:
                     CTradeMirror(void)
     {
      m_transport = NULL; m_lastRoute = -1; m_epoch = 0; m_seq = 0; m_clockOffsetMs = 0; m_notAccepted = 0;
      m_lastAcceptedMs = 0; m_staleSession = false; m_snapshotDirty = true; m_commandsBurst = false; m_mode = "normal"; m_pollMs = 2000;
      m_sendHistory = false; m_debug = false; m_cursor = ""; m_logsDisabled = false; m_unauthorized = false;
      m_blocked = false; m_accountMismatch = false; m_enrollRefused = false; m_restartRotation = false;
      m_sessionId = ""; m_status = ""; m_httpCalls = 0;
      m_minGapMs = TM_DEFAULT_CALL_GAP_MS; m_lastCallMs = 0; m_rateWindowMs = 0; m_rateWindowCalls = 0; m_callsPerMin = -1; m_rateWindows = 0; m_inStep = false;
      for(int i = 0; i < R_COUNT; i++)
        {
         ResetRequest(i);
         m_routes[i].due_ms = 0;
         m_routes[i].sent = 0;
         m_routes[i].ok = 0;
        }
     }

   bool              Init(const STmSettings &s, ITransport *transport)
     {
      m_s = s;
      m_transport = transport;
      m_minGapMs = MathMax((long)s.min_gap_ms, (long)TM_MIN_CALL_GAP_MS);
      TmLog.Verbose(s.verbose);
      TmLog.Popups(s.popups);
      if(!TmUrlAllowed(m_s.server_url))
        {
         TmLog.Alarm("ServerUrl must be https:// (http:// only for localhost)");
         return false;
        }
      FolderCreate("TradeMirror");
      string base = FileBase();
      m_token.SetPath(base + "copy_token_" + Suffix() + ".dat");
      m_token.Load();
      if(m_token.HasToken() && m_s.enroll_code != "" &&
         (m_s.force_enroll || m_token.login != AccountInfoInteger(ACCOUNT_LOGIN)))
         m_token.Reset();
      else if(m_token.HasToken() && m_s.enroll_code != "")
         TmLog.Info("already enrolled: EnrollCode ignored (set ForceReEnroll=true to use it)");
      if(!m_token.HasToken() && m_s.enroll_code == "")
         TmLog.Alarm("not enrolled: set EnrollCode (from the admin) in the EA inputs");
      if(IsSlave())
        {
         m_journal.Open(base + "journal_" + Suffix() + ".jsonl");
         m_outbox.Open(base + "outbox_" + Suffix() + ".jsonl");
         m_exec.Init(GetPointer(m_journal), GetPointer(m_outbox));
         TmLog.Info(StringFormat("journal: %d entries, outbox: %d results", m_journal.Total(), m_outbox.Count()));
        }
      return true;
     }

   //--- force a re-enroll with a newly entered code even when a token file exists
   void              ForceEnroll(void) { m_token.Reset(); m_unauthorized = false; m_enrollRefused = false; }

   // The single scheduler step, driven by OnTimer and OnTick. MQL5 delivers events one at a time, so
   // a nested call cannot normally happen; the guard keeps it a no-op if one ever does.
   void              OnTimerTick(void)
     {
      if(m_inStep)
         return;
      m_inStep = true;
      Step();
      m_inStep = false;
     }

   void              Step(void)
     {
      // 1 + 2: local execution never waits on HTTP (revoked: no trading at all)
      if(IsSlave() && m_token.HasToken() && !m_unauthorized)
        {
         m_exec.Tick();
         if(m_exec.m_crashed)
            return;
         if(m_exec.TakeExecutedFlag())
           {
            m_snapshotDirty = true;
            // results of what just executed go out on the next call (unless the route is backing off)
            if(m_routes[R_RESULTS].attempts == 0 && m_outbox.Count() > 0 && m_routes[R_RESULTS].due_ms - TmMonoMs() <= 1000)
               Schedule(R_RESULTS, 0);
           }
        }
      // 3: at most one HTTP call, and never sooner than m_minGapMs after the previous one (no exceptions:
      //    urgent snapshot, results and the burst re-poll only jump the queue, they never shorten the gap)
      int r = (m_lastCallMs == 0 || TmMonoMs() - m_lastCallMs >= m_minGapMs) ? PickRoute() : -1;
      if(r >= 0)
        {
         m_lastRoute = r;
         switch(r)
           {
            case R_ENROLL:   DoEnroll();   break;
            case R_SESSION:  DoSession();  break;
            case R_CONFIRM:  DoConfirm();  break;
            case R_ROTATE:   DoRotate();   break;
            case R_RESULTS:  DoResults();  break;
            case R_COMMANDS: DoCommands(); break;
            case R_SNAPSHOT: DoSnapshot(); break;
            case R_CONFIG:   DoConfig();   break;
            case R_SYMBOLS:  DoSymbols();  break;
            case R_LOGS:     DoLogs();     break;
           }
        }
      UpdateStatus();
     }

   void              OnTradeEvent(void) { m_snapshotDirty = true; }

   void              OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
     {
      if(IsSlave())
         m_exec.OnTransaction(trans, request, result);
      if(trans.type == TRADE_TRANSACTION_DEAL_ADD || trans.type == TRADE_TRANSACTION_POSITION)
         m_snapshotDirty = true;
     }

   void              UpdateStatus(void)
     {
      string s = TM_PRODUCT + " " + TM_EA_VERSION + " | " + Role();
      if(m_unauthorized)            s += " | NOT AUTHORIZED: re-enroll";
      else if(!m_token.HasToken())  s += " | not enrolled";
      else if(m_blocked)            s += " | BLOCKED by server";
      else if(m_staleSession)       s += " | SESSION FENCED: reload EA";
      else if(m_accountMismatch)    s += " | ACCOUNT MISMATCH";
      else                          s += " | " + m_mode + " | session " + (m_sessionId == "" ? "-" : "ok");
      s += StringFormat(" | http %s/min (gap %I64d ms)", m_callsPerMin < 0 ? "-" : IntegerToString(m_callsPerMin), m_minGapMs);
      if(IsSlave())
         s += StringFormat(" | outbox %d | suspended %d", m_outbox.Count(), m_exec.CountState(JS_SUSPENDED));
      if(TmLog.LastAlert() != "")
         s += "\nLast alert: " + TmLog.LastAlert();
      m_status = s;
     }

   //--- accessors (chart status, self-test EA)
   string            Status(void) const { return m_status; }
   CExecutor        *Exec(void) { return GetPointer(m_exec); }
   CJournal         *Journal(void) { return GetPointer(m_journal); }
   COutbox          *Outbox(void) { return GetPointer(m_outbox); }
   CTokenStore      *Token(void) { return GetPointer(m_token); }
   string            SessionId(void) const { return m_sessionId; }
   bool              Unauthorized(void) const { return m_unauthorized; }
   bool              Blocked(void) const { return m_blocked; }
   long              RouteSent(const int r) const { return m_routes[r].sent; }
   long              RouteOk(const int r) const { return m_routes[r].ok; }
   long              HttpCalls(void) const { return m_httpCalls; }
   long              MinGapMs(void) const { return m_minGapMs; }
   long              CallsPerMin(void) const { return m_callsPerMin; }
   void              ForceRotate(void) { m_token.issued_ms = 0; if(m_s.rotate_days <= 0) m_s.rotate_days = 1; Schedule(R_ROTATE, 0); }
  };

#endif
