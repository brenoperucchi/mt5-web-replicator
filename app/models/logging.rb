class Logging < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :loggerable, polymorphic: true
  # has_many :tracks, :class_name => "Track", :foreign_key => "logging_id"
  belongs_to :version, :class_name => "PaperTrail::Version", :foreign_key => "version_id"
  # has_one :account, :through => :loggerable, :source => :account
  # after_save :set_version

  def state
    klass_name = loggerable.class.name.to_s
    if klass_name.include?("Transaction")
      YAML.load(content)["action"]
    elsif klass_name.include?('Account')
      "COPY"
    end
  end

  def detect_closed?
    YAML.load(content)["action"] == "CLOSED" if loggerable.class.name == "TransactionSlave"
  end

  def account
    klass_name = loggerable.class.name.to_s
    if klass_name.include?("Transaction")
      loggerable.try(:account).try(:name)
    elsif klass_name.include?('Account')
      loggerable.try(:name)
    end
  end

  # def set_version
  #   if loggerable.class.name == "TransactionSlave"
  #     if loggerable.versions
  #       loggerable.versions.last.update(logging:self)
  #     end
  #   end
  # end

  # def track
  #   tracks.try(:last).try(:changeset) if loggerable.class.name == "TransactionSlave"
  # end

end
