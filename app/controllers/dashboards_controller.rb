class DashboardsController < ApplicationController
  # skip_before_action :after_sign_in_path_for
  before_action :set_trace, except: [:index]
  before_action :set_store
  before_action :filters, except: :create
  before_action :dashboard_restrict, except: :create

  respond_to :html, :xml, :json


  # before_action :authenticate_user
  # layout 'stisla'
  layout 'modernize'
  # layout 'mintone'

  # before_action :sign_up!


  # def sign_up!
  # 	redirect_to new_user_session_path if !user_signed_in?
  # end

  def mfe
    # @dates = @trace.analyze_transactions
    # respond_with
  end

  def transaction
    @account = Account.find(params[:account_id])
    @transaction = Transaction.find(params[:transaction_id])
    respond_with(@account)
  end

  def finish
    trace 	= Trace.find_by(name: params[:name])
    account = Account.find(params[:account_id])
    
    # invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
    account.create_invoice_account(@trace, true, nil)
    @invoice = account.customer.invoices.first
    @payment = @invoice.invoice_send
    if @payment.redirect_url
      redirect_to @payment.redirect_url
    else
      render :finish
    end
  end

  def contract
    # @contract_volume = params.dig([:account][:settings][:contract_volume]) || 1
    @trace.customer_plan.promotion_use = true if params[:promotion] == "promotion"
    respond_to do |wants|
      wants.js { render layout: false }
      wants.html do  
        @account = @trace.accounts.new
      end
    end
  end

  def create
    sign_out if user_signed_in?
    password = Devise.friendly_token.first(6)
    customer_plan_id = params[:customer_plan_id]
    account = @trace.accounts.new(account_params)
    account.state = "enable"
    # account.customer.store = current_store
    account.customer.role = "customer"
    account.customer.role_control = "user"
    account.customer.user.password = password
    account.traces << @trace
    if @trace.valid? and account.save
      # invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
      plan_usage = account.add_account_trace_to_planusage(@trace, customer_plan_id)
      customer_plan = plan_usage.usageable
      customer_plan.promotion_use = true if params[:promotion] == "promotion"
      customer_plan.save
      # account.customer.create_invoice_customer(invoice_name)
      # @customer.create_user(email: @customer.user_email, password: password)
      # redirect_to finish_dashboard_path(@trace.store.url, @trace.name, account)
      account.create_invoice_account(@trace, true, nil)
      @invoice = account.customer.invoices.first
      @payment = @invoice.invoice_send
      if @payment.redirect_url
        redirect_to @payment.redirect_url
      else
        render :finish
      end
    else
      filters
      @account = account
      flash[:notice] = "Error na contração de Portfolio"
      render :contract
    end
  end

  def dashboard_restrict
    flash[:notice] = nil


    unless @current_store.nil?
      if @current_store.dashboard_restrict == "enable" and (not user_signed_in? or @current_store.users.find_by(id:current_user.try(:id)).nil?)
        sign_out current_user
        redirect_to user_session_path, notice: "Dashboard restrict. You must be logged"
      else
        @traces = @current_store.traces.active.map do |trace| 
          trace.search_date_begin 				= session[:date_begin].strip().to_datetime.change(offset: @timezone) 
          trace.search_date_end 					= session[:date_end].strip().to_datetime.change(offset: @timezone) 
          # trace.dashboard_magic_number 	  = trace.magic_number_restrict?


          [trace.data_profit.to_f, trace.id]
        end
        @traces = @traces.sort
      end
    else
      redirect_to root_path, notice: "Dashboard not found"
    end
  end

  def index
    @all_records = request.fullpath.include?("all") ? true : false
    respond_to do |wants|
      
      wants.html { render :index}
    end
  end

  def show
    @trace.search_date_begin 				= session[:date_begin].strip().to_datetime.change(offset: @timezone) 
    @trace.search_date_end 					= session[:date_end].strip().to_datetime.change(offset: @timezone) 
    # @trace.dashboard_magic_number 	= session[:dashboard_magic_number]

    respond_to do |wants|
      wants.html do
        if @trace
          render action: :show
        else
          redirect_to dashboards_path, layout: 'modernize'
        end
      end
    end
  end

  def account
    @account = Account.find(params[:account_id])

    # @trace = Trace.find_by(name: params[:name])
    # @account = current_store.accounts.find(params[:id])
    @account.search_date_begin = session[:date_begin].strip().to_datetime.change(offset: @timezone) 
    @account.search_date_end = session[:date_end].strip().to_datetime.change(offset: @timezone) 
    if @account
      render action: :account
    else
      redirect_to dashboards_path
    end
  end

  private

  def account_params
    params.require(:account).permit(:name, :url, :password, :email, :kind, :meta_margin_mode, :meta_mode, :store_id, settings:[:contract_volume, :meta_mode, :meta_margin_mode],
                customer_attributes:[:name, :customer_plan_id, :user_email, :store_id, user_attributes:[:email, :store_id]]) 
  end

  def set_store
    @current_store = Store.find_by(url: params[:store_name].downcase) if params[:store_name].present?
    @current_store ||= @trace.try(:store)
    @current_store ||= Trace.find_by(name: params[:name])
    @current_store ||= current_store
  end

  def set_trace
    @trace = Trace.find_by(name: params[:name])
    if @trace.nil?
      redirect_to root_path, notice: "Dashboard Not found"
    end
  end

  def filters
    # if params[:datefilter].present?
    # session[:dashboard_magic_number] = params[:dashboard_magic_number].present? ? true : false

    
    # dates = "#{date_today} - #{date_today}"
    @timezone = params[:timezone].present? ? params[:timezone] : Time.zone.formatted_offset
    # session[:dates] = params[:datefilter]
    if params[:datefilter].blank?# and session[:date_begin].nil? and session[:date_end].nil?
      dates = dashboard_date_filter_set
      session[:dates] = dates
      session[:date_begin] = dates.split("-")[0]
      session[:date_end] = dates.split("-")[1]					

    else
      if params[:datefilter].present? 
        dates = params[:datefilter].split("-")
        if dates[0] != session[:date_begin] or dates[1] != session[:date_end]
          session[:dates] = params[:datefilter]
          session[:date_begin] = dates[0]
          session[:date_end] = dates[1]					
        end
      else
        session[:dates] = "#{session[:date_begin]} - #{session[:date_end]}"
      end
    end
  end


  def dashboard_date_filter_set
    date_today = Date.today
    case @current_store.try(:dashboard_date_filter)
    when "1_month"
      "#{((date_today - 1.month).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    when "3_months"
      "#{((date_today - 3.month).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    when "6_months"
      "#{((date_today - 6.month).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    when "1_year"
      "#{((date_today - 1.year).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    when "2_years"
      "#{((date_today - 2.years).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    when "3_years"
      "#{((date_today - 3.years).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    else
      "#{((date_today - 3.month).beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
    end
    
  end


end