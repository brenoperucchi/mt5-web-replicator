class SignOrder < ApplicationRecord

  # enum state: %i[ pending processed ordered error ]
  belongs_to :sign_trace

  scope :image_to_process, ->{ joins(:image_attachment).where.not(image_attachment:nil).where(order_at: nil).where(ready_at:nil).where.not(state: 'error') }

  scope :ready, ->{ where(state: 'processed').where.not(state:'error') }

  scope :error, ->{ where(state: 'error')}

  has_one_attached :image

  state_machine :initial => :pending do
    after_transition :pending => :processed, :do => :update_state
    after_transition :pending => :processed, :do => :verify_symbol
    after_transition :processed => :ordered, :do => :update_state
    after_transition [:processed, :ordered] => :pending, :do => :update_state

    event :process do
      transition :pending => :processed
    end
    event :order do
      transition :processed => :ordered
    end
    event :erro do
      transition [:processed, :ordered] => :error
    end
    event :cancel do
      transition [:processed, :ordered, :error] => :pending
    end

    state :processed do
      def update_state(state)
        self.update_column(:ready_at, DateTime.now)
        system("rm -rf #{Rails.root}/public/output.tiff")
      end

      def verify_symbol(state)
        if sign_trace.name.downcase == "m15 signals premium"
          sym = self.message.split[0]
          self.update_columns(symbol: sym, message:message.gsub(sym, '')) if not self.symbol
        end
      end
    end
    state :ordered do
      def update_state(state)
        self.update_column(:order_at, DateTime.now)
      end
    end
    state :pending do
      def update_state(state)
        self.update_column(:order_at, nil)
        self.update_column(:ready_at, nil)
      end
    end

  end

  def ocr_text(url:nil, file:nil)
    if file
      path = Rails.root
      image_path = ActiveStorage::Blob.service.path_for(self.image.key)
      system("#{path}/lib/textcleaner -c '0,140,0,0' -g -t 30 -s 2 -u -p 5 -T #{image_path} #{path}/public/output.tiff")
      image = RTesseract.new("#{path}/public/output.tiff")
      return image.to_s.gsub(/[^A-Za-z]+/, "") #.to_s.scan(/([A-Z]{1,3} *\/ *[A-Z]{1,3})/)

    elsif url
      # path = rails_blob_path(self.image, disposition: "attachment", only_path: true)
    # resource = OcrSpace::Resource.new(apikey: "14ce99dd8788957")relo
    # result = resource.convert url: "http://benincasouza.tplinkdns.com:8080/#{path}"
    end

  end


end
