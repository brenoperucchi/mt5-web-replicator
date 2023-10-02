module API
  module V2
    class APICopySerializer < ActiveModel::Serializer
      
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
          profit: obj['profit'],
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

      def mfe
        obj['mfe']
      end

      def mae
        obj['mae']
      end

      def time_trader
        time_zone(obj['time_gmt'], obj['time_trader'], obj['time_trader']) unless obj['time_trader'].nil?
      end

      def closed_at
        update_time_zone((obj['closed_at'] || obj['close_at']))
      end

      def open_at
        update_time_zone(obj['open_at'])
      end

      def update_time_zone(time_at)
        return nil if time_at.nil? or time_at.empty?
        time = time_at
        time = time.to_s.include?(".") ? time.split(".").try(:first).to_i : time.to_i
        zone = obj['timezone'].try(:to_i)

        unless obj.key?("time_trader")
          set_time_zone(time, zone)
        else
          time_zone(obj['time_gmt'], obj['time_trader'], time_at)
        end
      end

      def set_time_zone(time, zone)
        return 0 if time.nil?
        if zone.to_i != 0
         (Time.at(time).utc + zone.hours).to_datetime.change(:offset => Time.zone.formatted_offset)
        else
          Time.use_zone(Time.zone.name) { Time.zone.at(time).utc.to_datetime.change(offset: Time.zone.now.strftime("%z")) }
        end
      end

      def time_zone(time_gmt, time_trader, time_at)
        time_zone = ((DateTime.parse(time_trader).to_i - DateTime.parse(time_gmt).to_i).to_f/3600).round
        time_gmt = DateTime.parse(time_at + time_zone.to_sign) 
        time_gmt.in_time_zone
      end


    end
  end
end