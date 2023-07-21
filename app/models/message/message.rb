require "ancestry"

class Message::Message < ApplicationRecord
  self.table_name = "messages"
  has_ancestry

  serialize :content
  
  has_many :orders
  has_many :transactions,   through: :orders, source: :transactions
  
  # has_many :loggings, dependent: :destroy
  has_many :loggings, as: :loggerable, dependent: :destroy
  
  has_and_belongs_to_many :traces 

  belongs_to :store, optional: true
  # belongs_to :trace, optional: true


  def all_loggings
    loggings.try(:first).try(:subtree)
  end

  def params_copy
    YAML.load content[:imentore_copy] if self.content[:imentore_copy].present?
  end


  def params_url
   content.except(:imentore_copy) if self.content[:imentore_copy].present?
  end


  def request_url
    content["request_url"] || nil
  end



end