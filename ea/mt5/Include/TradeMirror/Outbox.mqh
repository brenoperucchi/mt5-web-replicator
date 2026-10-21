//+------------------------------------------------------------------+
//| TradeMirror - durable results outbox (design 4.2, 4.6 step 8)    |
//|                                                                  |
//| Every result is appended (and flushed) before it is posted and   |
//| stays until a 2xx (or until the server lists its command in      |
//| `unknown`). Results are event requests: never dropped.           |
//| File lines: {"id":n,"result":{...}}  |  {"ack":n}                |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_OUTBOX_MQH
#define TRADEMIRROR_OUTBOX_MQH

#include "Json.mqh"
#include "Util.mqh"

#define TM_RESULTS_BATCH_MAX 50

class COutbox
  {
private:
   string            m_path;
   long              m_ids[];
   string            m_results[];
   string            m_commandIds[];
   long              m_next;
   int               m_acksSinceCompact;

   void              Push(const long id, const string result, const string commandId)
     {
      int n = ArraySize(m_ids);
      ArrayResize(m_ids, n + 1);
      ArrayResize(m_results, n + 1);
      ArrayResize(m_commandIds, n + 1);
      m_ids[n] = id;
      m_results[n] = result;
      m_commandIds[n] = commandId;
     }
   void              RemoveAt(const int i)
     {
      int n = ArraySize(m_ids);
      for(int k = i; k < n - 1; k++)
        {
         m_ids[k] = m_ids[k + 1];
         m_results[k] = m_results[k + 1];
         m_commandIds[k] = m_commandIds[k + 1];
        }
      ArrayResize(m_ids, n - 1);
      ArrayResize(m_results, n - 1);
      ArrayResize(m_commandIds, n - 1);
     }
   int               IndexOf(const long id)
     {
      for(int i = 0; i < ArraySize(m_ids); i++)
         if(m_ids[i] == id)
            return i;
      return -1;
     }

public:
                     COutbox(void) { m_next = 0; m_acksSinceCompact = 0; }
   int               Count(void) const { return ArraySize(m_ids); }

   bool              Open(const string path)
     {
      m_path = path;
      ArrayResize(m_ids, 0);
      ArrayResize(m_results, 0);
      ArrayResize(m_commandIds, 0);
      m_next = 0;
      string lines[];
      int n = TmReadLines(path, lines);
      for(int i = 0; i < n; i++)
        {
         CJson *j = JsonParse(lines[i]);
         if(j == NULL)
            continue;
         if(j.Has("ack"))
           {
            int idx = IndexOf(j.Long("ack"));
            if(idx >= 0)
               RemoveAt(idx);
           }
         else if(j.Has("id"))
           {
            long id = j.Long("id");
            CJson *r = j.Get("result");
            if(r != NULL && IndexOf(id) < 0)
               Push(id, r.Serialize(), r.Str("command_id"));
            if(id > m_next)
               m_next = id;
           }
         delete j;
        }
      return Compact();
     }

   bool              Compact(void)
     {
      string content = "";
      for(int i = 0; i < ArraySize(m_ids); i++)
         content += "{\"id\":" + IntegerToString(m_ids[i]) + ",\"result\":" + m_results[i] + "}\n";
      m_acksSinceCompact = 0;
      return TmWriteAtomic(m_path, content);
     }

   //--- durable before return
   bool              Enqueue(const string resultJson, const string commandId)
     {
      long id = ++m_next;
      if(!TmAppendLine(m_path, "{\"id\":" + IntegerToString(id) + ",\"result\":" + resultJson + "}"))
         return false;
      Push(id, resultJson, commandId);
      return true;
     }

   //--- a results batch: at most 50 (bounded body, 4.2)
   int               PeekBatch(long &ids[], string &body)
     {
      int n = MathMin(ArraySize(m_ids), TM_RESULTS_BATCH_MAX);
      ArrayResize(ids, n);
      body = "{\"results\":[";
      for(int i = 0; i < n; i++)
        {
         ids[i] = m_ids[i];
         if(i > 0)
            body += ",";
         body += m_results[i];
        }
      body += "]}";
      return n;
     }

   void              Ack(const long &ids[])
     {
      for(int i = 0; i < ArraySize(ids); i++)
        {
         int idx = IndexOf(ids[i]);
         if(idx < 0)
            continue;
         TmAppendLine(m_path, "{\"ack\":" + IntegerToString(ids[i]) + "}");
         RemoveAt(idx);
         m_acksSinceCompact++;
        }
      if(m_acksSinceCompact > 500)
         Compact();
     }

   string            CommandIdOf(const long id)
     {
      int i = IndexOf(id);
      return i >= 0 ? m_commandIds[i] : "";
     }

   bool              HasCommand(const string commandId)
     {
      for(int i = 0; i < ArraySize(m_commandIds); i++)
         if(m_commandIds[i] == commandId)
            return true;
      return false;
     }
  };

#endif
