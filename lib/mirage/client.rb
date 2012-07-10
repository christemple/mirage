$LOAD_PATH.unshift "#{File.dirname(__FILE__)}"
require 'uri'
require 'waitforit'
require 'childprocess'
require 'client/web'
require 'util'
require 'cli'
require 'ostruct'

module Mirage

  class << self
    def start args={}

      args = convert_to_command_line_argument_array(args) if args.is_a? Hash

      process = Mirage::CLI.run args
      mirage_client = Mirage::Client.new "http://localhost:#{Mirage::CLI.parse_options(args)[:port]}/mirage", process
      wait_until :timeout_after => 30.seconds do
        mirage_client.running?
      end

      begin
        mirage_client.prime
      rescue Mirage::InternalServerException => e
        puts "WARN: #{e.message}"
      end
      mirage_client
    end

    def convert_to_command_line_argument_array(args)
      command_line_arguments = {}
      args.each do |key, value|
        command_line_arguments["--#{key}"] = "#{value}"
      end
      command_line_arguments.to_a.flatten
    end

    def stop
      puts "Stopping Mirage"
      Mirage::CLI.stop
    end
  end

  class MirageError < ::Exception
    attr_reader :code

    def initialize message, code
      super message
      @code = message, code
    end
  end

  class Response < OpenStruct

    attr_accessor :content_type
    attr_reader :value

    def initialize response
      @content_type = 'text/plain'
      @value = response
      super({})
    end

    def headers
      headers = {}

      @table.each { |header, value| headers["X-mirage-#{header.to_s.gsub('_', '-')}"] = value }
      headers['Content-Type']=@content_type
      headers['X-mirage-file'] = 'true' if @response.kind_of?(IO)

      headers
    end

  end

  class InternalServerException < MirageError;
  end

  class ResponseNotFound < MirageError;
  end

  class Client
    include ::Mirage::Web
    attr_reader :url

    # Creates an instance of the MIrage client that can be used to interact with the Mirage Server
    #
    #   Client.new => a client that is configured to connect to Mirage on http://localhost:7001/mirage (the default settings for Mirage)
    #   Client.new(URL) => a client that is configured to connect to an instance of Mirage running on the specified url.
    def initialize url="http://localhost:7001/mirage", process=nil
      @url = url
      @process = process
    end


    # Set a text or file based response template, to be hosted at a given end point. A block can be specified to configure the template
    # Client.set(endpoint, response, &block) => unique id that can be used to call back to the server
    #
    # Examples:
    # Client.put('greeting', 'hello')
    #
    # Client.put('greeting', 'hello') do |response|
    #   response.pattern = 'pattern' #regex or string literal applied against the request querystring and body
    #   response.method = :post #By default templates will respond to get requests
    #   response.content_type = 'text/html' #defaults text/plain
    #   response.default = true # defaults to false. setting to true will allow this template to respond to request made to sub resources should it match.
    # end
    def put endpoint, response_value, &block
      response = Response.new response_value

      yield response if block_given?

      build_response(http_put("#{@url}/templates/#{endpoint}", response.value, response.headers))
    end

    # Use to look at what a response contains without actually triggering it.
    # client.response(response_id) => response held on the server as a String
    def response response_id
      response = build_response(http_get("#{@url}/templates/#{response_id}"))
      case response
        when String then
          return response
        when Mirage::Web::FileResponse then
          return response.response.body
      end

    end

    # Clear Content from Mirage
    #
    # If a response id is not valid, a ResponseNotFound exception will be thrown
    #
    #   Examples:
    #   Client.new.clear # clear all responses and associated requests
    #   Client.new.clear(response_id) # Clear the response and tracked request for a given response id
    #   Client.new.clear(:requests) # Clear all tracked request information
    #   Client.new.clear(:request => response_id) # Clear the tracked request for a given response id
    def clear thing=nil

      case thing
        when :requests
          http_delete("#{@url}/requests")
        when Numeric then
          http_delete("#{@url}/templates/#{thing}")
        when Hash then
          puts "deleteing request #{thing[:request]}"
          http_delete("#{@url}/requests/#{thing[:request]}") if thing[:request]
        else
          NilClass
          http_delete("#{@url}/templates")
      end

    end


    # Retrieve the last request that triggered a response to be returned. If the request contained content in its body, this is returned. If the
    # request did not have any content in its body then what ever was in the request query string is returned instead
    #
    #   Example:
    #   Client.new.track(response_id) => Tracked request as a String
    def request response_id
      build_response(http_get("#{@url}/requests/#{response_id}"))
    end

    # Save the state of the Mirage server so that it can be reverted back to that exact state at a later time.
    def save
      http_put("#{@url}/backup", '').code == 200
    end


    # Revert the state of Mirage back to the state that was last saved
    # If there is no snapshot to rollback to, nothing happens
    def revert
      http_put("#{@url}", '').code == 200
    end


    # Check to see if Mirage is up and running
    def running?
      begin
        http_get(@url) and return true
      rescue Errno::ECONNREFUSED
        return false
      end
    end

    # Clear down the Mirage Server and load any defaults that are in Mirages default responses directory.
    def prime
      puts "#{@url}/defaults"
      build_response(http_put("#{@url}/defaults", ''))
    end

    def stop
      @process.stop
      wait_until{!running?}
    end

    private
    def build_response response
      case response.code.to_i
        when 500 then
          raise ::Mirage::InternalServerException.new(response.body, response.code.to_i)
        when 404 then
          raise ::Mirage::ResponseNotFound.new(response.body, response.code.to_i)
        else
          response.body
      end
    end

  end


end