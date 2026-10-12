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
#define TM_HTTP_NOT_ALLOWED   (-2)   // URL not in the WebRequest allow-list (err 4006 on build 6244, 4014, 4060)
#define TM_WR_TLS_FAILED      1009   // WebRequest "status" 1009: TLS handshake / secure connection failed

struct STmHttpResponse
  {
   int               status;        // HTTP status, or TM_HTTP_* (< 0)
   int               error;         // GetLastError() when status < 0
   string            headers;
   string            body;
  };

//--- WebRequest return value + GetLastError() -> (status, error). Codes >= 1000 are terminal-side
//    connection errors, not HTTP: they become a network error (transient) carrying the code.
void TmClassifyWebRequest(const int code, const int lastError, int &status, int &error)
  {
   if(code == -1)
     {
      error = lastError;
      status = (lastError == 4006 || lastError == 4014 || lastError == 4060) ? TM_HTTP_NOT_ALLOWED : TM_HTTP_NETWORK_ERROR;
      return;
     }
   if(code >= 1000)
     {
      error = code;
      status = TM_HTTP_NETWORK_ERROR;
      return;
     }
   error = 0;
   status = code;
  }

//--- operator hint for a failed call ("" when there is nothing specific to say)
string TmTransportHint(const int status, const int error, const string url)
  {
   if(status == TM_HTTP_NOT_ALLOWED)
      return "URL not allowed in Tools > Options > Expert Advisors > WebRequest: " + url;
   if(status == TM_HTTP_NETWORK_ERROR && error == TM_WR_TLS_FAILED)
      return "TLS failed (error 1009) - does the server speak https? check ServerUrl scheme: " + url;
   return "";
  }

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
      TmClassifyWebRequest(code, code == -1 ? GetLastError() : 0, resp.status, resp.error);
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
