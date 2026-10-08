//+------------------------------------------------------------------+
//| TradeMirror - terminal state: snapshots, symbol specs, evidence  |
//| lookups by position id / order / deal / comment+magic            |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_BROKER_MQH
#define TRADEMIRROR_BROKER_MQH

#include "Json.mqh"
#include "Util.mqh"

#define TM_HISTORY_MIN_DEALS   30
#define TM_EVIDENCE_DAYS       7

// Test seam (self-test EA only): pretend the broker rewrote the comment and the ids are unknown,
// i.e. no evidence is visible (S04 / S39). Never set by the production EA.
bool g_tm_hide_evidence = false;

string TmSide(const long type) { return type == POSITION_TYPE_BUY ? "buy" : "sell"; }

//+------------------------------------------------------------------+
//| Copier comment correlation (design 5.8a, same rule as the server |
//| engine.correlation). The command comment is                     |
//| c<copy_id>-<master position_id> (or legacy c<copy_id>); only the |
//| c<copy_id> part correlates, always together with the magic:      |
//|  - "c<digits>-<anything>": id = digits before the first '-'; a   |
//|    suffix truncated or rewritten by the broker is tolerated.     |
//|  - "c<digits>" (no '-'): accepted only when the command comment  |
//|    is exactly the legacy "c<copy_id>"; for a long-form command   |
//|    it is ambiguous (a cut before '-' looks like a cut inside the |
//|    digits) and rejected.                                         |
//+------------------------------------------------------------------+
// Copy id of a copier comment ("c<digits>" optionally followed by "-..."), -1 when not one.
// `dashed` reports whether the digits were terminated by '-'.
long TmCommentCopyId(const string comment, bool &dashed)
  {
   dashed = false;
   int n = StringLen(comment);
   if(n < 2 || StringGetCharacter(comment, 0) != 'c')
      return -1;
   int i = 1;
   while(i < n && StringGetCharacter(comment, i) >= '0' && StringGetCharacter(comment, i) <= '9')
      i++;
   if(i == 1 || i - 1 > 18)
      return -1;
   if(i < n)
     {
      if(StringGetCharacter(comment, i) != '-')
         return -1;
      dashed = true;
     }
   return StringToInteger(StringSubstr(comment, 1, i - 1));
  }

bool TmAllDigits(const string s)
  {
   int n = StringLen(s);
   if(n == 0)
      return false;
   for(int i = 0; i < n; i++)
      if(StringGetCharacter(s, i) < '0' || StringGetCharacter(s, i) > '9')
         return false;
   return true;
  }

// True when the broker-side `actual` comment correlates with the command comment `expected`.
// A digits-only suffix is the master position id written by a copier: it must be the expected one
// or a truncation of it (c22-<other master id> is another copy that reused the same copy id, e.g.
// from another Copy Server). A suffix with anything else in it was rewritten by the broker: prefix rule.
bool TmCommentMatches(const string expected, const string actual)
  {
   bool expDashed, actDashed;
   long want = TmCommentCopyId(expected, expDashed);
   if(want < 0)
      return actual == expected;   // not a copier comment: exact match only
   long got = TmCommentCopyId(actual, actDashed);
   if(got != want)
      return false;
   if(actDashed)
     {
      if(!expDashed)
         return true;              // legacy command, broker appended a suffix
      int ea = StringFind(actual, "-"), ee = StringFind(expected, "-");
      string as = StringSubstr(actual, ea + 1), es = StringSubstr(expected, ee + 1);
      if(TmAllDigits(as) && TmAllDigits(es))
         return StringFind(es, as) == 0;
      return true;
     }
   return !expDashed;              // bare c<id>: legacy command only
  }

//+------------------------------------------------------------------+
//| Evidence time bound. Comment-correlated evidence (positions,     |
//| history deals, orders) counts only when it is not older than the |
//| command: a c<copy_id> on the account from before the command     |
//| belongs to something else (another Copy Server, a reset          |
//| sequence). Ids persisted in our own journal stay authoritative.  |
//| Time bases: DEAL_TIME_MSC / POSITION_TIME_MSC / ORDER_TIME_SETUP_ |
//| MSC are broker server time (the server's wall clock written as   |
//| if it were UTC). Command issued_at is Copy Server UTC ms; the EA |
//| journal created_ms is local UTC ms (TmNowMs). Conversion:        |
//|   local = issued_at - ea_clock_offset (server_time - local)      |
//|   broker = local + (TimeTradeServer - TimeGMT), rounded to 15 min|
//| minus TM_EVIDENCE_SKEW_MS for clock skew.                        |
//+------------------------------------------------------------------+
#define TM_EVIDENCE_SKEW_MS    5000

