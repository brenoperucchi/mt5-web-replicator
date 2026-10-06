//+------------------------------------------------------------------+
//| TradeMirror - minimal JSON reader/writer                          |
//|                                                                  |
//| Numbers keep their raw text so 64-bit ids (deal, position_id)    |
//| never pass through a double.                                     |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_JSON_MQH
#define TRADEMIRROR_JSON_MQH

enum ENUM_JSON_TYPE
  {
   JSON_NULL = 0,
   JSON_BOOL,
   JSON_NUMBER,
   JSON_STRING,
   JSON_ARRAY,
   JSON_OBJECT
  };

string JsonEscape(const string s)
  {
   string out = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(c == '"')       out += "\\\"";
      else if(c == '\\') out += "\\\\";
      else if(c == '\n') out += "\\n";
      else if(c == '\r') out += "\\r";
      else if(c == '\t') out += "\\t";
      else if(c < 0x20)  out += StringFormat("\\u%04x", c);
      else               out += ShortToString(c);
     }
   return out;
  }

//--- number formatting: up to 8 decimals, trailing zeros trimmed
string JsonNum(const double v, const int digits = 8)
  {
   string s = DoubleToString(v, digits);
   if(StringFind(s, ".") >= 0)
     {
      int len = StringLen(s);
      while(len > 0 && StringGetCharacter(s, len - 1) == '0')
         len--;
      if(len > 0 && StringGetCharacter(s, len - 1) == '.')
         len--;
      s = StringSubstr(s, 0, len);
     }
   if(s == "-0")
      s = "0";
   return s;
  }

ushort JsonHex4(const string hex)
  {
   uint v = 0;
   for(int i = 0; i < StringLen(hex); i++)
     {
      ushort c = StringGetCharacter(hex, i);
      uint d = 0;
      if(c >= '0' && c <= '9') d = c - '0';
      else if(c >= 'a' && c <= 'f') d = 10 + c - 'a';
      else if(c >= 'A' && c <= 'F') d = 10 + c - 'A';
      v = v * 16 + d;
     }
   return (ushort)v;
  }

//+------------------------------------------------------------------+
//| Parsed value tree                                                |
//+------------------------------------------------------------------+
class CJson
  {
public:
   ENUM_JSON_TYPE    type;
   string            text;        // string value, or raw number text, or "true"/"false"
   string            keys[];
   CJson            *items[];

                     CJson(void) { type = JSON_NULL; text = ""; }
                    ~CJson(void) { Clear(); }

   void              Clear(void)
     {
      for(int i = 0; i < ArraySize(items); i++)
         if(CheckPointer(items[i]) == POINTER_DYNAMIC)
            delete items[i];
      ArrayResize(items, 0);
      ArrayResize(keys, 0);
     }

   int               Size(void) const { return ArraySize(items); }
   CJson            *At(const int i) { return (i >= 0 && i < ArraySize(items)) ? items[i] : NULL; }
   bool              IsNull(void) const { return type == JSON_NULL; }

   CJson            *Get(const string key)
     {
      if(type != JSON_OBJECT)
         return NULL;
      for(int i = 0; i < ArraySize(keys); i++)
         if(keys[i] == key)
            return items[i];
      return NULL;
     }

   bool              Has(const string key) { CJson *v = Get(key); return v != NULL && v.type != JSON_NULL; }

   string            Str(const string key, const string def = "")
     {
      CJson *v = Get(key);
      if(v == NULL || v.type == JSON_NULL)
         return def;
      return v.text;
     }
   long              Long(const string key, const long def = 0)
     {
      CJson *v = Get(key);
      if(v == NULL || v.type != JSON_NUMBER)
         return def;
      return StringToInteger(v.text);
     }
   double            Dbl(const string key, const double def = 0.0)
     {
      CJson *v = Get(key);
      if(v == NULL || v.type != JSON_NUMBER)
         return def;
      return StringToDouble(v.text);
     }
   bool              Bool(const string key, const bool def = false)
     {
      CJson *v = Get(key);
      if(v == NULL || v.type != JSON_BOOL)
         return def;
      return v.text == "true";
     }

   void              Add(const string key, CJson *child)
     {
      int n = ArraySize(items);
      ArrayResize(items, n + 1);
      ArrayResize(keys, n + 1);
      items[n] = child;
      keys[n] = key;
     }

   string            Serialize(void)
     {
      switch(type)
        {
         case JSON_NULL:   return "null";
         case JSON_BOOL:   return text;
         case JSON_NUMBER: return text;
         case JSON_STRING: return "\"" + JsonEscape(text) + "\"";
         case JSON_ARRAY:
           {
            string s = "[";
            for(int i = 0; i < ArraySize(items); i++)
              {
               if(i > 0) s += ",";
               s += items[i].Serialize();
              }
            return s + "]";
           }
         case JSON_OBJECT:
           {
            string s = "{";
            for(int i = 0; i < ArraySize(items); i++)
              {
               if(i > 0) s += ",";
               s += "\"" + JsonEscape(keys[i]) + "\":" + items[i].Serialize();
              }
            return s + "}";
           }
        }
      return "null";
     }
  };

