//+------------------------------------------------------------------+
//| TradeMirror - durable command journal (design 4.6)               |
//|                                                                  |
//| One entry per (command_id, attempt_id). File is append-only      |
//| JSONL; the last line for a key wins. Compacted on start with a   |
//| temp file + FileMove(FILE_REWRITE).                              |
//|                                                                  |
//| States: prepared -> sent -> confirmed                            |
//|                        \-> uncertain -> confirmed | suspended    |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_JOURNAL_MQH
#define TRADEMIRROR_JOURNAL_MQH

#include "Json.mqh"
#include "Util.mqh"

#define JS_PREPARED  "prepared"
#define JS_SENT      "sent"
#define JS_UNCERTAIN "uncertain"
#define JS_CONFIRMED "confirmed"
#define JS_SUSPENDED "suspended"

#define TM_JOURNAL_KEEP_DAYS 7

class CJournalEntry
  {
public:
   string            command_id;
   string            attempt_id;
   long              copy_id;
   string            action;
   long              seq_in_copy;
   string            state;
   string            command;          // raw command JSON as received (frozen exec params)
   ulong             order;
   uint              request_id;
   ulong             deal;
   ulong             position_id;
   double            executed_volume;
   double            residual_volume;
   string            result;           // raw result JSON (what was / will be posted)
   long              created_ms;
   long              updated_ms;
   long              sent_ms;          // local ms of the OrderSend call (uncertain window)
   int               checks;           // evidence re-checks done while uncertain

                     CJournalEntry(void)
     {
      copy_id = 0; seq_in_copy = 0; order = 0; request_id = 0; deal = 0; position_id = 0;
      executed_volume = 0; residual_volume = 0; created_ms = 0; updated_ms = 0; sent_ms = 0; checks = 0;
     }

   string            Key(void) const { return command_id + "/" + attempt_id; }
   bool              Blocking(void) const { return state == JS_SENT || state == JS_UNCERTAIN || state == JS_SUSPENDED; }

   string            ToJson(void)
     {
      CJsonWriter w;
      w.BeginObj();
      w.Str("command_id", command_id);
      w.Str("attempt_id", attempt_id);
      w.Int("copy_id", copy_id);
      w.Str("action", action);
      w.Int("seq_in_copy", seq_in_copy);
      w.Str("state", state);
      w.Raw("command", command);
      w.Int("order", (long)order);
      w.Int("request_id", (long)request_id);
      w.Int("deal", (long)deal);
      w.Int("position_id", (long)position_id);
      w.Num("executed_volume", executed_volume);
      w.Num("residual_volume", residual_volume);
      w.Raw("result", result);
      w.Int("created_ms", created_ms);
      w.Int("updated_ms", updated_ms);
      w.Int("sent_ms", sent_ms);
      w.Int("checks", checks);
      w.EndObj();
      return w.Text();
     }

   bool              FromJson(CJson *j)
     {
      if(j == NULL || j.type != JSON_OBJECT)
         return false;
      command_id = j.Str("command_id");
      attempt_id = j.Str("attempt_id");
      if(command_id == "")
         return false;
      copy_id = j.Long("copy_id");
      action = j.Str("action");
      seq_in_copy = j.Long("seq_in_copy");
      state = j.Str("state");
      CJson *c = j.Get("command");
      command = (c != NULL && c.type != JSON_NULL) ? c.Serialize() : "";
      order = (ulong)j.Long("order");
      request_id = (uint)j.Long("request_id");
      deal = (ulong)j.Long("deal");
      position_id = (ulong)j.Long("position_id");
      executed_volume = j.Dbl("executed_volume");
      residual_volume = j.Dbl("residual_volume");
      CJson *r = j.Get("result");
      result = (r != NULL && r.type != JSON_NULL) ? r.Serialize() : "";
      created_ms = j.Long("created_ms");
      updated_ms = j.Long("updated_ms");
      sent_ms = j.Long("sent_ms");
      checks = (int)j.Long("checks");
      return true;
     }
  };

