module API
  module V3
    module Defaults
      extend ActiveSupport::Concern

      included do
        prefix "api"
        version "v3", using: :path
        default_format :json
        # format :json
        # formatter :json, 
        #      Grape::Formatter::ActiveModelSerializers

        helpers do
          def permitted_params
            @permitted_params ||= declared(params, 
               include_missing: false)
          end

          def logger
            Rails.logger
          end

          def meta_version_accept
            yaml = YAML::load(File.open("#{Rails.root}/config/meta_versions.yml"))
            expert_name = params['expert_name']
            expert_version = params['expert_version'][0..3]
            return (yaml[expert_name].present? and yaml[expert_name][expert_version].present?)
          end

          def content
            if params[:data].present?
              content = File.open(params[:data][:tempfile]).try(:read) 
              content.gsub!("\u0000", "")
              content = sanitize_encoding(content)
              return content.to_s
            elsif params["orders"].present?
              content = params["orders"]
              content.gsub!("\u0000", "")
              content = sanitize_encoding(content)
              return content.to_s
            end
          end

          def sanitize_encoding(str)
            begin
              str.force_encoding('iso-8859-1').encode('utf-8')
            rescue => e
              return str
            end
          end
          
          # def error_response(message:, status:, headers: nil, backtrace: nil, original_exception: nil)
          #   error!({ error: message }, status, headers)
          # end
        end

        # rescue_from ActiveRecord::RecordNotFound do |e|
        #   error_response(message: e.message, status: 404)
        # end

        # rescue_from ActiveRecord::RecordInvalid do |e|
        #   error_response(message: e.message, status: 422)
        # end
      end
    end
  end
end