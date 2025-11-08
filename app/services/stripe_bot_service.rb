# frozen_string_literal: true

require "stripe"

# Service for making Stripe API calls for bot integrations
# No Pay gem - direct Stripe API usage
class StripeBotService
  def initialize
    # Get Stripe secret key from credentials (private_key is the secret key)
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :private_key) || ENV.fetch("STRIPE_SECRET_KEY", nil)
    raise "Stripe API key not configured. Add stripe.private_key to Rails credentials." if Stripe.api_key.blank?
  end

  # Fetch price details from Stripe API
  # Returns array of active (non-archived) prices
  def fetch_prices(price_ids)
    return [] if price_ids.blank?

    prices = []
    price_ids.each do |price_id|
      price = Stripe::Price.retrieve(price_id)

      # Only include active prices (archived prices have active: false)
      prices << price if price.active
    rescue Stripe::InvalidRequestError => e
      Rails.logger.warn "Stripe price #{price_id} not found or invalid: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Error fetching Stripe price #{price_id}: #{e.message}"
    end

    prices
  end

  # Create Stripe checkout session
  # Returns checkout session URL
  # bot_username is optional - defaults to returning to Telegram if not provided
  def create_checkout_session(price_id:, telegram_user_id:, telegram_chat_id:, bot_username: nil, mode: nil)
    price = Stripe::Price.retrieve(price_id)

    # Determine mode: 'subscription' for recurring prices, 'payment' for one-time
    checkout_mode = mode || (price.recurring ? "subscription" : "payment")

    # Use bot username if provided, otherwise use generic Telegram return URL
    return_url = if bot_username.present?
                   "https://t.me/#{bot_username}"
    else
                   "https://t.me"
    end

    session_params = {
      mode: checkout_mode,
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: return_url,
      cancel_url: return_url,
      metadata: {
        telegram_user_id: telegram_user_id.to_s,
        telegram_chat_id: telegram_chat_id.to_s
      }
    }

    # Add subscription_data metadata if it's a subscription
    if checkout_mode == "subscription"
      session_params[:subscription_data] = {
        metadata: {
          telegram_user_id: telegram_user_id.to_s,
          telegram_chat_id: telegram_chat_id.to_s
        }
      }
    end

    # Find or create Stripe customer with Telegram user ID in metadata
    existing_customer = find_customer_by_telegram_id(telegram_user_id: telegram_user_id)

    customer = existing_customer || Stripe::Customer.create(
      metadata: {
        telegram_user_id: telegram_user_id.to_s,
        telegram_chat_id: telegram_chat_id.to_s
      }
    )

    session_params[:customer] = customer.id

    session = Stripe::Checkout::Session.create(session_params)
    session.url
  rescue StandardError => e
    Rails.logger.error "Failed to create Stripe checkout session: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    nil
  end

  # Get subscription status for a Telegram user
  # Searches Stripe customers by metadata, then finds their subscription
  # Also searches by telegram_chat_id as fallback (in case they match)
  def get_subscription_status(telegram_user_id:)
    # Search for customer by Telegram user ID in metadata
    customers = Stripe::Customer.search(
      query: "metadata['telegram_user_id']:'#{telegram_user_id}'"
    )

    # Try to find a customer with an active subscription
    result = find_subscription_in_customers(customers.data)

    # If no active subscription found, try searching by telegram_chat_id as fallback
    # (sometimes chat_id == telegram_user_id in private chats, or there's a mismatch)
    # Also try fallback if we found customers but none had active subscriptions
    if result[:status] == :none
      customers_chat = Stripe::Customer.search(
        query: "metadata['telegram_chat_id']:'#{telegram_user_id}'"
      )
      result = find_subscription_in_customers(customers_chat.data) unless customers_chat.data.empty?
    end

    result
  rescue StandardError => e
    Rails.logger.error "Failed to get subscription status: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    { status: :error, subscription: nil }
  end

  # Helper method to find subscription status in a list of customers
  def find_subscription_in_customers(customers)
    return { status: :none, subscription: nil } if customers.empty?

    active_sub = nil
    cancelled_sub = nil
    trialing_sub = nil
    found_customer = nil

    # Check each customer for subscriptions
    customers.each do |customer|
      subscriptions = Stripe::Subscription.list(
        customer: customer.id,
        status: "all",
        limit: 10
      )

      # Look for active subscription
      active = subscriptions.data.find { |s| s.status == "active" }
      if active
        active_sub = active
        found_customer = customer
        break # Found active subscription, stop searching
      end

      # Also check for trialing (but keep looking for active)
      trialing = subscriptions.data.find { |s| s.status == "trialing" }
      if trialing && trialing_sub.nil?
        trialing_sub = trialing
        found_customer = customer if found_customer.nil?
      end

      # And cancelled (but keep looking for active/trialing)
      cancelled = subscriptions.data.find { |s| %w[canceled cancelled unpaid past_due].include?(s.status) }
      if cancelled && cancelled_sub.nil? && trialing_sub.nil?
        cancelled_sub = cancelled
        found_customer = customer if found_customer.nil?
      end
    end

    # Return appropriate status
    if active_sub
      if active_sub.cancel_at_period_end
        {
          status: :expiring,
          subscription: active_sub,
          customer: found_customer,
          ends_at: active_sub.current_period_end
        }
      else
        {
          status: :active,
          subscription: active_sub,
          customer: found_customer
        }
      end
    elsif trialing_sub
      {
        status: :active, # Treat trialing as active
        subscription: trialing_sub,
        customer: found_customer
      }
    elsif cancelled_sub
      ends_at = cancelled_sub.cancel_at || cancelled_sub.current_period_end || cancelled_sub.ended_at
      {
        status: :cancelled,
        subscription: cancelled_sub,
        customer: found_customer,
        ends_at: ends_at
      }
    else
      {
        status: :none,
        subscription: nil,
        customer: customers.first # Return first customer even if no subscription
      }
    end
  rescue StandardError => e
    Rails.logger.error "Failed to find subscription in customers: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    { status: :error, subscription: nil }
  end

  # Get customer by Telegram user ID from metadata
  # Also tries telegram_chat_id as fallback
  def find_customer_by_telegram_id(telegram_user_id:)
    customers = Stripe::Customer.search(
      query: "metadata['telegram_user_id']:'#{telegram_user_id}'"
    )

    # If no customer found, also try searching by telegram_chat_id
    if customers.data.empty?
      customers = Stripe::Customer.search(
        query: "metadata['telegram_chat_id']:'#{telegram_user_id}'"
      )
    end

    customers.data.first
  rescue StandardError => e
    Rails.logger.error "Failed to find customer: #{e.message}"
    nil
  end

  # Create a Stripe billing portal session for subscription management
  # Returns the portal session URL
  def create_billing_portal_session(customer_id:, return_url:)
    session = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: return_url
    )
    session.url
  rescue StandardError => e
    Rails.logger.error "Failed to create billing portal session: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    nil
  end
end
