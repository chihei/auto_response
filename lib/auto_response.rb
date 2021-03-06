require 'xmlrpc/httpserver'
require 'open-uri'
require 'fileutils'
require 'listen'
require 'colorize'
require 'logger'
require 'socket'

require 'ar/version'
require 'ar/proxy_server'
require 'ar/rule_manager'
require 'ar/parser'
require 'ar/session_viewer'

module AutoResp


  class AutoResponder

    ARHOME = "#{ENV["HOME"]}/.auto_response"
    RULES  = "#{ARHOME}/rules"

    def initialize(config = {})

      @config             = config
      @rule_manager       = RuleManager.new
      @logger             = init_logger

      @logger.debug { "Starting AutoResp v#{VERSION}" }
      @logger.debug { "Listening at " << "#{ip_address}:#{proxy_port}".yellow }

      init_autoresponse_home
      load_rules
      monitor_rules_change
    end
    
    protected

    def init_logger
      Logger.new( $stderr, Logger::WARN ).tap do |logger|
        logger.formatter = proc do |serverity, datetime, prog, msg|
          indent = {
            :debug  => '--',
            :info   => '  ',
            :warn   => '[W]',
            :error  => '[E]',
            :fatal  => '[F]'
          }[serverity.downcase.to_sym]
          "#{indent} #{msg}\n"
        end
      end
    end

    def ip_address
      Socket.ip_address_list.detect {|intf| intf.ipv4_private? }.ip_address
    end

    def init_autoresponse_home
      unless File.exist?(RULES)
        pwd = File.expand_path('..', File.dirname(__FILE__))
        FileUtils.mkdir_p(ARHOME) 
        FileUtils.cp "#{pwd}/rules.sample", RULES
      end
    end

    protected
    def init_proxy_server
      @server = ProxyServer.new(
        self,
        :BindAddress  => @config[:host] || '0.0.0.0',
        :Port         => proxy_port,
        :logger       => @logger
      )
      trap('INT') { stop_and_exit }
      @server
    end

    def proxy_port
      @config[:port] || 9000
    end

    def start_proxy
      @proxy_thread = Thread.new { init_proxy_server.start }
    end

    def start_viewer
      @viewer_thread = Thread.new {}
      SessionViewer.new( @server ).run 
    end

    public
    def start
      log_rules
      start_proxy
      start_viewer
    end

    def stop_and_exit
      stop
      exit
    end

    def stop
      @server.shutdown
      @viewer_thread.kill
      @proxy_thread.kill
    end

    def add_rule(*args, &block)
      case args.first
      when Hash
        rules.merge! args.first
      when String
        rules[args[0]] = args[1]
      when Regexp
        if block_given?
          rules[args[0]] = block
        else
          rules[args[0]] = args[1]
        end
      end
    end

    def rules
      @rule_manager.rules
    end

    def clear_rules
      rules.clear
    end

    private
    def load_rules(path=nil)
      path ||= @config[:rule_config] || "#{ARHOME}/rules"
      if File.readable?(path)
        begin
          @rule_manager.instance_eval File.read(path)
        rescue SyntaxError => e
          @logger.fatal "You have syntax error in your rules file, please check it"
          exit 1
        end
      end
    end

    def log_rules
      @logger.debug "Mapping rules:"
      rules.each do |n,v|
        @logger.info ""
        @logger.info n.to_s.ljust(30).green 
        @logger.info "=> #{v}"
      end
    end

    def monitor_rules_change
      listener = Listen.to(ARHOME) { reload_rules }
      Thread.new { listener.start }
    end

    def reload_rules
      @rule_manager.clear
      load_rules
    end

  end

end

