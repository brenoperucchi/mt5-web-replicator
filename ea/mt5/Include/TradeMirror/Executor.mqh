//+------------------------------------------------------------------+
//| TradeMirror - slave command executor (design 4.4 - 4.6)          |
//|                                                                  |
//| - Commands are executed per copy in seq_in_copy order; copies    |
//|   are independent. close/close_partial/cancel/resolve run before |
//|   open/modify, and never wait on HTTP.                           |
//| - Before every send: journal lookup, then per-action evidence.   |
//| - prepared (flushed) -> sent (flushed) -> OrderSend -> ids are    |
//|   persisted as soon as known -> confirmed | uncertain.           |
//| - No evidence never proves non-execution: a sent attempt without |
//|   conclusive evidence becomes `suspended` for that copy only and |
//|   reports `uncertain`. Only a `resolve` command or later broker  |
//|   evidence settles it.                                           |
//+------------------------------------------------------------------+
#ifndef TRADEMIRROR_EXECUTOR_MQH
#define TRADEMIRROR_EXECUTOR_MQH

#include "Json.mqh"
#include "Util.mqh"
#include "Journal.mqh"
#include "Outbox.mqh"
#include "Broker.mqh"

#define TM_DEFAULT_DEVIATION     30
#define TM_UNCERTAIN_WINDOW_MS   20000   // keep re-checking a sent attempt this long before suspending
#define TM_UNCERTAIN_MIN_CHECKS  3
#define TM_VOL_EPS               0.0000001

// Test seam: simulate a process crash at a precise point of the journal protocol (self-test EA).
enum ENUM_TM_CRASH
  {
   TM_CRASH_NONE = 0,
   TM_CRASH_AFTER_PREPARED,      // journal `prepared`, OrderSend never called (S02)
   TM_CRASH_AFTER_SENT,          // journal `sent`, OrderSend never called
   TM_CRASH_AFTER_ORDERSEND      // OrderSend executed, ids never persisted (S03)
  };

string TmRetcodeName(const uint rc)
  {
   switch(rc)
     {
      case TRADE_RETCODE_REQUOTE:            return "requote";
      case TRADE_RETCODE_REJECT:             return "rejected";
      case TRADE_RETCODE_CANCEL:             return "cancelled_by_trader";
      case TRADE_RETCODE_PLACED:             return "placed";
      case TRADE_RETCODE_DONE:               return "done";
      case TRADE_RETCODE_DONE_PARTIAL:       return "done_partial";
      case TRADE_RETCODE_ERROR:              return "request_error";
      case TRADE_RETCODE_TIMEOUT:            return "timeout";
      case TRADE_RETCODE_INVALID:            return "invalid_request";
      case TRADE_RETCODE_INVALID_VOLUME:     return "invalid_volume";
      case TRADE_RETCODE_INVALID_PRICE:      return "invalid_price";
      case TRADE_RETCODE_INVALID_STOPS:      return "invalid_stops";
      case TRADE_RETCODE_TRADE_DISABLED:     return "trade_disabled";
      case TRADE_RETCODE_MARKET_CLOSED:      return "market_closed";
      case TRADE_RETCODE_NO_MONEY:           return "no_money";
      case TRADE_RETCODE_PRICE_CHANGED:      return "price_changed";
      case TRADE_RETCODE_PRICE_OFF:          return "price_off";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "invalid_expiration";
      case TRADE_RETCODE_ORDER_CHANGED:      return "order_changed";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:  return "too_many_requests";
      case TRADE_RETCODE_NO_CHANGES:         return "no_changes";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "server_disables_at";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "client_disables_at";
      case TRADE_RETCODE_LOCKED:             return "locked";
      case TRADE_RETCODE_FROZEN:             return "frozen";
      case TRADE_RETCODE_INVALID_FILL:       return "invalid_fill";
      case TRADE_RETCODE_CONNECTION:         return "no_connection";
      case TRADE_RETCODE_ONLY_REAL:          return "only_real";
      case TRADE_RETCODE_LIMIT_ORDERS:       return "limit_orders";
      case TRADE_RETCODE_LIMIT_VOLUME:       return "limit_volume";
      case TRADE_RETCODE_INVALID_ORDER:      return "invalid_order";
      case TRADE_RETCODE_POSITION_CLOSED:    return "position_closed";
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME: return "invalid_close_volume";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:  return "close_order_exist";
      case TRADE_RETCODE_LIMIT_POSITIONS:    return "limit_positions";
      case TRADE_RETCODE_REJECT_CANCEL:      return "reject_cancel";
      case TRADE_RETCODE_LONG_ONLY:          return "long_only";
      case TRADE_RETCODE_SHORT_ONLY:         return "short_only";
      case TRADE_RETCODE_CLOSE_ONLY:         return "close_only";
      case TRADE_RETCODE_FIFO_CLOSE:         return "fifo_close";
      case TRADE_RETCODE_HEDGE_PROHIBITED:   return "hedge_prohibited";
     }
   return "retcode_" + IntegerToString(rc);
  }

// The broker answered and the request had no effect (4.6 step 5).
bool TmDefinitiveReject(const uint rc)
  {
   if(rc == 0)
      return false;
   if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED)
      return false;
   if(rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_ERROR)
      return false;   // no conclusive answer: uncertain
   return true;
  }

