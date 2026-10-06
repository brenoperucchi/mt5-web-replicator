//+------------------------------------------------------------------+
//| TradeMirror - in-memory fake v4 server for the self-test EA      |
//|                                                                  |
//| Implements the subset of the v4 contract the client scenarios    |
//| need (enroll, session, config, symbols, snapshots, commands,     |
//| results, rotate/confirm) plus fault injection: lost responses    |
//| (processed by the "server", reply never reaches the EA) and      |
//| forced 429 + Retry-After on one route.                           |
//| It is a test double only; the real contract is checked against   |
//| the Python server by server/tests/test_ea_contract.py.           |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_TESTTRANSPORT_MQH
#define TRADEMIRROR_TESTTRANSPORT_MQH

#include "Transport.mqh"
#include "Json.mqh"

class CFakeServer : public ITransport
  {
private:
   int               m_tokenSeq;
   int               m_sessionSeq;

   string            Bearer(const string headers)
     {
      string v = TmHeaderValue(headers, "Authorization");
      if(StringFind(v, "Bearer ") == 0)
         return StringSubstr(v, 7);
      return "";
     }
   void              Reply(STmHttpResponse &resp, const int status, const string json, const string extraHeaders = "")
     {
      resp.status = status;
      resp.error = 0;
      resp.headers = extraHeaders;
      if(json == "")
        {
         resp.body = "";
         return;
        }
      // every response carries server_time (4.1)
      string body = json;
      if(StringGetCharacter(body, 0) == '{' && StringLen(body) > 2)
         body = "{\"server_time\":" + IntegerToString(TmNowMs()) + "," + StringSubstr(body, 1);
      else if(body == "{}")
         body = "{\"server_time\":" + IntegerToString(TmNowMs()) + "}";
      resp.body = body;
     }
   void              Lost(STmHttpResponse &resp)
     {
      resp.status = TM_HTTP_NETWORK_ERROR;
      resp.error = 5203;
      resp.headers = "";
      resp.body = "";
     }
   int               CmdIndex(const string id)
     {
      for(int i = 0; i < ArraySize(cmdIds); i++)
         if(cmdIds[i] == id)
            return i;
      return -1;
     }

public:
   // --- server state (inspected by the tests) ---
   string            code;            // valid enrollment code
   bool              codeConsumed;
   string            token;           // current valid token
   string            issuedUnconfirmed;
   string            pendingToken;
   string            pendingId;
   string            retiredTokens[];
   string            sessionId;
   string            mode;
   string            cmdIds[];
   string            cmdJson[];
   string            cmdState[];      // queued | delivered | in_progress | settled
   string            results[];       // every result object received (raw)
   int               resultPosts;
   int               commandPolls;
   long              lastCallMs;       // fake clock of the previous call, for the min-gap check
   long              minGapMs;         // smallest gap seen between two calls (-1 = fewer than two calls)
   int               snapshotPosts;
   int               enrollCalls;
   int               rotateCalls;
   // --- faults ---
   int               dropResults;     // process the next N results posts, lose the reply
   bool              dropNextEnroll;
   bool              dropNextRotate;
   string            fail429Path;     // path prefix answered 429
   int               retryAfterSec;

                     CFakeServer(void) { Reset(); }

   void              Reset(void)
     {
      m_tokenSeq = 0; m_sessionSeq = 0; code = "ABCD2345EF"; codeConsumed = false; token = ""; issuedUnconfirmed = "";
      pendingToken = ""; pendingId = ""; sessionId = ""; mode = "normal"; resultPosts = 0; commandPolls = 0;
      snapshotPosts = 0; enrollCalls = 0; rotateCalls = 0; dropResults = 0; dropNextEnroll = false; dropNextRotate = false;
      fail429Path = ""; retryAfterSec = 0; lastCallMs = 0; minGapMs = -1;
      ArrayResize(cmdIds, 0); ArrayResize(cmdJson, 0); ArrayResize(cmdState, 0); ArrayResize(results, 0);
      ArrayResize(retiredTokens, 0);
     }

   string            IssueToken(void) { m_tokenSeq++; return StringFormat("tok-%d-%I64d", m_tokenSeq, TmNowMs()); }

   void              Queue(const string id, const string json)
     {
      int n = ArraySize(cmdIds);
      ArrayResize(cmdIds, n + 1); ArrayResize(cmdJson, n + 1); ArrayResize(cmdState, n + 1);
      cmdIds[n] = id; cmdJson[n] = json; cmdState[n] = "queued";
     }
   // lease expiry / new session: the command is delivered again (4.5)
   void              Redeliver(const string id) { int i = CmdIndex(id); if(i >= 0) cmdState[i] = "queued"; }

   int               CountResults(const string commandId, const string status)
     {
      int n = 0;
      for(int i = 0; i < ArraySize(results); i++)
        {
         CJson *j = JsonParse(results[i]);
         if(j != NULL && j.Str("command_id") == commandId && (status == "" || j.Str("status") == status))
            n++;
         if(j != NULL) delete j;
        }
      return n;
     }
   string            LastResult(const string commandId, const string status)
     {
      for(int i = ArraySize(results) - 1; i >= 0; i--)
        {
         CJson *j = JsonParse(results[i]);
         bool hit = j != NULL && j.Str("command_id") == commandId && (status == "" || j.Str("status") == status);
         if(j != NULL) delete j;
         if(hit) return results[i];
        }
      return "";
     }
   bool              TokenRetired(const string t)
     {
      for(int i = 0; i < ArraySize(retiredTokens); i++)
         if(retiredTokens[i] == t) return true;
      return false;
     }

   virtual void      Send(const string method, const string url, const string headers, const string body,
                          const int timeoutMs, STmHttpResponse &resp)
     {
      int p = StringFind(url, "/v4/");
      string path = p >= 0 ? StringSubstr(url, p) : url;
      string bearer = Bearer(headers);
      long nowMs = TmMonoMs();
      if(lastCallMs > 0 && (minGapMs < 0 || nowMs - lastCallMs < minGapMs))
         minGapMs = nowMs - lastCallMs;
      lastCallMs = nowMs;
      if(fail429Path != "" && StringFind(path, fail429Path) == 0)
        {
         Reply(resp, 429, "{\"error\":\"rate_limited\"}", "Retry-After: " + IntegerToString(retryAfterSec) + "\r\n");
         if(path == "/v4/slave/results") resultPosts++;
         return;
        }
      // --- enroll (no token) ---
      if(path == "/v4/enroll")
        {
         enrollCalls++;
         CJson *j = JsonParse(body);
         bool ok = j != NULL && j.Str("code") == code && !codeConsumed;
         if(j != NULL) delete j;
         if(!ok) { Reply(resp, 401, "{\"error\":\"invalid_code\"}"); return; }
         if(token != "") { int n = ArraySize(retiredTokens); ArrayResize(retiredTokens, n + 1); retiredTokens[n] = token; }
         token = IssueToken();     // a re-enroll invalidates the previous unconfirmed token (D8.3)
         issuedUnconfirmed = token;
         if(dropNextEnroll) { dropNextEnroll = false; Lost(resp); return; }
         Reply(resp, 201, "{\"token\":\"" + token + "\",\"account_id\":7}");
         return;
        }
      // --- token confirm (pending token) ---
      if(path == "/v4/token/confirm")
        {
         if(bearer == "" || bearer != pendingToken) { Reply(resp, 401, "{\"error\":\"invalid_token\"}"); return; }
         int n = ArraySize(retiredTokens); ArrayResize(retiredTokens, n + 1); retiredTokens[n] = token;
         token = pendingToken;
         pendingToken = ""; pendingId = "";
         Reply(resp, 204, "");
         return;
        }
      if(bearer == "" || bearer != token) { Reply(resp, 401, "{\"error\":\"invalid_token\"}"); return; }
      if(issuedUnconfirmed == bearer) { codeConsumed = true; issuedUnconfirmed = ""; }   // first authenticated call
      if(StringFind(path, "/v4/token/rotate") == 0)
        {
         rotateCalls++;
         bool restart = StringFind(path, "restart=true") > 0;
         if(pendingToken != "" && !restart) { Reply(resp, 409, "{\"error\":\"rotation_pending\"}"); return; }
         pendingToken = IssueToken();
         pendingId = "rot_" + IntegerToString(m_tokenSeq);
         if(dropNextRotate) { dropNextRotate = false; Lost(resp); return; }
         Reply(resp, 200, "{\"new_token\":\"" + pendingToken + "\",\"pending_id\":\"" + pendingId + "\"}");
         return;
        }
      if(path == "/v4/session")
        {
         m_sessionSeq++;
         sessionId = "s_" + IntegerToString(m_sessionSeq);
         for(int i = 0; i < ArraySize(cmdState); i++)
            if(cmdState[i] == "in_progress") cmdState[i] = "queued";   // released leases
         Reply(resp, 201, "{\"session_id\":\"" + sessionId + "\",\"epoch\":" + IntegerToString(m_sessionSeq) + "}");
         return;
        }
      if(path == "/v4/config")
        {
         Reply(resp, 200, "{\"mode\":\"" + mode + "\",\"message\":\"\",\"poll_ms\":2000,\"debug\":false,"
                          "\"send_history\":false,\"symbols_wanted\":[],\"min_ea_version\":null}");
         return;
        }
      if(path == "/v4/symbols") { Reply(resp, 204, ""); return; }
      if(path == "/v4/master/snapshot" || path == "/v4/slave/snapshot")
        {
         snapshotPosts++;
         CJson *j = JsonParse(body);
         bool fenced = j == NULL || j.Str("session_id") != sessionId;
         if(j != NULL) delete j;
         if(fenced) { Reply(resp, 409, "{\"error\":\"stale_session\"}"); return; }
         Reply(resp, 200, "{\"accepted\":true}");
         return;
        }
      if(StringFind(path, "/v4/slave/commands") == 0)
        {
         commandPolls++;
         string arr = "";
         for(int i = 0; i < ArraySize(cmdIds); i++)
           {
            if(cmdState[i] == "settled" || cmdState[i] == "in_progress")
               continue;
            cmdState[i] = "delivered";
            arr += (arr == "" ? "" : ",") + cmdJson[i];
           }
         Reply(resp, 200, "{\"commands\":[" + arr + "],\"cursor\":\"0\"}");
         return;
        }
      if(path == "/v4/slave/results")
        {
         resultPosts++;
         CJson *j = JsonParse(body);
         CJson *list = j != NULL ? j.Get("results") : NULL;
         string unknown = "";
         for(int i = 0; list != NULL && i < list.Size(); i++)
           {
            CJson *r = list.At(i);
            int k = CmdIndex(r.Str("command_id"));
            if(k < 0) { unknown += (unknown == "" ? "" : ",") + "\"" + r.Str("command_id") + "\""; continue; }
            int n = ArraySize(results); ArrayResize(results, n + 1); results[n] = r.Serialize();
            string st = r.Str("status");
            if(st == "in_progress") { if(cmdState[k] != "settled") cmdState[k] = "in_progress"; }
            else if(st != "uncertain") cmdState[k] = "settled";
            else cmdState[k] = "in_progress";   // uncertain: not re-delivered until a new session
           }
         if(j != NULL) delete j;
         if(dropResults > 0) { dropResults--; Lost(resp); return; }
         Reply(resp, 200, "{\"unknown\":[" + unknown + "]}");
         return;
        }
      Reply(resp, 404, "{\"error\":\"not_found\"}");
     }
  };

#endif
