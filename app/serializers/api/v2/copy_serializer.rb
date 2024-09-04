module API
  module V2
    class CopySerializer < ActiveModel::Serializer

      # attr_accessor :lot
      
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
          comment: obj['comment'],
          ticket_deal: obj['ticket_deal'],
          profit: profit,
          # time_trader: time_trader,
          # mae: mae,
          # mfe: mfe,
        }
      end

      def closed_attributes
        {
          price_closed: price_closed,
          profit: obj['profit'],
          closed_at: closed_at,
        }
      end

      def transaction_attributes
        {
          take_profit: take_profit,
          stop_loss: stop_loss,
          profit: profit,
          price_request: price_open,
          lot: lot
        }.compact
      end

      def slave_attributes
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

      def obj
        if object.is_a?(Hash)
          object
        else
          YAML.load(object)
        end
      end

      def ordertype
        obj['type']
      end

      def lot
        obj['volume']
      end

      def price_open
        obj['price_open']
      end

      def price_closed
        obj['price_closed']
      end

      def magic_number
        obj['magicnumber'] || obj['magic_number']
      end

      def stop_loss
        obj['stop_loss']
      end

      def take_profit
        obj['take_profit']
      end

      def ticket
        obj['ticket_id']
      end

      def profit
        obj['profit']
      end

      def mfe
        obj['mfe']
      end

      def mae
        obj['mae']
      end

      def time_trader
        time_zone_diff(obj['time_gmt'], obj['time_trader'], obj['time_trader']) unless obj['time_trader'].nil?
      end

      def closed_at
        update_time_zone((obj['closed_at'] || obj['close_at']))
      end

      def open_at
        update_time_zone(obj['open_at'])
      end

      def update_time_zone(time_at)
        return nil if time_at.blank?
        time_zone_diff(obj['time_gmt'], obj['time_trader'], time_at)
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