class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Ransack 4 requires explicit allowlists. Search is only exposed through the
  # authenticated admin/ and control/ dashboards, so keep ransack 3's behavior
  # of allowing every column and association.
  def self.ransackable_attributes(_auth_object = nil)
    authorizable_ransackable_attributes
  end

  def self.ransackable_associations(_auth_object = nil)
    authorizable_ransackable_associations
  end
end
