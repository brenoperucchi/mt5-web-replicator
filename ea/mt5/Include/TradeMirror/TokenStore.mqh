//+------------------------------------------------------------------+
//| TradeMirror - per-terminal token file (design D8 steps 4-5)      |
//|                                                                  |
//| MQL5\Files\TradeMirror\copy_token_<server>_<login>_<role>.dat    |
//| (terminal-local, never FILE_COMMON). Always written atomically.  |
//| Holds the current token and, during a rotation, the pending one. |
//| The token is never logged.                                       |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_TOKENSTORE_MQH
#define TRADEMIRROR_TOKENSTORE_MQH

#include "Json.mqh"
#include "Util.mqh"

class CTokenStore
  {
private:
   string            m_path;

public:
   string            token;
   long              issued_ms;
   long              account_id;
   long              login;
   string            pending_token;
   string            pending_id;

                     CTokenStore(void) { Reset(); }
   void              Reset(void) { token = ""; issued_ms = 0; account_id = 0; login = 0; pending_token = ""; pending_id = ""; }
   void              SetPath(const string path) { m_path = path; }
   string            Path(void) const { return m_path; }
   bool              HasToken(void) const { return token != ""; }

   bool              Load(void)
     {
      Reset();
      if(!FileIsExist(m_path))
         return false;
      CJson *j = JsonParse(TmReadAll(m_path));
      if(j == NULL)
        {
         TmLog.Alarm("token file is unreadable: re-enroll with a new code");
         return false;
        }
      token = j.Str("token");
      issued_ms = j.Long("issued_ms");
      account_id = j.Long("account_id");
      login = j.Long("login");
      pending_token = j.Str("pending_token");
      pending_id = j.Str("pending_id");
      delete j;
      return token != "";
     }

   bool              Save(void)
     {
      CJsonWriter w;
      w.BeginObj();
      w.Str("token", token);
      w.Int("issued_ms", issued_ms);
      w.Int("account_id", account_id);
      w.Int("login", login);
      if(pending_token != "")
        {
         w.Str("pending_token", pending_token);
         w.Str("pending_id", pending_id);
        }
      w.EndObj();
      return TmWriteAtomic(m_path, w.Text());
     }

   //--- rotation step 1: the new token is on disk before /v4/token/confirm is called
   bool              StorePending(const string newToken, const string pendingId)
     {
      pending_token = newToken;
      pending_id = pendingId;
      return Save();
     }

   //--- rotation step 2 (confirm answered 204): the pending token becomes the token
   bool              PromotePending(void)
     {
      token = pending_token;
      issued_ms = TmNowMs();
      pending_token = "";
      pending_id = "";
      return Save();
     }

   bool              DropPending(void)
     {
      pending_token = "";
      pending_id = "";
      return Save();
     }
  };

#endif
