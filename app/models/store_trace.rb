class StoreTrace < ApplicationRecord
  belongs_to :store
  belongs_to :trace

  validates_uniqueness_of :store_id, scope: [:trace_id]
  validate :validate_unique_name_id_per_store, if: -> { trace.present? && !trace.magic_same.to_b }

  private

  def validate_unique_name_id_per_store
    return if trace.name_id.blank?
    
    existing_traces = Trace.joins(:store_traces)
                           .where(store_traces: {store_id: store_id})
                           .where(name_id: trace.name_id)
                           .where.not(id: trace.id)
                           
    if existing_traces.exists?
      errors.add(:base, "Trace with name_id '#{trace.name_id}' already exists for this store")
    end
  end
end
