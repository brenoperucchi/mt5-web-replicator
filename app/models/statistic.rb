class Statistic < ApplicationRecord
  belongs_to :statisticable, polymorphic: true

  enum kind:  {mfe: 0, mae: 1}

  def self.mfe_max(range = nil)
    if range.nil?
      mfe.max{|x| x.amount}
      # send(kind.to_s).group_by{|x| x.created_at.strftime("%Y %m %d")}
    else
      where(created_at: range, kind: :mfe).max{|x| x.amount}
    end
  end

  def self.mae_min(range = nil)
    if range.nil?
      mae.min{|x| x.amount}
      # send(kind.to_s).group_by{|x| x.created_at.strftime("%Y %m %d")}
    else
      # where(created_at: range, kind: kind.to_s).group_by{|x| x.created_at.strftime("%Y %m %d")}
      where(created_at: range, kind: :mae).min{|a,b| a.amount <=> b.amount}
    end
  end
end