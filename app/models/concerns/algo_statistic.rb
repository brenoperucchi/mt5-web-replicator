require 'matrix'
require 'ruby_linear_regression'

module AlgoStatistic
  extend ActiveSupport::Concern

  included do

    def mfe
      if self.search_date_begin and self.search_date_end
        self.statitics.mfe_max(self.search_date_begin..self.search_date_end.try(:end_of_day))
      else
        self.statitics.mfe_max
      end
      #   self.statitics.group_day_amount(:mfe, search_date_begin..search_date_end.end_of_day)
      # else
      #   self.statitics.group_day_amount(:mfe)
      # end
    end

    def mae    
      if self.search_date_begin and self.search_date_end
        self.statitics.mae_min(self.search_date_begin..self.search_date_end.try(:end_of_day))
      else
        self.statitics.mae_min
      end
      # if self.search_date_begin and self.search_date_end
      #   self.statitics.group_day_amount(:mfe, search_date_begin..search_date_end.end_of_day)
      # else
      #   self.statitics.group_day_amount(:mfe)
      # end
    end

    def data_scope(type=:masters, states=nil, scope=:all, trace=nil)
      table_name = type == :slaves ? "transaction_slaves" : "transactions"

      states = self.send(type).klass.state_machine.states.map(&:name) if states == :all or (states.is_a?(Array) and states.include?(:all))
      if trace.nil?
        data = masters_filter(self.send(type), states)
      else
        if(type == :slaves)
          filtered_relation = self.send(type).where(store: [trace&.stores]).where("#{table_name}.trace_id = ?", trace.id)
          # filtered_relation = self.send(type).where("#{table_name}.trace_id = ?", trace.id).joins(:order).where("orders.store_id = ?", trace.store_id)
        else
          filtered_relation = self.send(type).where("#{table_name}.trace_id = ?", trace.id)
        end
        data = masters_filter(filtered_relation, states)
      end
           
      data = data.send(scope) if !scope.nil? and data.present? and data.respond_to?(*scope)

      if self.search_magic_number.present?
        data = data.where(magic_number: self.search_magic_number)
      end

      data
    end

    def data_profit(type=:masters, trace=nil)
      @data_profit = data_scope(type, :closed, :all, trace).to_a.sum(&:profit)
      @data_profit
    end


    def masters_filter(data, states=nil)
      # if Rails.env.development?
      #   self.search_date_begin = Date.parse("2024-05-01").to_date 
      #   self.search_date_end   = DateTime.current
      #   # self.search_date_end = Date.parse("2024-05-30").to_date 
      # end
      if self.search_date_begin and self.search_date_end
        if (states != :closed or states == :all) && (states.is_a?(Array) and not states.include?(:closed))
          query = {created_at: search_date_begin.beginning_of_day..search_date_end.end_of_day, state: states}.compact
          data = data.where(query)
        else
          query = {closed_at: search_date_begin.beginning_of_day..search_date_end.end_of_day, state: states}.compact
          query_created = {created_at: search_date_begin.beginning_of_day..search_date_end.end_of_day, state: states}.compact
          data = data.where(query).where(query_created)
        end

      end
      data
    end

    def profit_trade(type= :masters, trace=nil)
      trades = data_scope(type, :closed, nil, trace).to_a.try(:count).to_f
      gain_trades = data_scope(type, :closed, :gain, trace).to_a.try(:count).to_f
      AlgoStatistic.profit_trade(trades, gain_trades)
    end

    def loss_trade(type=:masters, trace=nil)
      trades = data_scope(type, :closed, nil, trace).to_a.try(:count).to_f
      loss_trades = data_scope(type, :closed, :loss, trace).to_a.try(:count).to_f
      AlgoStatistic.loss_trade(trades, loss_trades)
    end

    def pay_off(type=:masters, trace=nil)
      gain = data_scope(type, :closed, :gain, trace).to_a.sum(&:profit).abs
      gain_operation = data_scope(type, :closed, :gain, trace).to_a.try(:count).to_f
      loss = data_scope(type, :closed, :loss, trace).to_a.sum(&:profit).abs
      loss_operation = data_scope(type, :closed, :loss, trace).to_a.try(:count).to_f
      AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
    end

    def expect_pay_off(type=:masters, trace=nil)
      total_trades = data_scope(type, :closed, nil, trace).count
      profit_trades = data_scope(type, :closed, :gain, trace).count.to_f
      loss_trades = data_scope(type, :closed, :loss, trace).count.to_f
      gross_profit = data_scope(type, :closed, :gain, trace).to_a.sum(&:profit).abs
      gross_loss = data_scope(type, :closed, :loss, trace).to_a.sum(&:profit).abs
      AlgoStatistic.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
    end

    def profit_factor(type=:masters, trace=nil)
      gross_profit = data_scope(type, :closed, :gain, trace).to_a.sum(&:profit).abs
      gross_loss = data_scope(type, :closed, :loss, trace).to_a.sum(&:profit).abs
      AlgoStatistic.profit_factor(gross_profit, gross_loss, pay_off(type, trace)).abs
    end

    def profit_drawdown(type=:masters, trace=nil)
      gain = self.data_scope(type, :closed, :gain, trace).to_a.sum(&:profit).abs
      loss = self.data_scope(type, :closed, :loss, trace).to_a.sum(&:profit).abs
      profit = gain - loss
      AlgoStatistic.profit_drawdown(profit, drawdown(type, trace)).abs
    end

    def drawdown(type=:masters, trace=nil)
      scoped = data_scope(type, :closed, nil, trace).order(closed_at: :asc)
      AlgoStatistic.drawdown(scoped)
    end

    def drawdown_dates(type=:masters, trace=nil)
      scoped = data_scope(type, :closed, nil, trace).order(closed_at: :asc)
      AlgoStatistic.drawdown_dates(scoped)
    end

    def average(type=:masters, state=nil, scope=nil, trace=nil)
      scoped = data_scope(type, state, scope) 
      return 0 if scoped.size == 0
      scoped.sum(&:profit) / scoped.size
    end

    def dates_dashboard(collection)
      (collection.first.closed_at.beginning_of_day.to_datetime..collection.last.closed_at.end_of_day.to_datetime)
    end

    def dashboard_capital_accumulated(heading = false)
      amount_total = 0
      collection = data_scope(:masters, :closed).order(closed_at: :asc).where.not("transactions.closed_at is NULL AND transactions.profit = 0.0")
      collection_array = []
      if collection.present?
        collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), portfolio: 0, profit: 0, loss:0}] if heading
        dates_dashboard(collection).each do |date|
          profit = collection.where(closed_at: date.beginning_of_day..date.end_of_day).sum(&:profit)
          amount_total = profit + amount_total
          profit_value = profit <= 0 ? 0 : profit
          loss_value = profit >= 0 ? 0 : profit
          if profit_value != 0 or loss_value != 0
            collection_array.push({day:date.strftime("%Y-%m-%d"), portfolio: amount_total.round(2), profit: profit_value.round(2), loss: loss_value.round(2)})
          end
        end
      end
      collection_array
    end

    def dashboard_drawdown
      amount_total = 0
      collection = data_scope(:masters, :closed).order(closed_at: :asc)
      collection_array = []
      if collection.present?
        collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), drawdown: 0}]
        dates_dashboard(collection).each do |date|
          records = collection.where(closed_at: date.beginning_of_day..date.end_of_day)
          drawdown = AlgoStatistic.drawdown(records)
          collection_array.push({day:date.strftime("%Y-%m-%d"), drawdown: drawdown})
        end
      end
      collection_array
    end

    def dashboard_monthy_amount
      amount_total = 0
      date    = ['date']
      profit  = ['profit']
      capital = ['capital']
      array = []
      self.transactions.closed.where.not(closed_at:nil).order('closed_at asc').group_by{|x| x.closed_at.beginning_of_month.strftime("%b/%Y")}.map do |k,v|
        amount_total = v.sum(&:profit) + amount_total
        {date:k, profit: v.sum(&:profit), capital: amount_total} 
      end
    end
  end


  def self.profit_trade(trades, gain_trades)
    result = (gain_trades/trades)
    result = (result * 100).round(2)
    result.nan? ? 0 : result
  end

  def self.loss_trade(trades, loss_trades)
    result = (loss_trades/trades)
    result = (result * 100).round(2)
    result.nan? ? 0 : result
  end

  def self.pay_off(gain, gain_operation, loss, loss_operation)
    result = (gain/gain_operation)/(loss/loss_operation)
    result.nan? ? 0 : result
  end

  def self.profit_factor(profit, loss, pay_off)
    # divide = loss
    return 0 if loss == 0
    result = profit/loss.to_f
    (result.is_a?(Float) and result.nan?) ? 0 : result
  end

  def self.profit_drawdown(profit, drawdown)
    return 0 if drawdown == 0
    result = profit/drawdown.to_f
    (result.is_a?(Float) and result.nan?) ? 0 : result
  end

  def self.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
    result = (profit_trades/total_trades) * (gross_profit / profit_trades) - (loss_trades / total_trades) * (gross_loss / loss_trades)
    (result.is_a?(Float) and result.nan?) ? 0 : result
  end

  def self.drawdown(collection)
    drawdown_balance = 0
    drawdown_max = 0


    # collection.each do |record|
    #   value = record.profit.to_f
    collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
      value = record.sum(&:profit)
      if value < 0 
        drawdown_balance = drawdown_balance + value
        
        if drawdown_balance < drawdown_max
          drawdown_max = drawdown_balance
        end

      else
        drawdown_balance = drawdown_balance + value
        if drawdown_balance > 0
          drawdown_balance = 0 
        end
      end
    end
    drawdown_max
  end

  # def self.drawdown_days(collection)
  #   drawdown_balance = 0
  #   drawdown_max = 0
  #   drawdown_days = 0

  #   # collection.each do |record|
  #   #   value = record.profit.to_f
  #   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
  #     value = record.sum(&:profit)
  #     if value < 0 
  #       drawdown_balance = drawdown_balance + value
        
  #       if drawdown_balance < drawdown_max
  #         drawdown_days += 1
  #         drawdown_max = drawdown_balance
  #       end

  #     else
  #       drawdown_balance = drawdown_balance + value
  #       if drawdown_balance > 0
  #         drawdown_balance = 0 
  #       end
  #     end
  #   end
  #   drawdown_days
  # end

  def self.regression_linear(data)

    data ||= [{:day=>"2023-10-31", :portfolio=>0, :profit=>0, :loss=>0},
             {:day=>"2023-11-01", :portfolio=>404.0, :profit=>404.0, :loss=>0},
             {:day=>"2023-11-06", :portfolio=>408.0, :profit=>4.0, :loss=>0},
             {:day=>"2023-11-07", :portfolio=>612.0, :profit=>204.0, :loss=>0},
             {:day=>"2023-11-08", :portfolio=>471.0, :profit=>0, :loss=>-141.0},
             {:day=>"2023-11-09", :portfolio=>330.0, :profit=>0, :loss=>-141.0},
             {:day=>"2023-11-10", :portfolio=>716.0, :profit=>386.0, :loss=>0},
             {:day=>"2023-11-13", :portfolio=>549.0, :profit=>0, :loss=>-167.0},
             {:day=>"2023-11-14", :portfolio=>985.0, :profit=>436.0, :loss=>0},
             {:day=>"2023-11-16", :portfolio=>829.0, :profit=>0, :loss=>-156.0},
             {:day=>"2023-11-17", :portfolio=>741.0, :profit=>0, :loss=>-88.0},
             {:day=>"2023-11-20", :portfolio=>739.0, :profit=>0, :loss=>-2.0},
             {:day=>"2023-11-21", :portfolio=>674.0, :profit=>0, :loss=>-65.0},
             {:day=>"2023-11-22", :portfolio=>554.0, :profit=>0, :loss=>-120.0},
             {:day=>"2023-11-23", :portfolio=>371.0, :profit=>0, :loss=>-183.0},
             {:day=>"2023-11-24", :portfolio=>323.0, :profit=>0, :loss=>-48.0}
            ]

    # Preparando os data para a regressão linear
    x_data = data.map.with_index(0) { |d, index| [index] }
    y_data = data.map { |d| (d[:portfolio]).to_i }

    # Criando e treinando o modelo
    linear_regression = RubyLinearRegression.new
    linear_regression.load_training_data(x_data, y_data)
    linear_regression.train_normal_equation

    
    # Coeficientes da regressão linear
    intercept, slope = [linear_regression.theta[0,0], linear_regression.theta[1,0]]

    # Data de início para cálculo
    date_begin = Date.parse(data[0][:day])

    # Calculando a linha de tendência
    linha_tendencia = data.map do |d|
      dias = (Date.parse(d[:day]) - date_begin).to_i
      valor_tendencia = slope * dias + intercept
      { day: d[:day], linear: valor_tendencia }
    end
  end

  def self.trend_line(data, window_size=1)
    # Convertendo datas para números sequenciais a partir de 0
    x_data = data.map.with_index { |_, index| index }
    y_data = data.map { |d| d[:portfolio].to_f }

    # Calculando média móvel
    sma_values = y_data.each_cons(window_size).map { |window| window.sum / window.size.to_f }

    # Preparar x_data para corresponder ao tamanho de sma_values
    x_data_sma = x_data[window_size - 1..-1]

    # Aplicar regressão linear na média móvel
    xxs = x_data_sma.sum { |x| x * x }
    xys = x_data_sma.zip(sma_values).sum { |x, y| x * y }

    # Calculando a inclinação (slope)
    slope = (xxs.to_f == 0) ? 0 : (xys / xxs.to_f)
    intercept = 0

    # Gerando valores da linha de tendência
    linha_tendencia = x_data_sma.map.with_index do |x, i|
      valor_tendencia = slope * x + intercept
      
      { day: data[x][:day], linear: valor_tendencia.round }# if i == 0 or i == x_data_sma.size - 1
    end

    linha_tendencia.compact
  end

  # def self.trend_line(data)
  #   data ||= [{:day=>"2023-10-31", :portfolio=>0, :profit=>0, :loss=>0},
  #            {:day=>"2023-11-01", :portfolio=>404.0, :profit=>404.0, :loss=>0},
  #            {:day=>"2023-11-06", :portfolio=>408.0, :profit=>4.0, :loss=>0},
  #            {:day=>"2023-11-07", :portfolio=>612.0, :profit=>204.0, :loss=>0},
  #            {:day=>"2023-11-08", :portfolio=>471.0, :profit=>0, :loss=>-141.0},
  #            {:day=>"2023-11-09", :portfolio=>330.0, :profit=>0, :loss=>-141.0},
  #            {:day=>"2023-11-10", :portfolio=>716.0, :profit=>386.0, :loss=>0},
  #            {:day=>"2023-11-13", :portfolio=>549.0, :profit=>0, :loss=>-167.0},
  #            {:day=>"2023-11-14", :portfolio=>985.0, :profit=>436.0, :loss=>0},
  #            {:day=>"2023-11-16", :portfolio=>829.0, :profit=>0, :loss=>-156.0},
  #            {:day=>"2023-11-17", :portfolio=>741.0, :profit=>0, :loss=>-88.0},
  #            {:day=>"2023-11-20", :portfolio=>739.0, :profit=>0, :loss=>-2.0},
  #            {:day=>"2023-11-21", :portfolio=>674.0, :profit=>0, :loss=>-65.0},
  #            {:day=>"2023-11-22", :portfolio=>554.0, :profit=>0, :loss=>-120.0},
  #            {:day=>"2023-11-23", :portfolio=>371.0, :profit=>0, :loss=>-183.0},
  #            {:day=>"2023-11-24", :portfolio=>323.0, :profit=>0, :loss=>-48.0}
  #           ]

  #   # Convertendo datas para números sequenciais a partir de 0
  #   x_data = data.map.with_index { |_, index| index }
  #   y_data = data.map { |d| d[:portfolio].to_f }

  #   # Calculando a soma dos quadrados de x (xxs) e a soma do produto de x e y (xys)
  #   xxs = x_data.sum { |x| x * x }
  #   xys = x_data.zip(y_data).sum { |x, y| x * y }

  #   # Calculando a inclinação (slope)
  #   slope = xys / xxs.to_f

  #   # Ajustando o intercepto para que o primeiro valor (x=0) seja 0
  #   intercept = 0

  #   # Gerando valores da linha de tendência
  #   linha_tendencia = x_data.map do |x|
  #     valor_tendencia = slope * x + intercept
  #     { day: data[x][:day], linear: valor_tendencia.round }
  #   end

  #   linha_tendencia
  # end


  def self.drawdown_dates(collection)
    drawdown_balance = 0
    drawdown_max = 0
    drawdown_dates = []
    drawdown_dates_max = []


    collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
      value = record.sum(&:profit)
      if value < 0 
        drawdown_balance = drawdown_balance + value
        drawdown_dates.push(Date.strptime(date,"%Y  %m %d"))
        if drawdown_balance < drawdown_max
          drawdown_dates_max = (drawdown_dates)
          drawdown_max = drawdown_balance
        end
      else
        drawdown_balance = drawdown_balance + value
        if drawdown_balance > drawdown_max
          drawdown_balance = 0 
          drawdown_dates = []
        end
      end
    end
    return drawdown_dates_max
  end

  # def self.drawdown_dates(collection)
  #   drawdown_balance = 0
  #   drawdown_max = 0
  #   drawdown_dates = []
  #   drawdown_dates_max = []

  #   # collection.reverse.each do |record|
  #   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
  #     # value = record.profit.to_f
  #     value = record.sum(&:profit)
  #     # puts "----------BEGIN-------------"
  #     # # puts "Date => #{record.created_at.strftime("%Y/%m/%d")}"
  #     # puts "Date => #{date}"
  #     # puts "Value => #{value.to_f}"
  #     # puts "drawdown_balance => #{drawdown_balance.to_f}"
  #     if value < 0 
  #       # puts "drawdown_balance + value => #{drawdown_balance.to_f} + #{value} = #{drawdown_balance + value}"
  #       drawdown_balance = drawdown_balance + value
  #       # puts "drawdown_max => #{drawdown_max.to_f}"
  #       # puts "if drawdown_balance < drawdown_max => #{drawdown_balance} < #{drawdown_max} = #{drawdown_balance < drawdown_max}"
  #       # # drawdown_dates.push([record.created_at.strftime("%Y/%m/%d"), value])
  #       drawdown_dates.push(Date.strptime(date,"%Y  %m %d"))
  #       # puts "drawdown_dates => #{drawdown_dates}"
  #       if drawdown_balance < drawdown_max
  #         drawdown_dates_max = (drawdown_dates)
  #         # puts "drawdown_dates_max => #{drawdown_dates}"
  #         drawdown_max = drawdown_balance
  #         # puts "drawdown_max = drawdown_balance => #{drawdown_max.to_f}"
  #       end
  #     else
  #       # puts "ELSE"
  #       # puts "drawdown_balance + value => #{drawdown_balance.to_f} + #{value} = #{drawdown_balance + value}"
  #       drawdown_balance = drawdown_balance + value
  #       # puts "if drawdown_balance > drawdown_max => #{drawdown_balance} > #{drawdown_max} = #{drawdown_balance > drawdown_max}"
  #       if drawdown_balance > drawdown_max
  #         drawdown_balance = 0 
  #         # puts "Value >= 0 ELSE - drawdown_dates => #{drawdown_dates}"
  #         drawdown_dates = []
  #         # puts "Value >= 0 ELSE - drawdown_dates => #{drawdown_dates}"
  #         # puts "drawdown_balance = 0  => #{drawdown_balance.to_f}"
  #         # puts "drawdown_max     = 0  => #{drawdown_max.to_f}"
  #       end
  #     end
  #     # puts "----------END-------------"
  #   end
  #   # "#{drawdown_dates.first.strftime("%Y/%m/%d")} - #{drawdown_dates.last.strftime("%Y/%m/%d")}"
  #   # puts "drawdown_dates => #{drawdown_dates}"
  #   return drawdown_dates_max
  # end

  # def self.drawdown_dates(collection)
  #   drawdown_balance = 0
  #   drawdown_max = 0
  #   drawdown_dates = []

  #   collection.group_by{|x| x.created_at.strftime("%Y %m %d")}.each do |date, record|
  #     value = record.sum(&:profit)
  #     drawdown_balance = drawdown_balance + value
  #     if value < 0 
        
  #       if drawdown_balance < drawdown_max
  #         drawdown_dates.push("#{date} - #{value}")
  #         drawdown_dates.push(date)
  #         drawdown_max = drawdown_balance
  #       end

  #     else
  #       # drawdown_balance = drawdown_balance + value
  #       if drawdown_balance > drawdown_max
  #         drawdown_balance = drawdown_max
  #         # drawdown_max = 0
  #       end
  #     end
  #   end
  #   drawdown_dates
  #   # return [] unless drawdown_dates.present?
  #   # "#{Date.strptime(drawdown_dates.first,"%Y  %m %d").strftime("%Y/%m/%d")} - #{Date.strptime(drawdown_dates.first,"%Y  %m %d").strftime("%Y/%m/%d")}"
  # end
  
end