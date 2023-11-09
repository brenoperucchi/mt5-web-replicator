#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V2
    class APIAccount < Grape::API
      include API::V2::Defaults


      helpers do
        def process_file_upload(logging, file_data, file_name, store, kind)
          # Prepara o objeto StringIO para o novo arquivo
          file_contents = StringIO.new(file_data)
          file_contents.set_encoding('UTF-8')

          # Procura a primeira associação de arquivo ou cria uma nova
          upload_file = logging.files.first_or_initialize(store:store, kind: kind)

          # Se já houver um arquivo, ele será substituído
          upload_file.file.attach(
            io: file_contents,
            filename: sanitize_filename(file_name),
            content_type: 'text/plain'
          )

          # Salva o UploadFile se necessário
          upload_file.save if upload_file.new_record? || upload_file.file.attached?
        end

        def sanitize_filename(file_name)
          # Remove caracteres não permitidos em nomes de arquivo
          file_name.gsub("/", "_")
        end

        def parse_dynamic_json(json_string)
          # Corrigindo aspas simples para aspas duplas e removendo quebras de linha não escapadas
          corrected_json = json_string.gsub("'", '"').gsub(/\r?\n/, '\\n')

          # Tentando analisar a string JSON corrigida
          begin
            JSON.parse(corrected_json)
          rescue JSON::ParserError => e
            puts "Erro ao analisar JSON: #{e.message}"
            return nil # Retorna nil ou lança uma exceção, dependendo da sua preferência
          end
        end

      end

      resource :account do 
        ##Copy Version >= 2.12 
        post "/:kind/post/logfile/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'application/json'

          # Logging.create(content:params, state: "COPY")
          account = Account.find_by(name: params[:account_id], kind: params[:kind])
          if account and account.enable?

            unless params["body"].valid_encoding?
              params["body"] = params["body"].encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
            end
            # Parseia a entrada de forma segura
            parameters = parse_dynamic_json(params["body"])
            attributes = {
              state: "LOGFILE",
              content: parameters["log_filename"],
              changeset: account.name,
              account: account,
              loggerable: account,
              resourceable: account.store
            }

            # Use find_or_create_by para uma abordagem mais concisa
            logging = account.loggings.find_or_create_by(state: "LOGFILE", created_at: DateTime.now.all_day)
            logging.update(attributes)
            process_file_upload(logging, (parameters["log_file_content"] + params.except("body").to_s + parameters.except("log_file_content").to_s), parameters["log_filename"], account.store, parameters["log_kind"])

          end

          body "OK|OK|OK"
          status 201
        end
      end
    end
  end
end