//+------------------------------------------------------------------+
//| A received command (in memory; the server re-delivers un-acked   |
//| commands, so the queue itself needs no persistence)               |
//+------------------------------------------------------------------+
class CTmCommand
  {
public:
   string            id;
   string            attempt;
   string            action;
   long              copy_id;
   long              seq;
   string            raw;
   CJson            *j;
   bool              finished;

                     CTmCommand(void) { j = NULL; finished = false; copy_id = 0; seq = 0; }
                    ~CTmCommand(void) { if(CheckPointer(j) == POINTER_DYNAMIC) delete j; }
   bool              IsClosing(void) const { return action == "close" || action == "close_partial" || action == "cancel" || action == "resolve"; }
  };

class CExecutor
  {
public:
   ENUM_TM_CRASH     m_crash;      // test seam (self-test EA only)
   bool              m_crashed;

private:
   CJournal         *m_journal;
   COutbox          *m_outbox;
   CTmCommand       *m_queue[];
   bool              m_drain;
   long              m_clockOffsetMs;
   bool              m_hedging;
   bool              m_executedSomething;
   int               m_suspendedTicks;

   //--- results ----------------------------------------------------------------------------
   string            ResultJson(CJournalEntry *e, const string status, const STmEvidence &ev, const string errorCode,
                                const string message, const double executedVolume, const double residualVolume,
                                const string symbol)
     {
      CJsonWriter w;
      w.BeginObj();
      w.Str("command_id", e.command_id);
      w.Str("attempt_id", e.attempt_id);
      w.Int("copy_id", e.copy_id);
      w.Str("status", status);
      if(ev.order != 0)           w.Int("order", (long)ev.order);
      if(ev.deal != 0)            w.Int("deal", (long)ev.deal);
      if(e.request_id != 0)       w.Int("request_id", (long)e.request_id);
      if(ev.position_ticket != 0) w.Int("position_ticket", (long)ev.position_ticket);
      if(ev.position_id != 0)     w.Int("position_id", (long)ev.position_id);
      if(symbol != "")            w.Str("symbol", symbol);
      if(ev.volume > 0)           w.Num("volume", ev.volume);
      if(executedVolume > 0)      w.Num("executed_volume", executedVolume);
      if(residualVolume >= 0)     w.Num("residual_volume", residualVolume);
      if(ev.price > 0)            w.Num("price", ev.price);
      if(ev.found && (ev.profit != 0 || ev.commission != 0 || ev.swap != 0))
        {
         w.Num("profit", ev.profit, 2);
         w.Num("commission", ev.commission, 2);
         w.Num("swap", ev.swap, 2);
        }
      w.Int("executed_at", ev.time_msc > 0 ? ev.time_msc : TmNowMs());
      if(errorCode != "")         w.Str("error_code", errorCode);
      if(message != "")           w.Str("message", StringSubstr(message, 0, 500));
      w.EndObj();
      return w.Text();
     }

   //--- settle an attempt: journal `confirmed` (flushed) then the result goes to the outbox
   void              Confirm(CJournalEntry *e, const string status, const STmEvidence &ev, const string errorCode,
                             const string message, const double executedVolume = 0, const double residualVolume = -1,
                             const string symbol = "")
     {
      if(ev.order != 0)       e.order = ev.order;
      if(ev.deal != 0)        e.deal = ev.deal;
      if(ev.position_id != 0) e.position_id = ev.position_id;
      if(executedVolume > 0)  e.executed_volume = executedVolume;
      if(residualVolume >= 0) e.residual_volume = residualVolume;
      e.state = JS_CONFIRMED;
      e.result = ResultJson(e, status, ev, errorCode, message, executedVolume, residualVolume, symbol);
      m_journal.Save(e);
      m_outbox.Enqueue(e.result, e.command_id);
      m_executedSomething = true;
      TmLog.Info(StringFormat("copy %I64d %s %s -> %s %s", e.copy_id, e.action, e.command_id, status, errorCode));
     }

   void              ConfirmSimple(CJournalEntry *e, const string status, const string errorCode, const string message)
     {
      STmEvidence ev;
      TmEvidenceReset(ev);
      Confirm(e, status, ev, errorCode, message);
     }

   void              Suspend(CJournalEntry *e, const string why)
     {
      e.state = JS_SUSPENDED;
      STmEvidence ev;
      TmEvidenceReset(ev);
      ev.order = e.order;
      ev.deal = e.deal;
      ev.position_id = e.position_id;
      e.result = ResultJson(e, "uncertain", ev, "no_evidence", why, 0, -1, "");
      m_journal.Save(e);
      m_outbox.Enqueue(e.result, e.command_id);
      TmLog.Alarm(StringFormat("copy %I64d suspended (%s %s): %s. Resolve it in the admin (copies -> resolve).",
                               e.copy_id, e.action, e.command_id, why));
     }

   void              InProgress(CJournalEntry *e)
     {
      CJsonWriter w;
      w.BeginObj();
      w.Str("command_id", e.command_id);
      w.Str("attempt_id", e.attempt_id);
      w.Int("copy_id", e.copy_id);
      w.Str("status", "in_progress");
      w.EndObj();
      m_outbox.Enqueue(w.Text(), e.command_id);
     }

   //--- trade request plumbing ------------------------------------------------------------------
   bool              MarketPrice(const string symbol, const bool buy, double &price)
     {
      MqlTick t;
      if(!SymbolInfoTick(symbol, t))
         return false;
      price = buy ? t.ask : t.bid;
      return price > 0;
     }

   void              BaseDeal(MqlTradeRequest &r, const string symbol, const bool buy, const double volume, const double price,
                              const long deviation, const long magic, const string comment)
     {
      ZeroMemory(r);
      r.action = TRADE_ACTION_DEAL;
      r.symbol = symbol;
      r.volume = volume;
      r.type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      r.price = price;
      r.deviation = (ulong)(deviation > 0 ? deviation : TM_DEFAULT_DEVIATION);
      r.magic = (ulong)magic;
      r.comment = comment;
      r.type_filling = TmFilling(symbol);
     }

   // prepared -> sent -> OrderSend. Returns false when the crash seam fired.
   bool              Send(CJournalEntry *e, MqlTradeRequest &req, MqlTradeResult &res)
     {
      e.state = JS_PREPARED;
      m_journal.Save(e);
      if(m_crash == TM_CRASH_AFTER_PREPARED) { m_crash = TM_CRASH_NONE; m_crashed = true; return false; }
      e.state = JS_SENT;
      e.sent_ms = TmNowMs();
      m_journal.Save(e);
      InProgress(e);   // receipt ack: the server leases the command (4.5)
      if(m_crash == TM_CRASH_AFTER_SENT) { m_crash = TM_CRASH_NONE; m_crashed = true; return false; }
      ZeroMemory(res);
      ResetLastError();
      bool ok = OrderSend(req, res);
      if(m_crash == TM_CRASH_AFTER_ORDERSEND) { m_crash = TM_CRASH_NONE; m_crashed = true; return false; }
      if(!ok && res.retcode == 0)
         res.comment = res.comment + " err=" + IntegerToString(GetLastError());
      e.order = res.order;
      e.deal = res.deal;
      e.request_id = res.request_id;
      m_journal.Save(e);   // ids persisted as soon as known (4.6 step 3)
      m_executedSomething = true;
      return true;
     }

   bool              RequestLeftTerminal(const MqlTradeResult &res) { return res.retcode != 0 || res.request_id != 0; }

   //--- helpers on the command payload ---------------------------------------------------------
   long              Magic(CJson *j) { return j.Long("magic", 0); }
   string            Comment(CJson *j, const long copyId) { return j.Str("comment", "c" + IntegerToString(copyId)); }

   //--- actions -----------------------------------------------------------------------------
   void              DoOpen(CTmCommand *c, CJournalEntry *e)
     {
      CJson *j = c.j;
      string symbol = j.Str("symbol");
      bool buy = j.Str("side") == "buy";
      long magic = Magic(j);
      string comment = Comment(j, c.copy_id);
      STmEvidence ev;

      if(m_drain)
        { ConfirmSimple(e, "failed", "drain", "account in drain mode: no new opens"); return; }
      long expires = j.Long("expires_at", 0);
      if(expires > 0 && TmNowMs() + m_clockOffsetMs > expires)
        { ConfirmSimple(e, "expired", "expired", "open received after expires_at"); return; }

      // pre-send evidence (4.6 step 2): comment c<copy_id> + magic, persisted ids first
      if(TmFindOpenEvidence(comment, magic, e.order, e.deal, j.Long("issued_at", e.created_ms), ev) && ev.position_id != 0)
        {
         Confirm(e, "done", ev, "", "found by evidence check; nothing sent", ev.volume, -1, symbol);
         return;
        }
      if(ev.order != 0)
        {
         // a live order with our comment: execution in flight -> treat as sent, re-check later
         e.order = ev.order;
         e.state = JS_UNCERTAIN;
         e.sent_ms = TmNowMs();
         m_journal.Save(e);
         return;
        }
      if(!SymbolSelect(symbol, true) || !SymbolInfoInteger(symbol, SYMBOL_EXIST))
        { ConfirmSimple(e, "failed", "symbol_not_found", "symbol " + symbol + " not found on this account"); return; }
      if(!m_hedging && TmUnmanagedPositionOnSymbol(symbol, comment, magic))
        {
         TmLog.Alarm("netting slot on " + symbol + " is held by a position not managed by the copier: open refused");
         ConfirmSimple(e, "failed", "unmanaged_position_on_symbol", "position on " + symbol + " not managed by the copier");
         return;
        }
      double price;
      if(!MarketPrice(symbol, buy, price))
        { ConfirmSimple(e, "failed", "no_quote", "no current price for " + symbol); return; }
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double masterPrice = j.Dbl("master_price", 0);
      CJson *guard = j.Get("max_entry_deviation_points");
      if(guard != NULL && guard.type == JSON_NUMBER && masterPrice > 0 && point > 0)
        {
         double dist = MathAbs(price - masterPrice) / point;
         if(dist > StringToDouble(guard.text))
           {
            ConfirmSimple(e, "failed", "price_out_of_range",
                          StringFormat("price %.5f is %.0f points from master %.5f", price, dist, masterPrice));
            return;
           }
        }
      MqlTradeRequest req;
      MqlTradeResult res;
      BaseDeal(req, symbol, buy, j.Dbl("volume"), price, j.Long("max_slippage_points", TM_DEFAULT_DEVIATION), magic, comment);
      if(!Send(e, req, res))
         return;
      if(TmDefinitiveReject(res.retcode) || !RequestLeftTerminal(res))
        {
         ConfirmSimple(e, "failed", res.retcode == 0 ? "local_check_failed" : TmRetcodeName(res.retcode), res.comment);
         return;
        }
      if(!SettleOpen(e, c.j))
        {
         e.state = JS_UNCERTAIN;   // ids known but the deal is not visible yet
         m_journal.Save(e);
        }
     }

   // conclusive open evidence -> confirmed done (+ SL/TP). Returns false when not conclusive yet.
   bool              SettleOpen(CJournalEntry *e, CJson *j)
     {
      STmEvidence ev;
      string comment = Comment(j, e.copy_id);
      if(!TmFindOpenEvidence(comment, Magic(j), e.order, e.deal, e.created_ms, ev) || ev.position_id == 0)
         return false;
      Confirm(e, "done", ev, "", "", ev.volume, -1, j.Str("symbol"));
      ApplyStops(ev.position_id, j.Dbl("sl", 0), j.Dbl("tp", 0));
      return true;
     }

   void              ApplyStops(const ulong positionId, const double sl, const double tp)
     {
      if(sl == 0 && tp == 0)
         return;
      STmPosition p;
      if(!TmFindPositionById(positionId, p))
         return;
      MqlTradeRequest r;
      MqlTradeResult res;
      ZeroMemory(r);
      ZeroMemory(res);
      r.action = TRADE_ACTION_SLTP;
      r.position = p.ticket;
      r.symbol = p.symbol;
      r.sl = sl;
      r.tp = tp;
      r.magic = (ulong)p.magic;
      if(!OrderSend(r, res) || res.retcode != TRADE_RETCODE_DONE)
         TmLog.Warn(StringFormat("SL/TP on position %I64u not applied: %s", positionId, TmRetcodeName(res.retcode)));
     }

   // close the whole position; `status` is "done" (close) or "closed" (cancel of an executed open)
   void              DoClose(CTmCommand *c, CJournalEntry *e, const ulong positionId, const string status)
     {
      CJson *j = c.j;
      STmPosition p;
      STmEvidence ev;
      if(!TmFindPositionById(positionId, p))
        {
         if(TmFindExitDeals(positionId, 0, ev))
            Confirm(e, status, ev, "", "position already closed", ev.volume, 0, j.Str("symbol"));
         else
            ConfirmSimple(e, "failed", "position_not_found", "no position and no exit deal for " + IntegerToString((long)positionId));
         return;
        }
      e.position_id = positionId;
      double price;
      bool closeBuy = p.type == POSITION_TYPE_SELL;   // opposite side
      if(!MarketPrice(p.symbol, closeBuy, price))
        { ConfirmSimple(e, "failed", "no_quote", "no current price for " + p.symbol); return; }
      MqlTradeRequest req;
      MqlTradeResult res;
      BaseDeal(req, p.symbol, closeBuy, p.volume, price, j.Long("max_slippage_points", TM_DEFAULT_DEVIATION),
               p.magic, Comment(j, c.copy_id));
      req.position = p.ticket;
      if(!Send(e, req, res))
         return;
      if(TmDefinitiveReject(res.retcode) || !RequestLeftTerminal(res))
        {
         ConfirmSimple(e, "failed", res.retcode == 0 ? "local_check_failed" : TmRetcodeName(res.retcode), res.comment);
         return;
        }
      if(!SettleClose(e, status, j.Str("symbol")))
        {
         e.state = JS_UNCERTAIN;
         m_journal.Save(e);
        }
     }

   // close evidence: position gone + exit deal(s) of this attempt, or partial execution of the order
   bool              SettleClose(CJournalEntry *e, const string status, const string symbol)
     {
      STmEvidence ev;
      STmPosition p;
      bool alive = TmFindPositionById(e.position_id, p);
      if(!alive && !g_tm_hide_evidence)
        {
         if(TmFindExitDeals(e.position_id, e.sent_ms > 0 ? e.sent_ms - 5000 : 0, ev) ||
            TmFindExitDeals(e.position_id, 0, ev))
           {
            Confirm(e, status, ev, "", "", ev.volume, 0, symbol);
            return true;
           }
         return false;   // gone but no exit deal visible yet: not conclusive
        }
      if(alive && e.order != 0 && TmFindDealsOfOrder(e.order, ev))
        {
         // DONE_PARTIAL: the server keeps the copy closing and issues the rest as a new attempt
         Confirm(e, "done_partial", ev, "", "partial close", ev.volume, p.volume, symbol);
         return true;
        }
      return false;
     }

   void              DoClosePartial(CTmCommand *c, CJournalEntry *e)
     {
      CJson *j = c.j;
      ulong positionId = (ulong)j.Long("position_id");
      double target = j.Dbl("residual_volume", -1);
      STmPosition p;
      STmEvidence ev;
      if(!TmFindPositionById(positionId, p))
        {
         if(TmFindExitDeals(positionId, 0, ev))
            Confirm(e, "done", ev, "", "position already closed", 0, 0, j.Str("symbol"));
         else
            ConfirmSimple(e, "failed", "position_not_found", "no position " + IntegerToString((long)positionId));
         return;
        }
      e.position_id = positionId;
      if(target < 0)
         target = MathMax(p.volume - j.Dbl("volume"), 0);
      e.residual_volume = target;
      // already at or below the persisted target: done with the observed volume (4.6 step 2)
      if(p.volume <= target + TM_VOL_EPS)
        {
         ev.position_id = positionId;
         ev.position_ticket = p.ticket;
         Confirm(e, "done", ev, "", "position already at target volume", 0, p.volume, p.symbol);
         return;
        }
      string side = j.Str("side");
      if(!m_hedging && side != "" && side != TmSide(p.type))
        { ConfirmSimple(e, "failed", "side_mismatch", "netting position side differs from the copy side"); return; }
      double step = SymbolInfoDouble(p.symbol, SYMBOL_VOLUME_STEP);
      double delta = p.volume - target;
      if(step > 0)
         delta = MathFloor(delta / step + 0.0000001) * step;
      delta = MathMin(NormalizeDouble(delta, 8), p.volume);   // never flips the side
      if(delta <= TM_VOL_EPS)
        {
         ev.position_id = positionId;
         Confirm(e, "done", ev, "", "delta below volume step", 0, p.volume, p.symbol);
         return;
        }
      double price;
      bool closeBuy = p.type == POSITION_TYPE_SELL;
      if(!MarketPrice(p.symbol, closeBuy, price))
        { ConfirmSimple(e, "failed", "no_quote", "no current price for " + p.symbol); return; }
      MqlTradeRequest req;
      MqlTradeResult res;
      BaseDeal(req, p.symbol, closeBuy, delta, price, j.Long("max_slippage_points", TM_DEFAULT_DEVIATION),
               p.magic, Comment(j, c.copy_id));
      req.position = p.ticket;
      if(!Send(e, req, res))
         return;
      if(TmDefinitiveReject(res.retcode) || !RequestLeftTerminal(res))
        {
         ConfirmSimple(e, "failed", res.retcode == 0 ? "local_check_failed" : TmRetcodeName(res.retcode), res.comment);
         return;
        }
      e.executed_volume = delta;
      if(!SettlePartial(e, j.Str("symbol")))
        {
         e.state = JS_UNCERTAIN;
         m_journal.Save(e);
        }
     }

   bool              SettlePartial(CJournalEntry *e, const string symbol)
     {
      STmPosition p;
      STmEvidence ev;
      bool alive = TmFindPositionById(e.position_id, p);
      double now = alive ? p.volume : 0;
      if(alive && now <= e.residual_volume + TM_VOL_EPS)
        {
         TmFindDealsOfOrder(e.order, ev);
         ev.position_id = e.position_id;
         Confirm(e, "done", ev, "", "", ev.volume > 0 ? ev.volume : e.executed_volume, now, symbol);
         return true;
        }
      if(e.order != 0 && TmFindDealsOfOrder(e.order, ev))
        {
         ev.position_id = e.position_id;
         Confirm(e, ev.volume + TM_VOL_EPS < e.executed_volume ? "done_partial" : "done", ev, "", "", ev.volume, now, symbol);
         return true;
        }
      if(!alive && TmFindExitDeals(e.position_id, e.sent_ms > 0 ? e.sent_ms - 5000 : 0, ev))
        {
         Confirm(e, "done", ev, "", "position closed", ev.volume, 0, symbol);
         return true;
        }
      return false;
     }

   void              DoCancel(CTmCommand *c, CJournalEntry *e)
     {
      CJson *j = c.j;
      string openId = j.Str("open_command_id");
      CJournalEntry *oe = openId != "" ? m_journal.FindLatest(openId) : m_journal.LatestOfActionForCopy(c.copy_id, "open");
      if(oe != NULL && oe.Blocking() && oe.state != JS_SUSPENDED)
         return;   // open in flight: wait for it (4.6 step 2)
      STmEvidence ev;
      string comment = Comment(j, c.copy_id);
      ulong knownOrder = 0, knownDeal = 0;
      long since = e.created_ms;
      if(oe != NULL)
        {
         knownOrder = oe.order;
         knownDeal = oe.deal;
         since = oe.created_ms;
        }
      bool found = TmFindOpenEvidence(comment, Magic(j), knownOrder, knownDeal, since, ev) && ev.position_id != 0;
      if(!found && oe != NULL && oe.position_id != 0)
        {
         found = true;
         ev.position_id = oe.position_id;
        }
      if(found)
        {
         // the open executed: close that position and report `closed` (S05)
         DoClose(c, e, ev.position_id, "closed");
         return;
        }
      bool neverSent = (oe == NULL || oe.state == JS_PREPARED ||
                        (oe.state == JS_CONFIRMED && StringFind(oe.result, "\"status\":\"done\"") < 0));
      if(!neverSent)
        {
         Suspend(e, "cancel: the open was sent but no position evidence is visible");
         return;
        }
      // the open never left this terminal: drop it locally so a late delivery never executes it
      if(oe != NULL && oe.state == JS_PREPARED)
        {
         oe.state = JS_CONFIRMED;
         oe.result = "";
         m_journal.Save(oe);
        }
      if(openId != "" && m_journal.Find(openId, "cancelled") == NULL)
        {
         CJournalEntry *mark = m_journal.Create(openId, "cancelled", c.copy_id, "open", 0, "");
         mark.state = JS_CONFIRMED;
         m_journal.Save(mark);
        }
      DropQueued(openId);
      ConfirmSimple(e, "not_executed", "", "open never sent");
     }

   void              DoModify(CTmCommand *c, CJournalEntry *e)
     {
      CJson *j = c.j;
      ulong positionId = (ulong)j.Long("position_id");
      STmPosition p;
      if(!TmFindPositionById(positionId, p))
        { ConfirmSimple(e, "failed", "position_not_found", "no position " + IntegerToString((long)positionId)); return; }
      double sl = j.Dbl("sl", 0);
      double tp = j.Dbl("tp", 0);
      double half = SymbolInfoDouble(p.symbol, SYMBOL_POINT) / 2.0;
      STmEvidence ev;
      TmEvidenceReset(ev);
      ev.position_id = positionId;
      ev.position_ticket = p.ticket;
      if(MathAbs(p.sl - sl) <= half && MathAbs(p.tp - tp) <= half)
        { Confirm(e, "done", ev, "", "already set"); return; }
      MqlTradeRequest r;
      MqlTradeResult res;
      ZeroMemory(r);
      ZeroMemory(res);
      r.action = TRADE_ACTION_SLTP;
      r.position = p.ticket;
      r.symbol = p.symbol;
      r.sl = sl;
      r.tp = tp;
      r.magic = (ulong)p.magic;
      if(!OrderSend(r, res))
         PrintFormat("SL/TP modify of %I64u rejected: %u", p.ticket, res.retcode);
      if(res.retcode == TRADE_RETCODE_DONE)
         Confirm(e, "done", ev, "", "");
      else if(res.retcode == TRADE_RETCODE_INVALID_STOPS || res.retcode == TRADE_RETCODE_NO_CHANGES)
         Confirm(e, "notmodify", ev, TmRetcodeName(res.retcode), res.comment);
      else
         Confirm(e, "failed", ev, res.retcode == 0 ? "local_check_failed" : TmRetcodeName(res.retcode), res.comment);
     }

   // operator resolution of a suspended attempt (4.6 step 7)
   void              DoResolve(CTmCommand *c, CJournalEntry *e)
     {
      CJson *j = c.j;
      string rid = j.Str("resolves_command_id");
      string ratt = j.Str("resolves_attempt_id");
      string resolution = j.Str("resolution");
      ulong pid = (ulong)j.Long("position_id", 0);
      if(rid != "")
        {
         CJournalEntry *t = ratt != "" ? m_journal.Find(rid, ratt) : m_journal.FindLatest(rid);
         if(t != NULL && t.state != JS_CONFIRMED)
           {
            STmEvidence ev;
            TmEvidenceReset(ev);
            ev.position_id = pid != 0 ? pid : t.position_id;
            bool executed = resolution == "executed" || resolution == "closed";
            t.state = JS_CONFIRMED;
            if(pid != 0)
               t.position_id = pid;
            // stored only to answer a re-delivery of that attempt; the server already settled it
            t.result = ResultJson(t, executed ? "done" : "failed", ev, executed ? "" : "not_executed",
                                  "resolved by operator", 0, j.Dbl("residual_volume", -1), "");
            m_journal.Save(t);
            TmLog.Info(StringFormat("copy %I64d: suspended %s %s resolved as %s", t.copy_id, t.action, rid, resolution));
           }
        }
      ConfirmSimple(e, "done", "", "journal updated: " + resolution);
     }

   //--- queue -------------------------------------------------------------------------------
   int               IndexOf(const string id, const string attempt)
     {
      for(int i = 0; i < ArraySize(m_queue); i++)
         if(m_queue[i].id == id && m_queue[i].attempt == attempt)
            return i;
      return -1;
     }

   void              DropQueued(const string commandId)
     {
      for(int i = 0; i < ArraySize(m_queue); i++)
         if(m_queue[i].id == commandId)
            m_queue[i].finished = true;
     }

   void              Compress(void)
     {
      int k = 0;
      for(int i = 0; i < ArraySize(m_queue); i++)
        {
         if(m_queue[i].finished)
           {
            delete m_queue[i];
            continue;
           }
         m_queue[k++] = m_queue[i];
        }
      ArrayResize(m_queue, k);
     }

   // lowest pending seq for this copy (seq gaps never block, 4.5)
   CTmCommand       *HeadOfCopy(const long copyId)
     {
      CTmCommand *best = NULL;
      for(int i = 0; i < ArraySize(m_queue); i++)
        {
         CTmCommand *c = m_queue[i];
         if(c.finished || c.copy_id != copyId || c.action == "resolve")
            continue;
         if(best == NULL || c.seq < best.seq)
            best = c;
        }
      return best;
     }

   void              Execute(CTmCommand *c)
     {
      CJournalEntry *e = m_journal.Find(c.id, c.attempt);
      if(c.action == "open" && m_journal.Find(c.id, "cancelled") != NULL)
        {
         // cancelled locally before it was ever sent
         if(e == NULL)
            e = m_journal.Create(c.id, c.attempt, c.copy_id, c.action, c.seq, c.raw);
         ConfirmSimple(e, "not_executed", "", "open cancelled before it was sent");
         c.finished = true;
         return;
        }
      if(e != NULL)
        {
         if(e.state == JS_CONFIRMED)
           {
            // re-delivered after a lost result: re-send the stored result, never the order (S01)
            if(e.result != "" && !m_outbox.HasCommand(e.command_id))
               m_outbox.Enqueue(e.result, e.command_id);
            c.finished = true;
            return;
           }
         if(e.state == JS_SUSPENDED)
           {
            if(!m_outbox.HasCommand(e.command_id) && e.result != "")
               m_outbox.Enqueue(e.result, e.command_id);
            c.finished = true;
            return;
           }
         if(e.state == JS_SENT || e.state == JS_UNCERTAIN)
           {
            c.finished = true;   // settled by Recover(), never re-sent
            return;
           }
         // JS_PREPARED: never sent (S02) -> evidence check + execute below
        }
      // another attempt of this copy is unresolved: only `resolve` may pass (4.6 step 1)
      if(c.action != "resolve")
        {
         CJournalEntry *b = m_journal.BlockingForCopy(c.copy_id);
         if(b != NULL && b != e)
            return;
        }
      // a failed/expired open makes the copy's later commands moot (4.5)
      if(c.action == "modify" || c.action == "close" || c.action == "close_partial")
        {
         CJournalEntry *oe = m_journal.LatestOfActionForCopy(c.copy_id, "open");
         if(oe != NULL && oe.state == JS_CONFIRMED && oe.position_id == 0 && oe.attempt_id != "cancelled" &&
            StringFind(oe.result, "\"status\":\"done\"") < 0 && c.j.Long("position_id", 0) == 0)
           {
            if(e == NULL)
               e = m_journal.Create(c.id, c.attempt, c.copy_id, c.action, c.seq, c.raw);
            ConfirmSimple(e, "skipped", "open_not_executed", "the copy's open did not execute");
            c.finished = true;
            return;
           }
        }
      if(e == NULL)
         e = m_journal.Create(c.id, c.attempt, c.copy_id, c.action, c.seq, c.raw);

      if(c.action == "open")               DoOpen(c, e);
      else if(c.action == "close")         DoClose(c, e, (ulong)c.j.Long("position_id"), "done");
      else if(c.action == "close_partial") DoClosePartial(c, e);
      else if(c.action == "cancel")        DoCancel(c, e);
      else if(c.action == "modify")        DoModify(c, e);
      else if(c.action == "resolve")       DoResolve(c, e);
      else
         ConfirmSimple(e, "skipped", "unknown_action", "action " + c.action + " is not supported by this EA");

      if(m_crashed)
         return;
      if(e.state == JS_CONFIRMED || e.state == JS_SUSPENDED || e.state == JS_SENT || e.state == JS_UNCERTAIN)
         c.finished = true;
     }

public:
                     CExecutor(void)
     {
      m_journal = NULL; m_outbox = NULL; m_drain = false; m_clockOffsetMs = 0; m_hedging = true;
      m_executedSomething = false; m_crash = TM_CRASH_NONE; m_crashed = false; m_suspendedTicks = 0;
     }
                    ~CExecutor(void)
     {
      for(int i = 0; i < ArraySize(m_queue); i++)
         delete m_queue[i];
      ArrayResize(m_queue, 0);
     }

   void              Init(CJournal *journal, COutbox *outbox) { m_journal = journal; m_outbox = outbox; m_hedging = TmIsHedging(); }
   void              SetDrain(const bool d) { m_drain = d; }
   void              SetClockOffset(const long ms) { m_clockOffsetMs = ms; }
   int               QueueSize(void) const { return ArraySize(m_queue); }
   bool              TakeExecutedFlag(void) { bool f = m_executedSomething; m_executedSomething = false; return f; }

   //--- commands from GET /v4/slave/commands
   void              Receive(CJson *commands)
     {
      if(commands == NULL || commands.type != JSON_ARRAY)
         return;
      for(int i = 0; i < commands.Size(); i++)
        {
         CJson *cj = commands.At(i);
         if(cj == NULL || cj.type != JSON_OBJECT)
            continue;
         string id = cj.Str("command_id");
         string action = cj.Str("action");
         if(id == "")
            continue;
         if(action == "superseded")
           {
            DropQueued(id);   // tombstone of a modify that must not run (4.5)
            continue;
           }
         string attempt = cj.Str("attempt_id", id);
         if(IndexOf(id, attempt) >= 0)
            continue;
         CTmCommand *c = new CTmCommand();
         c.id = id;
         c.attempt = attempt;
         c.action = action;
         c.copy_id = cj.Long("copy_id");
         c.seq = cj.Long("seq_in_copy");
         c.raw = cj.Serialize();
         c.j = JsonParse(c.raw);
         if(c.j == NULL)
           {
            delete c;
            continue;
           }
         int n = ArraySize(m_queue);
         ArrayResize(m_queue, n + 1);
         m_queue[n] = c;
        }
     }

   //--- 4.6 step 6 / 8: sent and uncertain attempts are re-checked; suspended ones on a slower beat
   void              Recover(const bool includeSuspended)
     {
      for(int i = 0; i < m_journal.Total() && !m_crashed; i++)
        {
         CJournalEntry *e = m_journal.At(i);
         if(!(e.state == JS_SENT || e.state == JS_UNCERTAIN || (includeSuspended && e.state == JS_SUSPENDED)))
            continue;
         CJson *j = JsonParse(e.command);
         if(j == NULL)
           {
            if(e.state != JS_SUSPENDED)
               Suspend(e, "journal entry without command payload");
            continue;
           }
         if(e.position_id == 0 && j.Long("position_id", 0) != 0)
            e.position_id = (ulong)j.Long("position_id");
         bool settled = false;
         // a recorded order the broker rejected/cancelled is definitive: no effect
         if(e.order != 0 && !g_tm_hide_evidence && HistoryOrderSelect(e.order))
           {
            long st = HistoryOrderGetInteger(e.order, ORDER_STATE);
            if((st == ORDER_STATE_REJECTED || st == ORDER_STATE_CANCELED) && e.deal == 0)
              {
               STmEvidence none;
               TmEvidenceReset(none);
               none.order = e.order;
               Confirm(e, "failed", none, "order_" + (st == ORDER_STATE_REJECTED ? "rejected" : "cancelled"), "order had no fill");
               settled = true;
              }
           }
         if(!settled)
           {
            if(e.action == "open")
               settled = SettleOpen(e, j);
            else if(e.action == "close")
               settled = SettleClose(e, "done", j.Str("symbol"));
            else if(e.action == "cancel")
               settled = SettleClose(e, "closed", j.Str("symbol"));
            else if(e.action == "close_partial")
              {
               if(e.residual_volume <= 0)
                  e.residual_volume = j.Dbl("residual_volume", 0);
               settled = SettlePartial(e, j.Str("symbol"));
              }
            else
              {
               ConfirmSimple(e, "failed", "not_executed", "non-financial action interrupted");
               settled = true;
              }
           }
         delete j;
         if(settled || e.state == JS_SUSPENDED)
            continue;
         // not conclusive: keep checking for the window, then suspend this copy only (C3)
         if(e.state == JS_SENT)
            e.state = JS_UNCERTAIN;
         e.checks++;
         long age = TmNowMs() - (e.sent_ms > 0 ? e.sent_ms : e.created_ms);
         if(e.checks >= TM_UNCERTAIN_MIN_CHECKS && age >= TM_UNCERTAIN_WINDOW_MS)
            Suspend(e, "sent without conclusive broker evidence");
         else
            m_journal.Save(e);
        }
     }

   //--- local work of one timer tick (4.2 per-tick order steps 1 and 2)
   void              Tick(void)
     {
      m_crashed = false;
      Recover(false);
      m_suspendedTicks++;
      if(m_suspendedTicks >= 10)   // ~every 10 s: suspended entries look for late evidence
        {
         m_suspendedTicks = 0;
         Recover(true);
        }
      // resolves first: they unblock copies
      for(int i = 0; i < ArraySize(m_queue) && !m_crashed; i++)
         if(!m_queue[i].finished && m_queue[i].action == "resolve")
            Execute(m_queue[i]);
      // closing actions, then opens/modifies: one head command per copy per pass
      for(int pass = 0; pass < 2 && !m_crashed; pass++)
        {
         long seen[];
         for(int i = 0; i < ArraySize(m_queue) && !m_crashed; i++)
           {
            CTmCommand *c = m_queue[i];
            if(c.finished)
               continue;
            bool dup = false;
            for(int k = 0; k < ArraySize(seen); k++)
               if(seen[k] == c.copy_id) { dup = true; break; }
            if(dup)
               continue;
            int n = ArraySize(seen);
            ArrayResize(seen, n + 1);
            seen[n] = c.copy_id;
            CTmCommand *head = HeadOfCopy(c.copy_id);
            if(head == NULL)
               continue;
            if((pass == 0) != head.IsClosing())
               continue;
            Execute(head);
           }
        }
      if(!m_crashed)
         Compress();
     }

   //--- OnTradeTransaction: persist the deal of a journal order as soon as it is known
   void              OnTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
     {
      if(trans.type == TRADE_TRANSACTION_REQUEST)
        {
         CJournalEntry *e = m_journal.FindByRequestId(result.request_id);
         if(e != NULL && (e.order == 0 || e.deal == 0))
           {
            if(result.order != 0) e.order = result.order;
            if(result.deal != 0)  e.deal = result.deal;
            m_journal.Save(e);
           }
        }
      else if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
        {
         CJournalEntry *e = m_journal.FindByOrder(trans.order);
         if(e != NULL && e.deal == 0)
           {
            e.deal = trans.deal;
            if(e.action == "open" && trans.position != 0)
               e.position_id = trans.position;
            m_journal.Save(e);
           }
        }
     }

   int               CountState(const string state)
     {
      int n = 0;
      for(int i = 0; i < m_journal.Total(); i++)
         if(m_journal.At(i).state == state)
            n++;
      return n;
     }
  };

#endif
