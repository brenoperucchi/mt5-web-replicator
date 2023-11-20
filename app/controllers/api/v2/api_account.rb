#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V2
    class APIAccount < Grape::API
      include API::V2::Defaults

      helpers do
        def process_file_upload(file_data)
          # Prepara o objeto StringIO para o novo arquivo
          file_data = file_data.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
          file_contents = StringIO.new(file_data)
          file_contents.set_encoding('UTF-8')
        end

        def sanitize_filename(file_name)
          # Remove caracteres não permitidos em nomes de arquivo
          file_name.gsub("/", "_")
        end

      end

      resource :account do 
        ##Copy Version >= 2.12 
        post "/:kind/post/logfile/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'application/json'

          # Logging.create(content:params, state: "COPY")
          account = Account.find_by(name: params[:account_id], kind: params[:kind], state: :enable)
          if account and account.enable?
            if params[:logfile] && params[:logfile][:tempfile]

              attributes = {
                state: "LOGFILE",
                content: params[:logfile][:filename],
                changeset: account.name,
                account: account,
                loggerable: account,
                resourceable: account.store
              }

              # Use find_or_create_by para uma abordagem mais concisa
              logging = account.loggings.find_or_create_by(state: "LOGFILE", created_at: DateTime.now.all_day)
              logging.update(attributes)

              upload_file = logging.files.first_or_initialize(store:account.store, kind: params[:kind])

              # Se já houver um arquivo, ele será substituído
              upload_file.file.attach(
                io: process_file_upload(File.open(params[:logfile][:tempfile]).read),
                filename: sanitize_filename(params[:logfile][:filename]),
                content_type: params[:logfile][:type]
              )
              upload_file.save if upload_file.new_record? || upload_file.file.attached?
            end

          end

          if upload_file.try(:persisted?)
            body "OK|OK|OK"
            status 201
          else
            body "file_not_created"
            status 401
          end
        end
      end
    end
  end
end