module ExternalApiHelper
  require 'oj'
  def self.get_api_call url
    uri = URI.parse(URI.encode(url))
    begin
      response = Net::HTTP.get_response(uri)
      if response.code == "200"
        JSON.parse(response.body) rescue nil 
      else
        log_network_call_error(url, response.code, response.body)
      end
    rescue => exception
      log_network_call_error(url, exception.class, "Net::HTTP Error")
    end    
  end

  def self.log_network_call_error(url, code, response_body)
    log_file = Logger.new("#{Rails.root}/log/network_call_error.log")
    log_file.info "Got response #{code} #{response_body} from url: #{url}."
    nil
  end
end

