//+------------------------------------------------------------------+
//| TradeMirror - logging, ids, clocks, atomic files                 |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_UTIL_MQH
#define TRADEMIRROR_UTIL_MQH

#define TM_EA_VERSION "1.0.0"
#define TM_PRODUCT    "TradeMirror"

enum ENUM_TM_LOG
  {
   TM_DEBUG = 0,
   TM_INFO,
   TM_WARN,
   TM_ALERT
  };

//+------------------------------------------------------------------+
//| Log: terminal journal, optional chart comment, upload buffer     |
//+------------------------------------------------------------------+
class CTmLog
  {
private:
   string            m_buffer[];     // lines waiting for POST /v4/logs (debug only)
   string            m_lastAlert;
   bool              m_verbose;
   bool              m_popups;

public:
                     CTmLog(void) { m_verbose = false; m_popups = true; m_lastAlert = ""; }
   void              Verbose(const bool v) { m_verbose = v; }
   void              Popups(const bool v) { m_popups = v; }
   string            LastAlert(void) const { return m_lastAlert; }

   void              Write(const ENUM_TM_LOG level, const string msg)
     {
      if(level == TM_DEBUG && !m_verbose)
         return;
      string tag = (level == TM_DEBUG ? "DEBUG" : level == TM_INFO ? "INFO" : level == TM_WARN ? "WARN" : "ALERT");
      string line = StringFormat("%s [%s] %s", TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS), tag, msg);
      Print(TM_PRODUCT, " ", line);
      int n = ArraySize(m_buffer);
      if(n < 2000)
        {
         ArrayResize(m_buffer, n + 1);
         m_buffer[n] = line;
        }
      if(level == TM_ALERT)
        {
         m_lastAlert = msg;
         if(m_popups && !MQLInfoInteger(MQL_TESTER))
            Alert(TM_PRODUCT, ": ", msg);
        }
     }
   void              Debug(const string m) { Write(TM_DEBUG, m); }
   void              Info(const string m)  { Write(TM_INFO, m); }
   void              Warn(const string m)  { Write(TM_WARN, m); }
   void              Alarm(const string m) { Write(TM_ALERT, m); }

   //--- drain up to maxBytes of buffered lines (for /v4/logs)
   string            TakeBuffer(const int maxBytes)
     {
      string out = "";
      int taken = 0;
      for(int i = 0; i < ArraySize(m_buffer); i++)
        {
         if(StringLen(out) + StringLen(m_buffer[i]) + 1 > maxBytes)
            break;
         out += m_buffer[i] + "\n";
         taken++;
        }
      if(taken > 0)
        {
         int rest = ArraySize(m_buffer) - taken;
         for(int i = 0; i < rest; i++)
            m_buffer[i] = m_buffer[i + taken];
         ArrayResize(m_buffer, rest);
        }
      return out;
     }
   void              ClearBuffer(void) { ArrayResize(m_buffer, 0); }
  };

CTmLog TmLog;

//+------------------------------------------------------------------+
//| Clock: UTC ms, server offset (server_time - local)               |
//+------------------------------------------------------------------+
// Test seam: when > 0, both clocks read this value (self-test EA drives time explicitly).
long g_tm_fake_now_ms = 0;

long TmNowMs(void)
  {
   if(g_tm_fake_now_ms > 0)
      return g_tm_fake_now_ms;
   // TimeGMT has 1 s resolution; the sub-second part is approximated from the tick counter.
   return (long)TimeGMT() * 1000 + (long)(GetTickCount64() % 1000);
  }

long TmMonoMs(void) { return g_tm_fake_now_ms > 0 ? g_tm_fake_now_ms : (long)GetTickCount64(); }

//+------------------------------------------------------------------+
//| Random ids (UUID v4 format). Uniqueness, not secrecy, matters.   |
//+------------------------------------------------------------------+
bool g_tm_seeded = false;

string TmUuid(void)
  {
   if(!g_tm_seeded)
     {
      MathSrand((int)(GetMicrosecondCount() ^ (ulong)TimeLocal() ^ (ulong)AccountInfoInteger(ACCOUNT_LOGIN)));
      g_tm_seeded = true;
     }
   uchar b[16];
   ulong mix = GetMicrosecondCount();
   for(int i = 0; i < 16; i++)
     {
      mix = mix * 6364136223846793005 + 1442695040888963407 + (ulong)MathRand();
      b[i] = (uchar)((mix >> 33) & 0xFF);
     }
   b[6] = (uchar)((b[6] & 0x0F) | 0x40);
   b[8] = (uchar)((b[8] & 0x3F) | 0x80);
   string s = "";
   for(int i = 0; i < 16; i++)
     {
      if(i == 4 || i == 6 || i == 8 || i == 10)
         s += "-";
      s += StringFormat("%02x", b[i]);
     }
   return s;
  }

//+------------------------------------------------------------------+
//| Server name normalisation for file names                          |
//+------------------------------------------------------------------+
string TmSafeName(const string s)
  {
   string out = "";
   for(int i = 0; i < StringLen(s); i++)
     {
      ushort c = StringGetCharacter(s, i);
      if((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.')
         out += ShortToString(c);
      else if(c >= 'A' && c <= 'Z')
         out += ShortToString((ushort)(c + 32));
      else
         out += "_";
     }
   return out;
  }

//+------------------------------------------------------------------+
//| Files in MQL5\Files (terminal-local, never FILE_COMMON)          |
//+------------------------------------------------------------------+
// Whole-file atomic replace: temp file, flush, FileMove(FILE_REWRITE).
bool TmWriteAtomic(const string path, const string content)
  {
   string tmp = path + ".tmp";
   ResetLastError();
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      TmLog.Warn(StringFormat("cannot open %s for write (err %d)", tmp, GetLastError()));
      return false;
     }
   FileWriteString(h, content);
   FileFlush(h);
   FileClose(h);
   ResetLastError();
   if(!FileMove(tmp, 0, path, FILE_REWRITE))
     {
      TmLog.Warn(StringFormat("cannot move %s -> %s (err %d)", tmp, path, GetLastError()));
      return false;
     }
   return true;
  }

// Append one line and flush before returning (journal/outbox durability, 4.6).
bool TmAppendLine(const string path, const string line)
  {
   ResetLastError();
   int h = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
     {
      TmLog.Warn(StringFormat("cannot open %s for append (err %d)", path, GetLastError()));
      return false;
     }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\n");
   FileFlush(h);
   FileClose(h);
   return true;
  }

// Read all non-empty lines.
int TmReadLines(const string path, string &lines[])
  {
   ArrayResize(lines, 0);
   if(!FileIsExist(path))
      return 0;
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return 0;
   while(!FileIsEnding(h))
     {
      string l = FileReadString(h);
      StringTrimLeft(l);
      StringTrimRight(l);
      if(l == "")
         continue;
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = l;
     }
   FileClose(h);
   return ArraySize(lines);
  }

string TmReadAll(const string path)
  {
   string lines[];
   TmReadLines(path, lines);
   string s = "";
   for(int i = 0; i < ArraySize(lines); i++)
      s += lines[i];
   return s;
  }

#endif
