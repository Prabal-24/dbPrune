class AppConfig
  def initialize
    @config={}
  end

  private

  def method_missing(method_name, *arguments, &block)
    if method_name.to_s =~ /=$/
      @config[$`.to_sym]=arguments.first
    elsif @config.has_key?(method_name)
      @config[method_name]
    else  
      super
    end 
  end

  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s =~ /=$/ or @config.has_key? method_name
  end
end  