// broker server time - UTC, ms. Self-test: "now" on the fake clock is mapped onto the tester's broker clock,
// which stays frozen during the run (every tester deal carries the same TimeCurrent).
long TmBrokerOffsetMs(void)
  {
   if(g_tm_fake_now_ms > 0)
      return (long)TimeCurrent() * 1000 - g_tm_fake_now_ms;
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   return (long)MathRound(d / 900.0) * 900 * 1000;
  }

// Oldest broker-time ms a comment match may have for a command issued at `issuedServerMs` (Copy Server
// clock; 0 = unknown, then `createdLocalMs`, the local UTC time the EA journaled it), given the EA clock
// offset (server_time - local).
long TmEvidenceFloor(const long issuedServerMs, const long createdLocalMs, const long clockOffsetMs)
  {
   long local = issuedServerMs > 0 ? issuedServerMs - clockOffsetMs : createdLocalMs;
   if(local <= 0)
      return 0;
   return local + TmBrokerOffsetMs() - TM_EVIDENCE_SKEW_MS;
  }

string TmDealEntry(const long e)
  {
   switch((int)e)
     {
      case DEAL_ENTRY_IN:    return "in";
      case DEAL_ENTRY_OUT:   return "out";
      case DEAL_ENTRY_INOUT: return "inout";
      case DEAL_ENTRY_OUT_BY:return "out_by";
     }
   return "unknown";
  }

string TmDealReason(const long r)
  {
   switch((int)r)
     {
      case DEAL_REASON_CLIENT:   return "client";
      case DEAL_REASON_MOBILE:   return "mobile";
      case DEAL_REASON_WEB:      return "web";
      case DEAL_REASON_EXPERT:   return "expert";
      case DEAL_REASON_SL:       return "sl";
      case DEAL_REASON_TP:       return "tp";
      case DEAL_REASON_SO:       return "so";
      case DEAL_REASON_ROLLOVER: return "rollover";
      case DEAL_REASON_VMARGIN:  return "vmargin";
      case DEAL_REASON_SPLIT:    return "split";
     }
   return "other";
  }

bool TmIsTradeDeal(const ulong deal)
  {
   long t = HistoryDealGetInteger(deal, DEAL_TYPE);
   return t == DEAL_TYPE_BUY || t == DEAL_TYPE_SELL;
  }

