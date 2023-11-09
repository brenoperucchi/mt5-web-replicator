module API
  module V2
    module Defaults
      extend ActiveSupport::Concern

      included do
        prefix "api"
        version "v2", using: :path
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