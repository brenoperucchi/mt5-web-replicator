module API
  module V220
    module Defaults
      extend ActiveSupport::Concern

      included do
        prefix "api"
        version "v220", using: :path
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
            yaml[params['expert_name']][params['expert_version']].present? ? true : false
          end

        end

        rescue_from ActiveRecord::RecordNotFound do |e|
          error_response(message: e.message, status: 404)
        end

        rescue_from ActiveRecord::RecordInvalid do |e|
          error_response(message: e.message, status: 422)
        end
      end
    end
  end
end