bool TmIsHedging(void)
  {
   return AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

//+------------------------------------------------------------------+
//| Positions                                                        |
//+------------------------------------------------------------------+
struct STmPosition
  {
   ulong             ticket;
   ulong             position_id;
   string            symbol;
   long              type;
   double            volume;
   double            price_open;
   double            sl;
   double            tp;
   long              magic;
   string            comment;
   long              time_msc;        // POSITION_TIME_MSC (broker time)
  };

bool TmSelectPositionAt(const int i, STmPosition &p)
  {
   ulong ticket = PositionGetTicket(i);
   if(ticket == 0)
      return false;
   p.ticket = ticket;
   p.position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   p.symbol = PositionGetString(POSITION_SYMBOL);
   p.type = PositionGetInteger(POSITION_TYPE);
   p.volume = PositionGetDouble(POSITION_VOLUME);
   p.price_open = PositionGetDouble(POSITION_PRICE_OPEN);
   p.sl = PositionGetDouble(POSITION_SL);
   p.tp = PositionGetDouble(POSITION_TP);
   p.magic = PositionGetInteger(POSITION_MAGIC);
   p.comment = PositionGetString(POSITION_COMMENT);
   p.time_msc = PositionGetInteger(POSITION_TIME_MSC);
   return true;
  }

// The current ticket for a stable POSITION_IDENTIFIER (tickets may change, 4.4).
bool TmFindPositionById(const ulong positionId, STmPosition &p)
  {
   if(positionId == 0)
      return false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(TmSelectPositionAt(i, p) && p.position_id == positionId)
         return true;
   return false;
  }

// Netting physical slot (4.4): any position on the symbol that this copy does not own.
// A position with our comment + magic opened before `floorMs` (broker time) is someone else's.
bool TmUnmanagedPositionOnSymbol(const string symbol, const string ownComment, const long ownMagic, const long floorMs)
  {
   STmPosition p;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(TmSelectPositionAt(i, p) && p.symbol == symbol &&
         !(TmCommentMatches(ownComment, p.comment) && p.magic == ownMagic && p.time_msc >= floorMs))
         return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Evidence (4.6 step 2 / step 6)                                   |
//+------------------------------------------------------------------+
struct STmEvidence
  {
   bool              found;
   ulong             order;
   ulong             deal;
   ulong             position_id;
   ulong             position_ticket;
   double            volume;          // entry volume (open) / exit volume (close)
   double            price;
   double            profit;
   double            commission;
   double            swap;
   long              time_msc;
   bool              position_alive;
   double            position_volume;
  };

void TmEvidenceReset(STmEvidence &e)
  {
   e.found = false; e.order = 0; e.deal = 0; e.position_id = 0; e.position_ticket = 0; e.volume = 0; e.price = 0;
   e.profit = 0; e.commission = 0; e.swap = 0; e.time_msc = 0; e.position_alive = false; e.position_volume = 0;
  }

void TmFillAlive(STmEvidence &e)
  {
   STmPosition p;
   if(TmFindPositionById(e.position_id, p))
     {
      e.position_alive = true;
      e.position_ticket = p.ticket;
      e.position_volume = p.volume;
     }
  }

// Entry evidence of an open: persisted ids first (order, deal), then the c<copy_id> part of the comment + magic
// over live positions, live orders and history deals, each no older than `floorMs` (broker time,
// TmEvidenceFloor). Persisted ids are ours whatever their time.
bool TmFindOpenEvidence(const string comment, const long magic, const ulong knownOrder, const ulong knownDeal,
                        const long floorMs, STmEvidence &e)
  {
   TmEvidenceReset(e);
   if(g_tm_hide_evidence)
      return false;
   datetime from = (datetime)(MathMax(floorMs / 1000 - 86400, (long)TimeCurrent() - TM_EVIDENCE_DAYS * 86400));
   if(!HistorySelect(from, TimeCurrent() + 86400))
      return false;
   // 1. by persisted deal
   if(knownDeal != 0 && HistoryDealSelect(knownDeal))
     {
      e.found = true;
      e.deal = knownDeal;
      e.order = (ulong)HistoryDealGetInteger(knownDeal, DEAL_ORDER);
      e.position_id = (ulong)HistoryDealGetInteger(knownDeal, DEAL_POSITION_ID);
      e.volume = HistoryDealGetDouble(knownDeal, DEAL_VOLUME);
      e.price = HistoryDealGetDouble(knownDeal, DEAL_PRICE);
      e.time_msc = HistoryDealGetInteger(knownDeal, DEAL_TIME_MSC);
      TmFillAlive(e);
      return true;
     }
   // 2. by persisted order: its deals
   if(knownOrder != 0)
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_ORDER) != knownOrder)
            continue;
         e.found = true;
         e.deal = d;
         e.order = knownOrder;
         e.position_id = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
         e.volume = HistoryDealGetDouble(d, DEAL_VOLUME);
         e.price = HistoryDealGetDouble(d, DEAL_PRICE);
         e.time_msc = HistoryDealGetInteger(d, DEAL_TIME_MSC);
         TmFillAlive(e);
         return true;
        }
     }
   // 3. live position with the correlation comment
   STmPosition p;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(TmSelectPositionAt(i, p) && TmCommentMatches(comment, p.comment) && p.magic == magic && p.time_msc >= floorMs)
        {
         e.found = true;
         e.position_id = p.position_id;
         e.position_ticket = p.ticket;
         e.position_alive = true;
         e.position_volume = p.volume;
         e.volume = p.volume;
         e.price = p.price_open;
         // the entry deal, when history has it
         if(HistorySelectByPosition(p.position_id))
            for(int k = 0; k < HistoryDealsTotal(); k++)
              {
               ulong d = HistoryDealGetTicket(k);
               if(d != 0 && HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
                 {
                  e.deal = d;
                  e.order = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
                  e.time_msc = HistoryDealGetInteger(d, DEAL_TIME_MSC);
                  break;
                 }
              }
         return true;
        }
   // 4. history entry deal with the comment (position may already be closed: S40)
   HistorySelect(from, TimeCurrent() + 86400);
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || !TmIsTradeDeal(d))
         continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;
      if(!TmCommentMatches(comment, HistoryDealGetString(d, DEAL_COMMENT)) || HistoryDealGetInteger(d, DEAL_MAGIC) != magic)
         continue;
      if(HistoryDealGetInteger(d, DEAL_TIME_MSC) < floorMs)
         continue;   // older than the command: not this copy's
      e.found = true;
      e.deal = d;
      e.order = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
      e.position_id = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      e.volume = HistoryDealGetDouble(d, DEAL_VOLUME);
      e.price = HistoryDealGetDouble(d, DEAL_PRICE);
      e.time_msc = HistoryDealGetInteger(d, DEAL_TIME_MSC);
      TmFillAlive(e);
      return true;
     }
   // 5. a live (not yet filled) order with the comment: execution in flight, not conclusive
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong o = OrderGetTicket(i);
      if(o != 0 && TmCommentMatches(comment, OrderGetString(ORDER_COMMENT)) && OrderGetInteger(ORDER_MAGIC) == magic &&
         OrderGetInteger(ORDER_TIME_SETUP_MSC) >= floorMs)
        {
         e.order = o;
         return false;
        }
     }
   return false;
  }