class CJournal
  {
private:
   string            m_path;
   CJournalEntry    *m_items[];

public:
                     CJournal(void) { m_path = ""; }
                    ~CJournal(void) { Clear(); }

   void              Clear(void)
     {
      for(int i = 0; i < ArraySize(m_items); i++)
         if(CheckPointer(m_items[i]) == POINTER_DYNAMIC)
            delete m_items[i];
      ArrayResize(m_items, 0);
     }

   int               Total(void) const { return ArraySize(m_items); }
   CJournalEntry    *At(const int i) { return m_items[i]; }
   string            Path(void) const { return m_path; }

   //--- load + compact (on start)
   bool              Open(const string path)
     {
      m_path = path;
      Clear();
      string lines[];
      int n = TmReadLines(path, lines);
      for(int i = 0; i < n; i++)
        {
         CJson *j = JsonParse(lines[i]);
         if(j == NULL)
           {
            TmLog.Warn("journal: skipping malformed line " + IntegerToString(i + 1));
            continue;
           }
         CJournalEntry *e = new CJournalEntry();
         if(!e.FromJson(j))
           {
            delete e;
            delete j;
            continue;
           }
         delete j;
         CJournalEntry *old = Find(e.command_id, e.attempt_id);
         if(old != NULL)
           {
            Replace(old, e);
            delete e;
           }
         else
            Push(e);
        }
      return Compact();
     }

   bool              Compact(void)
     {
      long cutoff = TmNowMs() - (long)TM_JOURNAL_KEEP_DAYS * 86400000;
      string content = "";
      CJournalEntry *keep[];
      for(int i = 0; i < ArraySize(m_items); i++)
        {
         CJournalEntry *e = m_items[i];
         // confirmed entries are kept a week so a re-delivered command is answered from the journal
         if(e.state == JS_CONFIRMED && e.updated_ms > 0 && e.updated_ms < cutoff)
           {
            delete e;
            continue;
           }
         int k = ArraySize(keep);
         ArrayResize(keep, k + 1);
         keep[k] = e;
         content += e.ToJson() + "\n";
        }
      ArrayResize(m_items, ArraySize(keep));
      for(int i = 0; i < ArraySize(keep); i++)
         m_items[i] = keep[i];
      return TmWriteAtomic(m_path, content);
     }

   CJournalEntry    *Find(const string commandId, const string attemptId)
     {
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].command_id == commandId && m_items[i].attempt_id == attemptId)
            return m_items[i];
      return NULL;
     }

   //--- most recent attempt of a logical command
   CJournalEntry    *FindLatest(const string commandId)
     {
      CJournalEntry *best = NULL;
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].command_id == commandId && (best == NULL || m_items[i].created_ms >= best.created_ms))
            best = m_items[i];
      return best;
     }

   //--- an attempt of this copy that is sent/uncertain/suspended blocks the copy (4.6 step 1)
   CJournalEntry    *BlockingForCopy(const long copyId)
     {
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].copy_id == copyId && m_items[i].Blocking())
            return m_items[i];
      return NULL;
     }

   CJournalEntry    *LatestOfActionForCopy(const long copyId, const string action)
     {
      CJournalEntry *best = NULL;
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].copy_id == copyId && m_items[i].action == action &&
            (best == NULL || m_items[i].created_ms >= best.created_ms))
            best = m_items[i];
      return best;
     }

   CJournalEntry    *FindByOrder(const ulong order)
     {
      if(order == 0)
         return NULL;
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].order == order)
            return m_items[i];
      return NULL;
     }

   CJournalEntry    *FindByRequestId(const uint requestId)
     {
      if(requestId == 0)
         return NULL;
      for(int i = 0; i < ArraySize(m_items); i++)
         if(m_items[i].request_id == requestId && m_items[i].Blocking())
            return m_items[i];
      return NULL;
     }

   CJournalEntry    *Create(const string commandId, const string attemptId, const long copyId, const string action,
                            const long seq, const string commandJson)
     {
      CJournalEntry *e = new CJournalEntry();
      e.command_id = commandId;
      e.attempt_id = attemptId;
      e.copy_id = copyId;
      e.action = action;
      e.seq_in_copy = seq;
      e.command = commandJson;
      e.created_ms = TmNowMs();
      Push(e);
      return e;
     }

   //--- persist the entry's current state: one flushed line (4.6 step 3)
   bool              Save(CJournalEntry *e)
     {
      e.updated_ms = TmNowMs();
      return TmAppendLine(m_path, e.ToJson());
     }

private:
   void              Push(CJournalEntry *e)
     {
      int n = ArraySize(m_items);
      ArrayResize(m_items, n + 1);
      m_items[n] = e;
     }
   void              Replace(CJournalEntry *dst, CJournalEntry *src)
     {
      dst.copy_id = src.copy_id; dst.action = src.action; dst.seq_in_copy = src.seq_in_copy;
      dst.state = src.state; dst.command = src.command; dst.order = src.order; dst.request_id = src.request_id;
      dst.deal = src.deal; dst.position_id = src.position_id; dst.executed_volume = src.executed_volume;
      dst.residual_volume = src.residual_volume; dst.result = src.result; dst.created_ms = src.created_ms;
      dst.updated_ms = src.updated_ms; dst.sent_ms = src.sent_ms; dst.checks = src.checks;
     }
  };

#endif
