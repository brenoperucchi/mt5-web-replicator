class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable#, :validatable

  belongs_to :store
  belongs_to :userable, polymorphic: true, optional: true, dependent: :destroy

  validates_uniqueness_of :email, scope: [:store_id]
  validates_presence_of :email
  validates_presence_of :password, :on => :create

end