// Exit evidence for a position id: every out/out_by deal (sums volume, profit, fees).
// `afterMs` > 0 restricts to deals at or after that time (only this attempt's effect).
bool TmFindExitDeals(const ulong positionId, const long afterMs, STmEvidence &e)
  {
   TmEvidenceReset(e);
   if(g_tm_hide_evidence || positionId == 0)
      return false;
   e.position_id = positionId;
   if(!HistorySelectByPosition((long)positionId))
      return false;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      long entry = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      long t = HistoryDealGetInteger(d, DEAL_TIME_MSC);
      if(afterMs > 0 && t < afterMs)
         continue;
      e.found = true;
      e.deal = d;                   // last exit deal
      e.order = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
      e.volume += HistoryDealGetDouble(d, DEAL_VOLUME);
      e.price = HistoryDealGetDouble(d, DEAL_PRICE);
      e.profit += HistoryDealGetDouble(d, DEAL_PROFIT);
      e.commission += HistoryDealGetDouble(d, DEAL_COMMISSION);
      e.swap += HistoryDealGetDouble(d, DEAL_SWAP);
      e.time_msc = t;
     }
   TmFillAlive(e);
   return e.found;
  }

// Deals of one order (close/close_partial by persisted order id).
bool TmFindDealsOfOrder(const ulong order, STmEvidence &e)
  {
   TmEvidenceReset(e);
   if(g_tm_hide_evidence || order == 0)
      return false;
   if(!HistorySelect(TimeCurrent() - TM_EVIDENCE_DAYS * 86400, TimeCurrent() + 86400))
      return false;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_ORDER) != order)
         continue;
      e.found = true;
      e.deal = d;
      e.order = order;
      e.position_id = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      e.volume += HistoryDealGetDouble(d, DEAL_VOLUME);
      e.price = HistoryDealGetDouble(d, DEAL_PRICE);
      e.profit += HistoryDealGetDouble(d, DEAL_PROFIT);
      e.commission += HistoryDealGetDouble(d, DEAL_COMMISSION);
      e.swap += HistoryDealGetDouble(d, DEAL_SWAP);
      e.time_msc = HistoryDealGetInteger(d, DEAL_TIME_MSC);
     }
   if(e.found)
      TmFillAlive(e);
   return e.found;
  }

