module API
  module V3
    class CopySerializer < ActiveModel::Serializer
      
      def copy_attributes
        {
          ordertype: ordertype,
          lot: lot,
          price_open: price_open,
          # price_closed: price_closed,
          magic_number: magic_number,
          stop_loss: stop_loss,
          take_profit: take_profit,
          ticket: ticket,
          open_at: open_at,
          comment: comment,
          ticket_deal: ticket_deal,
          profit: profit,
          entry: entry,
          fee: fee,
          # time_trader: time_trader,
          # mae: mae,
          # mfe: mfe,
        }
      end

      def closed_attributes
        {
          fee: fee,
          profit: profit,
          price_closed: price_closed,
          closed_at: closed_at
        }
      end


      def transaction_attributes
        {
          lot: lot,
          fee: fee,
          profit: profit,
          price_request: price_open,
          take_profit: take_profit,
          stop_loss: stop_loss
        }.compact
      end

      def slave_attributes # A ORDEM DEPENDE PARA O `transaction.set_sl_and_tp_order``
        {
          take_profit: take_profit, 
          stop_loss: stop_loss, 
          price_request: price_open,
          lot: lot
        }.compact
      end

      def mfe_attributes
        { 
          mfe: mfe, 
          mae: mae, 
          time_trader: time_trader
        }.compact
      end

      def trace_attributes(instrument, account_slave, master, trace)
        {
          symbol: instrument,
          ticket: ticket,
          position_id: obj['positionID'],
          ticket_deal: ticket_deal,
          ordertype: ordertype,
          lot: lot,
          price_open: price_open,
          price_closed: price_closed,
          price_request: price_open,
          stop_loss: stop_loss,
          take_profit: take_profit,
          profit: 0,
          comment: comment,
          magic_number: magic_number,
          account: account_slave,
          master: master,
          trace: trace,
          open_at: nil,
          closed_at: nil
        }.compact
      end


      def obj
        if object.is_a?(Hash)
          object
        else
          YAML.load(object)
        end
      end

      def comment
        obj['comment']
      end

      def ticket_deal
        obj['ticketDeal']
      end

      def ordertype
        obj['type']
      end

      def entry
        obj['entry']
      end

      def lot
        obj['volume']
      end      

      def volume
        obj['volume']
      end

      def price_open
        obj['priceOpen']
      end

      def price_closed
        obj['priceClose']
      end

      def magic_number
        obj['magicNumber']
      end

      def stop_loss
        obj['stopLoss']
      end

      def take_profit
        obj['takeProfit']
      end
      
      ## TODO VER ISSO URGENTE!
      ## TODO VER ISSO URGENTE!
      def ticket
        obj['ticketMaster'] || obj['ticket']
      end
      ## TODO VER ISSO URGENTE!
      ## TODO VER ISSO URGENTE!

      def profit
        obj['profit']
      end

      def fee
        obj['fee'] || 0
      end

      def swap
        obj['swap'] || 0
      end

      def commission
        obj['commission'] || 0
      end

      def mfe
        obj['mfe']
      end

      def mae
        obj['mae']
      end

      def time_trader
        time_zone_diff(obj['timeGMT'], obj['timeTrader'], obj['timeTrader']) unless obj['timeTrader'].nil?
      end

      def closed_at
        update_time_zone(obj['closeAt'])
      end

      def open_at
        update_time_zone(obj['openAt'])
      end

      def update_time_zone(time_at)
        return nil if time_at.blank?
        time_zone_diff(obj['timeGMT'], obj['timeTrader'], time_at)
      end

      def time_zone_diff(time_gmt, time_trader, time_at)
        # Calculate timezone difference in hours
        trader_time = DateTime.parse(time_trader)
        gmt_time = DateTime.parse(time_gmt)
        time_zone_hours = ((trader_time.to_time - gmt_time.to_time) / 1.hour).round

        # Parse the 'time_at' and adjust for the timezone
        parsed_time = DateTime.parse(time_at)
        adjusted_time = parsed_time - time_zone_hours.hours

        # Return the adjusted time
        adjusted_time
      end

    end
  end
end