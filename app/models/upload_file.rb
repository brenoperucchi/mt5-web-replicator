class UploadFile < ApplicationRecord
  belongs_to :uploadable, polymorphic: true, optional: true
  belongs_to :store,                         optional: true
  belongs_to :trace,                         optional: true

  after_create_commit :import_file

  has_one_attached :file


  def import_file(trace_id=nil)

    return if self.kind != "import"
    csv_content = file.download # Baixa o conteúdo do arquivo
    trace = self.trace
    trace ||= Trace.find_by(id:trace_id)
    return if trace.nil?
    
    message = Message::Import.create(content: csv_content, state: "pending", store: store, state_meta: "import")
    message.create_orders(trace)
  end
end