//+------------------------------------------------------------------+
//| Snapshot body (4.3)                                              |
//+------------------------------------------------------------------+
void TmWritePositions(CJsonWriter &w)
  {
   w.BeginArr("positions");
   STmPosition p;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(!TmSelectPositionAt(i, p))
         continue;
      int digits = (int)SymbolInfoInteger(p.symbol, SYMBOL_DIGITS);
      w.BeginObj();
      w.Int("position_ticket", (long)p.ticket);
      w.Int("position_id", (long)p.position_id);
      w.Str("symbol", p.symbol);
      w.Str("type", TmSide(p.type));
      w.Num("volume", p.volume);
      w.Num("price_open", p.price_open, digits);
      w.NumOrNull("sl", p.sl, digits);
      w.NumOrNull("tp", p.tp, digits);
      w.Int("magic", p.magic);
      w.Str("comment", p.comment);
      w.Int("time_msc", PositionGetInteger(POSITION_TIME_MSC));
      w.EndObj();
     }
   w.EndArr();
  }

void TmWritePending(CJsonWriter &w)
  {
   // Reported only; ignored for fan-out in Phase 1 (5.3a).
   w.BeginArr("pending");
   for(int i = 0; i < OrdersTotal(); i++)
     {
      ulong o = OrderGetTicket(i);
      if(o == 0)
         continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      w.BeginObj();
      w.Int("order", (long)o);
      w.Str("symbol", sym);
      w.Int("type", OrderGetInteger(ORDER_TYPE));
      w.Num("volume", OrderGetDouble(ORDER_VOLUME_CURRENT));
      w.Num("price", OrderGetDouble(ORDER_PRICE_OPEN), digits);
      w.Int("magic", OrderGetInteger(ORDER_MAGIC));
      w.Str("comment", OrderGetString(ORDER_COMMENT));
      w.EndObj();
     }
   w.EndArr();
  }

// history[]: trade deals since `sinceMs` (the last accepted snapshot), at least the last 30;
// `full` (config send_history) sends up to `maxDeals` of the evidence window.
bool TmWriteHistory(CJsonWriter &w, const long sinceMs, const bool full, const int maxDeals)
  {
   bool synced = HistorySelect(TimeCurrent() - TM_EVIDENCE_DAYS * 86400, TimeCurrent() + 86400);
   w.BeginArr("history");
   if(synced)
     {
      int total = HistoryDealsTotal();
      int written = 0;
      // newest first; the server does not depend on order
      for(int i = total - 1; i >= 0 && written < maxDeals; i--)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || !TmIsTradeDeal(d))
            continue;
         long t = HistoryDealGetInteger(d, DEAL_TIME_MSC);
         if(!full && written >= TM_HISTORY_MIN_DEALS && t < sinceMs)
            break;
         string sym = HistoryDealGetString(d, DEAL_SYMBOL);
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         w.BeginObj();
         w.Int("deal", (long)d);
         w.Int("order", HistoryDealGetInteger(d, DEAL_ORDER));
         w.Int("position_id", HistoryDealGetInteger(d, DEAL_POSITION_ID));
         w.Str("entry", TmDealEntry(HistoryDealGetInteger(d, DEAL_ENTRY)));
         w.Str("reason", TmDealReason(HistoryDealGetInteger(d, DEAL_REASON)));
         w.Str("symbol", sym);
         w.Num("volume", HistoryDealGetDouble(d, DEAL_VOLUME));
         w.Num("price", HistoryDealGetDouble(d, DEAL_PRICE), digits > 0 ? digits : 8);
         w.Num("profit", HistoryDealGetDouble(d, DEAL_PROFIT), 2);
         w.Num("commission", HistoryDealGetDouble(d, DEAL_COMMISSION), 2);
         w.Num("swap", HistoryDealGetDouble(d, DEAL_SWAP), 2);
         w.Int("magic", HistoryDealGetInteger(d, DEAL_MAGIC));
         w.Str("comment", HistoryDealGetString(d, DEAL_COMMENT));
         w.Int("time_msc", t);
         w.EndObj();
         written++;
        }
     }
   w.EndArr();
   return synced;
  }

