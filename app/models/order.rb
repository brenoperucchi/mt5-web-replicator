class Order < ApplicationRecord

  attr_accessor :image_url

  # enum state: %i[ pending prepared ordered error ]
  belongs_to :trace
  has_many :transactions, :class_name => "Transaction", :foreign_key => "order_id"

  scope :image_to_process, ->{ joins(:image_attachment).where.not(image_attachment:nil).where(execute_at: nil).where(ready_at:nil).where.not(state: 'error') }

  scope :ready, ->{ where(state: 'prepared').where.not(state:'error') }

  scope :error, ->{ where(state: 'error')}

  has_one_attached :image

  state_machine :kind, :initial => :message do
    event :order do
      transition :message => :orderd
    end
  end

  state_machine :initial => :pending do
    before_transition :pending => :prepared, :do => :preparing
    after_transition :pending => :prepared, :do => :update_state
    after_transition :pending => :prepared, :do => :verify_symbol
    after_transition :prepared => :executed, :do => :update_state
    after_transition [:prepared, :executed] => :pending, :do => :update_state

    event :prepare do
      transition :pending => :prepared
    end
    event :execute do
      transition :prepared => :executed
    end
    event :erro do
      transition [:prepared, :executed] => :error
    end
    event :cancel do
      transition [:prepared, :executed, :error] => :pending
    end

    state :prepared do

      def update_state(state)
        self.update_column(:ready_at, DateTime.now)
        system("rm -rf #{Rails.root}/public/output.jpg") 
      end

      def verify_symbol(state)

      end
    end
    state :executed do
      def update_state(state)
        self.update_column(:execute_at, DateTime.now)
      end
    end
    state :pending do
      def preparing(state)
        case self.trace.name
        when "M15 Signals Premium", "RoboSignal" 
          self.symbol = self.ocr_text(file:true) 
          self.image.attach(io: File.open("#{Rails.root}/public/output.jpg"), filename: "#{self.symbol}.jpg") 
        when "Swing Trading ViP", "Perucchi Inc"
          self.symbol = self.message.split[0].upcase
        end

      end

      def update_state(state)
        self.update_column(:execute_at, nil)
        self.update_column(:ready_at, nil)
      end
    end

  end

  def ocr_text(url:nil, file:nil)
    if file
      path = Rails.root
      image_path = "#{path}/public/output.jpg"
      # image_path = ActiveStorage::Blob.service.path_for(self.image.key)
      system("#{path}/lib/textcleaner -c '0,140,0,0' -g -t 30 -s 2 -u -p 5 -T #{image_path} #{image_path}")
      image = RTesseract.new(image_path)
      return image.to_s.gsub(/[^A-Za-z]+/, "") #.to_s.scan(/([A-Z]{1,3} *\/ *[A-Z]{1,3})/)

    elsif url
      # path = rails_blob_path(self.image, disposition: "attachment", only_path: true)
    # resource = OcrSpace::Resource.new(apikey: "14ce99dd8788957")relo
    # result = resource.convert url: "http://benincasouza.tplinkdns.com:8080/#{path}"
    end
  end

  def calcule_lot(value)
    decimal = 10 ** (value.to_s.split('.').last.size)
    (self.trace.lots.to_f * value * decimal).round / decimal.to_f
  end



end
