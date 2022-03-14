class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :store
  belongs_to :userable, polymorphic: true, optional: true
  # has_one :customer, :class_name => "Customer", :foreign_key => "user_id"

  validates_uniqueness_of :email, scope: :store
end
