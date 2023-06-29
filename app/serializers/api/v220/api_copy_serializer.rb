module API
  module V220
    class APICopySerializer < ActiveModel::Serializer

      def method_missing(m, *args, &block)
        obj[m.to_s]
      end
      
      def copy_attributes
        {
          symbol: obj['symbol'],
          ticket: obj['ticket_id'],
          ticket_deal: obj['ticket_deal'],
          ordertype: obj['type'],
          lot: obj['volume'],
          price_open: obj['price_open'],
          price_closed: obj['price_closed'],
          profit: obj['profit'],
          stop_loss: obj['stop_loss'],
          take_profit: obj['take_profit'],
          open_at: open_at,
          # time_trader: time_trader,
          # time_gmt: obj['time_gmt'],
          # time_zone: obj['timezone'],
          # state_meta: obj['state_meta'],
          magic_number: obj['magic_number'],
          comment: obj['comment'],
        }
      end

      def update_order_attributes
        {
          symbol: obj['symbol'],
          ticket: obj['ticket_id'],
          ticket_deal: obj['ticket_deal'],
          ordertype: obj['type'],
          lot: obj['volume'],
          price_open: obj['price_open'],
          price_closed: obj['price_closed'],
          profit: obj['profit'],
          stop_loss: obj['stop_loss'],
          take_profit: obj['take_profit'],
          # mae: obj['mae'],
          # mfe: obj['mfe'],
          open_at: open_at,
          # time_trader: time_trader,
          # time_gmt: obj['time_gmt'],
          # time_zone: obj['timezone'],
          # state_meta: obj['state_meta'],
          magic_number: obj['magic_number'],
          comment: obj['comment'],
        }
      end

      # def mae
      #   obj['mae']
      # end

      # def mfe
      #   obj['mfe']
      # end 

      def obj
        if object.is_a?(Hash)
          object
        else
          YAML.load(object)
        end
      end

      def time_trader
        time_zone(obj['time_gmt'], obj['time_trader'], obj['time_trader']) unless obj['time_trader'].nil?
      end

      def open_at
        time = obj['open_at']
        time = time.to_s.include?(".") ? time.split(".").try(:first).to_i : time.to_i
        zone = obj['timezone'].try(:to_i)

        unless obj.key?("time_trader")
          set_time_zone(time, zone)
        else
          time_zone(obj['time_gmt'], obj['time_trader'], obj['open_at'])
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

      def time_zone(time_gmt, time_trader, time_open)
        time_zone = ((DateTime.parse(time_trader).to_i - DateTime.parse(time_gmt).to_i).to_f/3600).round
        time_gmt = DateTime.parse(time_open + time_zone.to_sign) 
        time_gmt.in_time_zone
      end


    end
  end
end