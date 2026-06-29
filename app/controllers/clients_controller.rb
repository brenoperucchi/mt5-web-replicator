require 'rest-client'
class ClientsController < ApplicationController
  layout 'stisla'
  before_action :set_client, only: [:show, :edit, :update, :destroy]

  # GET /clients
  # GET /clients.json
  def index
    # @clients = Client.all
    response = RestClient.get("localhost:3000/api/v1/clients").body

    @clients = JSON.parse(response).map{|x| Api::Client.new(x)}
    # render json: response
  end

  # GET /clients/1
  # GET /clients/1.json
  def show
  end

  # GET /clients/new
  def new
    @client = Api::Client.new
  end

  # GET /clients/1/edit
  def edit
  end

  # POST /clients
  # POST /clients.json
  def create
    # @client = Api::Client.new(client_params)
    response = RestClient.post("localhost:3000/api/v1/clients", params:client_params, content_type: :json, accept: :json)
    json = JSON.parse(response.body)
    @client = Api::Client.new(json)

    respond_to do |format|
      if @client.valid?
        format.html { redirect_to clients_url, notice: 'Client was successfully created.' }
        format.json { render :show, status: :created, location: @client }
      else
        format.html { render :new }
        format.json { render json: @client.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /clients/1
  # PATCH/PUT /clients/1.json
  def update
    response = RestClient.put("localhost:3000/api/v1/clients/#{params[:id]}", params:client_params, content_type: :json, accept: :json)
    json = JSON.parse(response.body)
    @client = Api::Client.new(json)
    respond_to do |format|
      if @client.valid?
        format.html { redirect_to client_path(@client.id) , notice: 'Client was successfully updated.' }
        format.json { render :show, status: :ok, location: @client }
      else
        format.html { render :edit }
        format.json { render json: @client.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /clients/1
  # DELETE /clients/1.json
  def destroy
    response = RestClient.delete("localhost:3000/api/v1/clients/#{params[:id]}", params:{_destroy: true}, content_type: :json, accept: :json)
    if response.code == 200
      respond_to do |format|
        format.html { redirect_to clients_url, notice: 'Client was successfully destroyed.' }
        format.json { head :no_content }
      end
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_client
      response = RestClient.get("localhost:3000/api/v1/clients/#{params[:id]}", content_type: :json, accept: :json)
      @client = Api::Client.new(JSON.parse(response.body))
      # @client = Client.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def client_params
      params.require(:api_client).permit(:name, :active, :email, :plan, :created_at, :updated_at, :destroy)
    end
end
