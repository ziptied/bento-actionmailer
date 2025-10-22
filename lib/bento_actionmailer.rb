# frozen_string_literal: true

require "bento_actionmailer/version"
require "bento_actionmailer/railtie" if defined? Rails

require "net/http"
require "uri"
require "json"

module BentoActionMailer
  class DeliveryMethod
    class DeliveryError < StandardError
      attr_reader :response_code, :error_details

      def initialize(message, response_code: nil, error_details: nil)
        super(message)
        @response_code = response_code
        @error_details = error_details
      end
    end

    BENTO_ENDPOINT = URI.parse("https://app.bentonow.com/api/v1/batch/emails")

    DEFAULTS = {
      transactional: true
    }.freeze

    UNAUTHORIZED_AUTHOR_ERROR = "Author not authorized to send on this account"
    UNKNOWN_RESPONSE_MESSAGE = "Unknown response"

    attr_accessor :settings

    def initialize(params = {})
      self.settings = DEFAULTS.merge(params)
    end

    def deliver!(mail)
      html_body = mail.body.parts.find { |p| p.content_type =~ /text\/html/ }
      raise DeliveryError, "No HTML body given. Bento requires an html email body." unless html_body

      send_mail(
        to: mail.to.first,
        from: mail.from.first,
        subject: mail.subject,
        html_body: html_body.decoded,
        personalization: {}
      )
    end

    private

    def send_mail(to:, from:, subject:, html_body:, personalization: {})
      import_data = [
        {
          to: to,
          from: from,
          subject: subject,
          html_body: html_body,
          transactional: settings[:transactional],
          personalizations: personalization
        }
      ]

      request = Net::HTTP::Post.new(BENTO_ENDPOINT)
      request.basic_auth(settings[:publishable_key], settings[:secret_key])
      request.body = JSON.dump({ site_uuid: settings[:site_uuid], emails: import_data })
      request.content_type = "application/json"
      req_options = { use_ssl: BENTO_ENDPOINT.scheme == "https" }

      response = Net::HTTP.start(BENTO_ENDPOINT.hostname, BENTO_ENDPOINT.port, req_options) do |http|
        http.request(request)
      end

      handle_response(response)
    end

    def handle_response(response)
      status = response.code.to_i
      return if success_response?(status)

      error_data = parse_error_response(response)
      error_message = error_data&.dig("error") || response.message || UNKNOWN_RESPONSE_MESSAGE

      case status
      when 401, 403
        raise_authorization_error(status, error_data, error_message)
      when 400..499
        raise build_delivery_error("Client error: #{error_message}", status, error_data)
      when 500..599
        raise build_delivery_error("Bento API server error: #{error_message}", status, error_data)
      else
        raise build_delivery_error("Unexpected response: #{status} #{error_message}", status, error_data)
      end
    end

    def parse_error_response(response)
      body = response.body
      return nil if body.nil?

      body = body.strip
      return nil if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def raise_authorization_error(status, error_data, error_message)
      if error_message == UNAUTHORIZED_AUTHOR_ERROR
        raise build_delivery_error(UNAUTHORIZED_AUTHOR_ERROR, status, error_data)
      end

      sanitized_message = error_message
      sanitized_message = nil if sanitized_message == UNKNOWN_RESPONSE_MESSAGE
      sanitized_message = sanitized_message&.strip
      message = sanitized_message && !sanitized_message.empty? ? "Authorization failed: #{sanitized_message}" : "Authorization failed"
      raise build_delivery_error(message, status, error_data)
    end

    def success_response?(status)
      status.between?(200, 299)
    end

    def build_delivery_error(message, status, error_data)
      DeliveryError.new(message, response_code: status, error_details: error_data)
    end
  end
end
