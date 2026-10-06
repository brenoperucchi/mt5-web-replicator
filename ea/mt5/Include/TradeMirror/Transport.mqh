//+------------------------------------------------------------------+
//| TradeMirror - HTTP transport                                     |
//|                                                                  |
//| ITransport is the seam used by the client tests: the Strategy    |
//| Tester does not run WebRequest, so the self-test EA injects an   |
//| in-memory fake server (TestTransport.mqh) instead.               |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_TRANSPORT_MQH
#define TRADEMIRROR_TRANSPORT_MQH

#include "Util.mqh"

#define TM_HTTP_NETWORK_ERROR (-1)   // no HTTP answer (timeout, DNS, refused, WebRequest error)
#define TM_HTTP_NOT_ALLOWED   (-2)   // URL not in the WebRequest allow-list (err 4014/4060)

struct STmHttpResponse
  {
   int               status;        // HTTP status, or TM_HTTP_* (< 0)
   int               error;         // GetLastError() when status < 0
   string            headers;
   string            body;
  };

class ITransport
  {
public:
   virtual          ~ITransport(void) {}
   //--- one synchronous attempt; never retries, never sleeps
   virtual void      Send(const string method, const string url, const string headers, const string body,
                          const int timeoutMs, STmHttpResponse &resp) = 0;
  };

//+------------------------------------------------------------------+
//| Real transport                                                   |
//+------------------------------------------------------------------+
class CWebRequestTransport : public ITransport
  {
public:
   virtual void      Send(const string method, const string url, const string headers, const string body,
                          const int timeoutMs, STmHttpResponse &resp)
     {
      uchar data[];
      uchar result[];
      string respHeaders = "";
      int n = 0;
      if(body != "")
        {
         n = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8);
         if(n > 0)
            ArrayResize(data, n - 1);   // drop the terminating zero
        }
      else
         ArrayResize(data, 0);
      ResetLastError();
      int code = WebRequest(method, url, headers, timeoutMs, data, result, respHeaders);
      resp.headers = respHeaders;
      resp.body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      if(code == -1)
        {
         resp.error = GetLastError();
         resp.status = (resp.error == 4014 || resp.error == 4060) ? TM_HTTP_NOT_ALLOWED : TM_HTTP_NETWORK_ERROR;
         return;
        }
      resp.error = 0;
      resp.status = code;
     }
  };

//--- header helpers
string TmHeaderValue(const string headers, const string name)
  {
   string lines[];
   int n = StringSplit(headers, '\n', lines);
   string want = name;
   StringToLower(want);
   for(int i = 0; i < n; i++)
     {
      int c = StringFind(lines[i], ":");
      if(c <= 0)
         continue;
      string k = StringSubstr(lines[i], 0, c);
      StringTrimLeft(k);
      StringTrimRight(k);
      StringToLower(k);
      if(k != want)
         continue;
      string v = StringSubstr(lines[i], c + 1);
      StringTrimLeft(v);
      StringTrimRight(v);
      return v;
     }
   return "";
  }

#endif
