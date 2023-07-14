class Token < ApplicationRecord
  belongs_to :resourceable, polymorphic:true
  belongs_to :tokenable, polymorphic:true
end