// Full snapshot body; returns history_synced via the out parameter.
string TmBuildSnapshot(const string sessionId, const long epoch, const long seq, const long clockOffsetMs,
                       const long historySinceMs, const bool fullHistory, bool &historySynced)
  {
   CJsonWriter w;
   w.BeginObj();
   w.Str("session_id", sessionId);
   w.Int("epoch", epoch);
   w.Int("seq", seq);
   w.Int("taken_at", TmNowMs());
   w.Int("ea_clock_offset_ms", clockOffsetMs);
   w.Int("broker_offset_ms", TmBrokerOffsetMs());   // deal/position time_msc - this = local UTC ms
   w.Bool("connected", TerminalInfoInteger(TERMINAL_CONNECTED) != 0);
   w.Int("login", AccountInfoInteger(ACCOUNT_LOGIN));
   w.Str("server", AccountInfoString(ACCOUNT_SERVER));
   // history first so history_synced reflects this snapshot's HistorySelect
   CJsonWriter h;
   h.BeginObj();
   historySynced = TmWriteHistory(h, historySinceMs, fullHistory, fullHistory ? 1000 : 500);
   h.EndObj();
   w.Bool("history_synced", historySynced);
   TmWritePositions(w);
   TmWritePending(w);
   string hist = h.Text();               // {"history":[...]}
   w.Raw("history", StringSubstr(hist, 11, StringLen(hist) - 12));
   w.EndObj();
   return w.Text();
  }

//+------------------------------------------------------------------+
//| Symbol specs (PUT /v4/symbols)                                   |
//+------------------------------------------------------------------+
string TmTradeMode(const long m)
  {
   switch((int)m)
     {
      case SYMBOL_TRADE_MODE_DISABLED:  return "disabled";
      case SYMBOL_TRADE_MODE_LONGONLY:  return "longonly";
      case SYMBOL_TRADE_MODE_SHORTONLY: return "shortonly";
      case SYMBOL_TRADE_MODE_CLOSEONLY: return "closeonly";
      case SYMBOL_TRADE_MODE_FULL:      return "full";
     }
   return "unknown";
  }

void TmWriteFillingModes(CJsonWriter &w, const string symbol)
  {
   long f = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   w.BeginArr("filling_modes");
   if((f & SYMBOL_FILLING_FOK) != 0) w.Str("", "fok");
   if((f & SYMBOL_FILLING_IOC) != 0) w.Str("", "ioc");
   if(SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE) != SYMBOL_TRADE_EXECUTION_MARKET) w.Str("", "return");
   w.EndArr();
  }

void TmWriteSymbolSpec(CJsonWriter &w, const string s)
  {
   w.BeginObj();
   w.Str("name", s);
   w.Num("volume_min", SymbolInfoDouble(s, SYMBOL_VOLUME_MIN));
   w.Num("volume_step", SymbolInfoDouble(s, SYMBOL_VOLUME_STEP));
   w.Num("volume_max", SymbolInfoDouble(s, SYMBOL_VOLUME_MAX));
   w.Num("contract_size", SymbolInfoDouble(s, SYMBOL_TRADE_CONTRACT_SIZE));
   w.Int("digits", SymbolInfoInteger(s, SYMBOL_DIGITS));
   w.Num("point", SymbolInfoDouble(s, SYMBOL_POINT), 10);
   w.Num("tick_size", SymbolInfoDouble(s, SYMBOL_TRADE_TICK_SIZE), 10);
   w.Str("trade_mode", TmTradeMode(SymbolInfoInteger(s, SYMBOL_TRADE_MODE)));
   TmWriteFillingModes(w, s);
   w.Int("stops_level", SymbolInfoInteger(s, SYMBOL_TRADE_STOPS_LEVEL));
   w.Int("freeze_level", SymbolInfoInteger(s, SYMBOL_TRADE_FREEZE_LEVEL));
   w.EndObj();
  }

// Market Watch symbols plus the ones the server asked for (`symbols_wanted`).
string TmBuildSymbols(const string &wanted[])
  {
   for(int i = 0; i < ArraySize(wanted); i++)
      SymbolSelect(wanted[i], true);
   CJsonWriter w;
   w.BeginObj();
   w.BeginArr("symbols");
   int n = SymbolsTotal(true);
   for(int i = 0; i < n && i < 5000; i++)
      TmWriteSymbolSpec(w, SymbolName(i, true));
   w.EndArr();
   w.EndObj();
   return w.Text();
  }

ENUM_ORDER_TYPE_FILLING TmFilling(const string symbol)
  {
   long f = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

#endif