//+------------------------------------------------------------------+
//| Recursive-descent parser. Returns NULL on malformed input.       |
//+------------------------------------------------------------------+
class CJsonParser
  {
private:
   string            m_s;
   int               m_pos;
   int               m_len;
   bool              m_err;

   void              Ws(void)
     {
      while(m_pos < m_len)
        {
         ushort c = StringGetCharacter(m_s, m_pos);
         if(c == ' ' || c == '\t' || c == '\n' || c == '\r')
            m_pos++;
         else
            break;
        }
     }
   ushort            Peek(void) { return m_pos < m_len ? StringGetCharacter(m_s, m_pos) : 0; }

   bool              ParseString(string &out)
     {
      out = "";
      if(Peek() != '"') { m_err = true; return false; }
      m_pos++;
      while(m_pos < m_len)
        {
         ushort c = StringGetCharacter(m_s, m_pos++);
         if(c == '"')
            return true;
         if(c == '\\')
           {
            if(m_pos >= m_len) break;
            ushort e = StringGetCharacter(m_s, m_pos++);
            if(e == 'n') out += "\n";
            else if(e == 'r') out += "\r";
            else if(e == 't') out += "\t";
            else if(e == 'b') out += ShortToString(8);
            else if(e == 'f') out += ShortToString(12);
            else if(e == 'u')
              {
               if(m_pos + 4 > m_len) break;
               string hex = StringSubstr(m_s, m_pos, 4);
               m_pos += 4;
               out += ShortToString(JsonHex4(hex));
              }
            else out += ShortToString(e);
           }
         else
            out += ShortToString(c);
        }
      m_err = true;
      return false;
     }

   CJson            *ParseValue(void)
     {
      Ws();
      ushort c = Peek();
      CJson *v = new CJson();
      if(c == '{')
        {
         v.type = JSON_OBJECT;
         m_pos++;
         Ws();
         if(Peek() == '}') { m_pos++; return v; }
         while(!m_err)
           {
            Ws();
            string key;
            if(!ParseString(key)) break;
            Ws();
            if(Peek() != ':') { m_err = true; break; }
            m_pos++;
            CJson *child = ParseValue();
            if(child == NULL) { m_err = true; break; }
            v.Add(key, child);
            Ws();
            if(Peek() == ',') { m_pos++; continue; }
            if(Peek() == '}') { m_pos++; return v; }
            m_err = true;
           }
         delete v;
         return NULL;
        }
      if(c == '[')
        {
         v.type = JSON_ARRAY;
         m_pos++;
         Ws();
         if(Peek() == ']') { m_pos++; return v; }
         while(!m_err)
           {
            CJson *child = ParseValue();
            if(child == NULL) { m_err = true; break; }
            v.Add("", child);
            Ws();
            if(Peek() == ',') { m_pos++; continue; }
            if(Peek() == ']') { m_pos++; return v; }
            m_err = true;
           }
         delete v;
         return NULL;
        }
      if(c == '"')
        {
         v.type = JSON_STRING;
         string s;
         if(!ParseString(s)) { delete v; return NULL; }
         v.text = s;
         return v;
        }
      if(StringSubstr(m_s, m_pos, 4) == "true")  { v.type = JSON_BOOL; v.text = "true";  m_pos += 4; return v; }
      if(StringSubstr(m_s, m_pos, 5) == "false") { v.type = JSON_BOOL; v.text = "false"; m_pos += 5; return v; }
      if(StringSubstr(m_s, m_pos, 4) == "null")  { v.type = JSON_NULL; m_pos += 4; return v; }
      // number
      int start = m_pos;
      while(m_pos < m_len)
        {
         ushort d = StringGetCharacter(m_s, m_pos);
         if((d >= '0' && d <= '9') || d == '-' || d == '+' || d == '.' || d == 'e' || d == 'E')
            m_pos++;
         else
            break;
        }
      if(m_pos == start) { m_err = true; delete v; return NULL; }
      v.type = JSON_NUMBER;
      v.text = StringSubstr(m_s, start, m_pos - start);
      return v;
     }

public:
   CJson            *Parse(const string s)
     {
      m_s = s;
      m_pos = 0;
      m_len = StringLen(s);
      m_err = false;
      CJson *v = ParseValue();
      if(v != NULL && m_err) { delete v; return NULL; }
      return v;
     }
  };

CJson *JsonParse(const string s)
  {
   CJsonParser p;
   return p.Parse(s);
  }

//+------------------------------------------------------------------+
//| Streaming writer                                                 |
//+------------------------------------------------------------------+
class CJsonWriter
  {
private:
   string            m_s;
   bool              m_first[];
   int               m_depth;

   void              Sep(const string key)
     {
      if(m_depth > 0)
        {
         if(!m_first[m_depth - 1]) m_s += ",";
         m_first[m_depth - 1] = false;
        }
      if(key != "")
         m_s += "\"" + JsonEscape(key) + "\":";
     }
   void              Push(void) { m_depth++; ArrayResize(m_first, m_depth); m_first[m_depth - 1] = true; }

public:
                     CJsonWriter(void) { m_s = ""; m_depth = 0; }
   string            Text(void) const { return m_s; }
   void              Reset(void) { m_s = ""; m_depth = 0; ArrayResize(m_first, 0); }

   void              BeginObj(const string key = "") { Sep(key); m_s += "{"; Push(); }
   void              EndObj(void)  { m_s += "}"; m_depth--; }
   void              BeginArr(const string key = "") { Sep(key); m_s += "["; Push(); }
   void              EndArr(void)  { m_s += "]"; m_depth--; }

   void              Str(const string key, const string v)  { Sep(key); m_s += "\"" + JsonEscape(v) + "\""; }
   void              Int(const string key, const long v)    { Sep(key); m_s += IntegerToString(v); }
   void              Num(const string key, const double v, const int digits = 8) { Sep(key); m_s += JsonNum(v, digits); }
   void              Bool(const string key, const bool v)   { Sep(key); m_s += (v ? "true" : "false"); }
   void              Null(const string key)                 { Sep(key); m_s += "null"; }
   // StringLen, not == "": an unassigned MQL5 string is NULL, and NULL == "" is false, so the
   // old check let a NULL through and emitted `"key":,` (invalid JSON).
   void              Raw(const string key, const string json) { Sep(key); m_s += (StringLen(json) == 0 ? "null" : json); }
   //--- optional numbers: 0 / EMPTY means "unknown" and is written as null
   void              IntOrNull(const string key, const long v) { if(v == 0) Null(key); else Int(key, v); }
   void              NumOrNull(const string key, const double v, const int digits = 8) { if(v == 0.0) Null(key); else Num(key, v, digits); }
  };

#endif
